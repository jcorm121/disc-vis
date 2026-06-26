import CoreVideo
import Foundation
import Metal
import MetalPerformanceShaders
import QuartzCore
import simd

struct HeatmapUniforms {
    var axisWeights: SIMD3<Float>
    var weightEpsilon: Float
    var targetCount: UInt32
    var backgroundCount: UInt32
    var overlayOpacity: Float
    var overlayScoreFloor: Float
    var palette: UInt32
    var scoreGamma: Float
}

struct MetalSignature {
    var lab: SIMD3<Float>
}

/// GPU pipeline for continuous Lab discriminative heatmaps.
final class LabHeatmapEngine {
    let device: MTLDevice
    private let commandQueue: MTLCommandQueue
    private let labPipeline: MTLComputePipelineState
    private let scorePipeline: MTLComputePipelineState
    private let renderPipeline: MTLRenderPipelineState
    private let gaussianBlur: MPSImageGaussianBlur
    private let bilinearScale: MPSImageBilinearScale
    private let scoreUpscale: MPSImageBilinearScale

    private var textureCache: CVMetalTextureCache?
    private var reference: ReferenceSignatureModel?
    private var backgroundSignatures: [SIMD3<Float>] = []
    private var axisWeights: SIMD3<Float> = SIMD3(repeating: 1)
    private var frameCounter = 0

    private var internalWidth = 0
    private var internalHeight = 0
    private var labTexture: MTLTexture?
    private var scoreTexture: MTLTexture?
    private var blurredScoreTexture: MTLTexture?
    private var fullResScoreTexture: MTLTexture?
    private var reducedBGRATexture: MTLTexture?
    private var targetSignatureBuffer: MTLBuffer?
    private var backgroundSignatureBuffer: MTLBuffer?

    private let processingQueue = DispatchQueue(label: "discvis.heatmap.processing", qos: .userInitiated)
    private let lock = NSLock()
    private var latestCameraTexture: MTLTexture?
    private var latestScoreTexture: MTLTexture?
    private var heatmapEnabled = false

    var palette: HeatmapPalette = .whiteHot
    var overlayOpacity: Float = HeatmapConfig.defaultOverlayOpacity

    init?() {
        guard
            let device = MTLCreateSystemDefaultDevice(),
            let commandQueue = device.makeCommandQueue(),
            let library = device.makeDefaultLibrary(),
            let labFunction = library.makeFunction(name: "bgraToLab"),
            let scoreFunction = library.makeFunction(name: "discriminativeScore"),
            let vertexFunction = library.makeFunction(name: "colormapVertex"),
            let fragmentFunction = library.makeFunction(name: "colormapFragment")
        else { return nil }

        self.device = device
        self.commandQueue = commandQueue

        do {
            labPipeline = try device.makeComputePipelineState(function: labFunction)
            scorePipeline = try device.makeComputePipelineState(function: scoreFunction)

            let descriptor = MTLRenderPipelineDescriptor()
            descriptor.vertexFunction = vertexFunction
            descriptor.fragmentFunction = fragmentFunction
            descriptor.colorAttachments[0].pixelFormat = .bgra8Unorm
            renderPipeline = try device.makeRenderPipelineState(descriptor: descriptor)

            gaussianBlur = MPSImageGaussianBlur(device: device, sigma: HeatmapConfig.probabilityBlurSigma)
            bilinearScale = MPSImageBilinearScale(device: device)
            scoreUpscale = MPSImageBilinearScale(device: device)
        } catch {
            return nil
        }

        var cache: CVMetalTextureCache?
        CVMetalTextureCacheCreate(nil, nil, device, nil, &cache)
        textureCache = cache
    }

    func setReference(_ model: ReferenceSignatureModel?) {
        lock.lock()
        reference = model
        heatmapEnabled = model != nil
        if let model {
            targetSignatureBuffer = makeSignatureBuffer(
                signatures: model.targetSignatures,
                maxCount: HeatmapConfig.maxTargetSignatures
            )
        } else {
            targetSignatureBuffer = nil
        }
        backgroundSignatures = []
        backgroundSignatureBuffer = nil
        frameCounter = 0
        lock.unlock()
    }

    func processFrame(_ pixelBuffer: CVPixelBuffer) {
        processingQueue.async { [weak self] in
            self?.processFrameOnQueue(pixelBuffer)
        }
    }

    func render(to drawable: CAMetalDrawable) {
        lock.lock()
        let cameraTexture = latestCameraTexture
        let scoreTexture = latestScoreTexture
        let enabled = heatmapEnabled
        let uniforms = uniformsSnapshot()
        lock.unlock()

        guard let cameraTexture else { return }

        guard
            let commandBuffer = commandQueue.makeCommandBuffer(),
            let renderPass = makeRenderPass(for: drawable.texture, commandBuffer: commandBuffer)
        else { return }

        renderPass.setRenderPipelineState(renderPipeline)
        renderPass.setFragmentTexture(cameraTexture, index: 0)
        renderPass.setFragmentTexture(enabled ? (scoreTexture ?? cameraTexture) : cameraTexture, index: 1)
        var fragmentUniforms = uniforms
        if !enabled {
            fragmentUniforms.overlayOpacity = 0
        }
        renderPass.setFragmentBytes(&fragmentUniforms, length: MemoryLayout<HeatmapUniforms>.stride, index: 0)
        renderPass.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)
        renderPass.endEncoding()

        commandBuffer.present(drawable)
        commandBuffer.commit()
    }

    // MARK: - Processing

    private func processFrameOnQueue(_ pixelBuffer: CVPixelBuffer) {
        guard let cameraTexture = makeTexture(from: pixelBuffer) else { return }

        lock.lock()
        latestCameraTexture = cameraTexture
        let reference = reference
        let enabled = heatmapEnabled
        lock.unlock()

        guard enabled, let reference else { return }

        ensureInternalTextures(for: cameraTexture)
        ensureFullResScoreTexture(for: cameraTexture)

        guard
            let reducedBGRATexture,
            let labTexture,
            let scoreTexture,
            let blurredScoreTexture,
            let fullResScoreTexture,
            let commandBuffer = commandQueue.makeCommandBuffer()
        else { return }

        bilinearScale.encode(commandBuffer: commandBuffer, sourceTexture: cameraTexture, destinationTexture: reducedBGRATexture)
        encodeLabConversion(commandBuffer: commandBuffer, input: reducedBGRATexture, output: labTexture)

        let sceneStats = readSceneStatistics(from: labTexture)
        let weights = computeAxisWeights(target: reference, sceneMean: sceneStats.mean, sceneStd: sceneStats.std)

        frameCounter += 1
        if frameCounter % HeatmapConfig.backgroundRecomputeInterval == 1 || backgroundSignatures.isEmpty {
            updateBackgroundSignatures(from: labTexture, weights: weights)
        }

        guard
            let targetSignatureBuffer,
            let backgroundSignatureBuffer,
            !backgroundSignatures.isEmpty
        else { return }

        var uniforms = currentUniforms(axisWeights: weights)
        uniforms.targetCount = UInt32(min(reference.targetSignatures.count, HeatmapConfig.maxTargetSignatures))
        uniforms.backgroundCount = UInt32(min(backgroundSignatures.count, HeatmapConfig.maxBackgroundSignatures))

        encodeScore(
            commandBuffer: commandBuffer,
            labTexture: labTexture,
            scoreTexture: scoreTexture,
            uniforms: uniforms,
            targetBuffer: targetSignatureBuffer,
            backgroundBuffer: backgroundSignatureBuffer
        )

        gaussianBlur.encode(commandBuffer: commandBuffer, sourceTexture: scoreTexture, destinationTexture: blurredScoreTexture)
        scoreUpscale.encode(commandBuffer: commandBuffer, sourceTexture: blurredScoreTexture, destinationTexture: fullResScoreTexture)

        commandBuffer.commit()
        commandBuffer.waitUntilCompleted()

        lock.lock()
        axisWeights = weights
        latestScoreTexture = fullResScoreTexture
        lock.unlock()
    }

    private func updateBackgroundSignatures(from labTexture: MTLTexture, weights: SIMD3<Float>) {
        guard let labPixels = readLabPixels(from: labTexture) else { return }
        let sampled = KMeansLab.subsample(labPixels, count: HeatmapConfig.scenePixelSampleCount)
        let weighted = sampled.map { $0 / weights }
        let centroids = KMeansLab.cluster(pixels: weighted, count: HeatmapConfig.backgroundDominantColorCount)
        backgroundSignatures = centroids.map { $0 * weights }
        backgroundSignatureBuffer = makeSignatureBuffer(
            signatures: backgroundSignatures,
            maxCount: HeatmapConfig.maxBackgroundSignatures
        )
    }

    private func currentUniforms(axisWeights override: SIMD3<Float>? = nil) -> HeatmapUniforms {
        lock.lock()
        defer { lock.unlock() }
        return uniformsSnapshot(axisWeights: override)
    }

    /// Reads uniform fields; caller must not hold ``lock``.
    private func uniformsSnapshot(axisWeights override: SIMD3<Float>? = nil) -> HeatmapUniforms {
        let weights = override ?? axisWeights
        let targetCount = reference?.targetSignatures.count ?? 0
        let backgroundCount = backgroundSignatures.count
        let paletteValue = palette
        let opacity = overlayOpacity

        return HeatmapUniforms(
            axisWeights: weights,
            weightEpsilon: HeatmapConfig.weightEpsilon,
            targetCount: UInt32(targetCount),
            backgroundCount: UInt32(backgroundCount),
            overlayOpacity: opacity,
            overlayScoreFloor: HeatmapConfig.overlayScoreFloor,
            palette: UInt32(paletteValue.rawValue),
            scoreGamma: HeatmapConfig.scoreGamma
        )
    }

    private func computeAxisWeights(
        target: ReferenceSignatureModel,
        sceneMean: SIMD3<Float>,
        sceneStd: SIMD3<Float>
    ) -> SIMD3<Float> {
        let epsilon = HeatmapConfig.axisWeightEpsilon
        let delta = abs(target.targetMean - sceneMean)
        let weights = (target.targetStd + sceneStd) / (delta + SIMD3(repeating: epsilon))
        return SIMD3(max(weights.x, 1e-4), max(weights.y, 1e-4), max(weights.z, 1e-4))
    }

    private func ensureInternalTextures(for cameraTexture: MTLTexture) {
        let longEdge = max(cameraTexture.width, cameraTexture.height)
        let scale = Float(HeatmapConfig.internalMaxDimension) / Float(longEdge)
        let width = max(1, Int((Float(cameraTexture.width) * scale).rounded()))
        let height = max(1, Int((Float(cameraTexture.height) * scale).rounded()))

        if width == internalWidth, height == internalHeight, labTexture != nil { return }

        internalWidth = width
        internalHeight = height
        reducedBGRATexture = makePrivateTexture(width: width, height: height, pixelFormat: .bgra8Unorm)
        labTexture = makePrivateTexture(width: width, height: height, pixelFormat: .rgba32Float)
        scoreTexture = makePrivateTexture(width: width, height: height, pixelFormat: .r32Float)
        blurredScoreTexture = makePrivateTexture(width: width, height: height, pixelFormat: .r32Float)
    }

    private func ensureFullResScoreTexture(for cameraTexture: MTLTexture) {
        if fullResScoreTexture?.width == cameraTexture.width,
           fullResScoreTexture?.height == cameraTexture.height {
            return
        }
        fullResScoreTexture = makePrivateTexture(
            width: cameraTexture.width,
            height: cameraTexture.height,
            pixelFormat: .r32Float
        )
    }

    private func makePrivateTexture(width: Int, height: Int, pixelFormat: MTLPixelFormat) -> MTLTexture? {
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: pixelFormat,
            width: width,
            height: height,
            mipmapped: false
        )
        descriptor.usage = [.shaderRead, .shaderWrite]
        descriptor.storageMode = .private
        return device.makeTexture(descriptor: descriptor)
    }

    private func makeTexture(from pixelBuffer: CVPixelBuffer) -> MTLTexture? {
        guard let textureCache else { return nil }

        let width = CVPixelBufferGetWidth(pixelBuffer)
        let height = CVPixelBufferGetHeight(pixelBuffer)
        var cvTexture: CVMetalTexture?
        let status = CVMetalTextureCacheCreateTextureFromImage(
            nil,
            textureCache,
            pixelBuffer,
            nil,
            .bgra8Unorm,
            width,
            height,
            0,
            &cvTexture
        )
        guard status == kCVReturnSuccess, let cvTexture, let texture = CVMetalTextureGetTexture(cvTexture) else {
            return nil
        }
        return texture
    }

    private func encodeLabConversion(commandBuffer: MTLCommandBuffer, input: MTLTexture, output: MTLTexture) {
        guard let encoder = commandBuffer.makeComputeCommandEncoder() else { return }
        encoder.setComputePipelineState(labPipeline)
        encoder.setTexture(input, index: 0)
        encoder.setTexture(output, index: 1)
        dispatchThreads(encoder: encoder, width: output.width, height: output.height)
        encoder.endEncoding()
    }

    private func encodeScore(
        commandBuffer: MTLCommandBuffer,
        labTexture: MTLTexture,
        scoreTexture: MTLTexture,
        uniforms: HeatmapUniforms,
        targetBuffer: MTLBuffer,
        backgroundBuffer: MTLBuffer
    ) {
        guard let encoder = commandBuffer.makeComputeCommandEncoder() else { return }
        encoder.setComputePipelineState(scorePipeline)
        encoder.setTexture(labTexture, index: 0)
        encoder.setTexture(scoreTexture, index: 1)
        var mutableUniforms = uniforms
        encoder.setBytes(&mutableUniforms, length: MemoryLayout<HeatmapUniforms>.stride, index: 0)
        encoder.setBuffer(targetBuffer, offset: 0, index: 1)
        encoder.setBuffer(backgroundBuffer, offset: 0, index: 2)
        dispatchThreads(encoder: encoder, width: scoreTexture.width, height: scoreTexture.height)
        encoder.endEncoding()
    }

    private func dispatchThreads(encoder: MTLComputeCommandEncoder, width: Int, height: Int) {
        let threadGroupSize = MTLSize(width: 16, height: 16, depth: 1)
        let threadGroups = MTLSize(
            width: (width + 15) / 16,
            height: (height + 15) / 16,
            depth: 1
        )
        encoder.dispatchThreadgroups(threadGroups, threadsPerThreadgroup: threadGroupSize)
    }

    private func makeSignatureBuffer(signatures: [SIMD3<Float>], maxCount: Int) -> MTLBuffer? {
        let capped = Array(signatures.prefix(maxCount))
        guard !capped.isEmpty else { return nil }
        let metalSignatures = capped.map { MetalSignature(lab: $0) }
        return device.makeBuffer(
            bytes: metalSignatures,
            length: MemoryLayout<MetalSignature>.stride * metalSignatures.count,
            options: .storageModeShared
        )
    }

    private func readSceneStatistics(from labTexture: MTLTexture) -> (mean: SIMD3<Float>, std: SIMD3<Float>) {
        guard let pixels = readLabPixels(from: labTexture), !pixels.isEmpty else {
            return (SIMD3(repeating: 0), SIMD3(repeating: 1))
        }

        var mean = SIMD3<Float>(repeating: 0)
        for pixel in pixels { mean += pixel }
        mean /= Float(pixels.count)

        var variance = SIMD3<Float>(repeating: 0)
        for pixel in pixels {
            let delta = pixel - mean
            variance += delta * delta
        }
        variance /= Float(pixels.count)
        return (mean, SIMD3(sqrt(variance.x), sqrt(variance.y), sqrt(variance.z)))
    }

    private func readLabPixels(from labTexture: MTLTexture) -> [SIMD3<Float>]? {
        let targetWidth = min(labTexture.width, HeatmapConfig.sceneStatsMaxDimension)
        let targetHeight = min(labTexture.height, HeatmapConfig.sceneStatsMaxDimension)

        guard
            let commandBuffer = commandQueue.makeCommandBuffer(),
            let downsampled = makeSharedTexture(width: targetWidth, height: targetHeight, pixelFormat: .rgba32Float)
        else { return nil }

        bilinearScale.encode(commandBuffer: commandBuffer, sourceTexture: labTexture, destinationTexture: downsampled)
        commandBuffer.commit()
        commandBuffer.waitUntilCompleted()

        let rowBytes = targetWidth * 4 * MemoryLayout<Float>.size
        var floats = [Float](repeating: 0, count: targetWidth * targetHeight * 4)
        downsampled.getBytes(
            &floats,
            bytesPerRow: rowBytes,
            from: MTLRegionMake2D(0, 0, targetWidth, targetHeight),
            mipmapLevel: 0
        )

        var pixels: [SIMD3<Float>] = []
        pixels.reserveCapacity(targetWidth * targetHeight)
        for index in stride(from: 0, to: floats.count, by: 4) {
            pixels.append(SIMD3(floats[index], floats[index + 1], floats[index + 2]))
        }
        return pixels
    }

    private func makeSharedTexture(width: Int, height: Int, pixelFormat: MTLPixelFormat) -> MTLTexture? {
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: pixelFormat,
            width: width,
            height: height,
            mipmapped: false
        )
        descriptor.usage = [.shaderRead, .shaderWrite]
        descriptor.storageMode = .shared
        return device.makeTexture(descriptor: descriptor)
    }

    private func makeRenderPass(for texture: MTLTexture, commandBuffer: MTLCommandBuffer) -> MTLRenderCommandEncoder? {
        let passDescriptor = MTLRenderPassDescriptor()
        passDescriptor.colorAttachments[0].texture = texture
        passDescriptor.colorAttachments[0].loadAction = .clear
        passDescriptor.colorAttachments[0].storeAction = .store
        passDescriptor.colorAttachments[0].clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 1)
        return commandBuffer.makeRenderCommandEncoder(descriptor: passDescriptor)
    }
}
