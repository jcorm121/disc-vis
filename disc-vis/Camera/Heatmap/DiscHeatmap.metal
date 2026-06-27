#include <metal_stdlib>
using namespace metal;

struct HeatmapUniforms {
    float3 axisWeights;
    float weightEpsilon;
    uint targetCount;
    uint backgroundCount;
    float overlayOpacity;
    float overlayScoreFloor;
    uint palette;
    float scoreGamma;
    float probabilityThreshold;
    uint displayMode;
};

struct Signature {
    float3 lab;
};

constant float3 kD65White = float3(0.95047, 1.0, 1.08883);

inline float channelSrgbToLinear(float c) {
    return c <= 0.04045 ? (c / 12.92) : pow((c + 0.055) / 1.055, 2.4);
}

inline float3 srgbToLinear(float3 c) {
    return float3(channelSrgbToLinear(c.r), channelSrgbToLinear(c.g), channelSrgbToLinear(c.b));
}

inline float labF(float t) {
    const float delta = 6.0 / 29.0;
    return t > 0.008856 ? pow(t, 1.0 / 3.0) : (t / (3.0 * delta * delta) + 4.0 / 29.0);
}

inline float3 rgbToLab(float3 rgb) {
    float3 linear = srgbToLinear(rgb);
    float x = dot(linear, float3(0.4124564, 0.3575761, 0.1804375));
    float y = dot(linear, float3(0.2126729, 0.7151522, 0.0721750));
    float z = dot(linear, float3(0.0193339, 0.1191920, 0.9503041));

    float fx = labF(x / kD65White.x);
    float fy = labF(y / kD65White.y);
    float fz = labF(z / kD65White.z);

    float L = 116.0 * fy - 16.0;
    float a = 500.0 * (fx - fy);
    float b = 200.0 * (fy - fz);
    return float3(L, a, b);
}

kernel void bgraToLab(texture2d<float, access::read> input [[texture(0)]],
                      texture2d<float, access::write> output [[texture(1)]],
                      uint2 gid [[thread_position_in_grid]]) {
    if (gid.x >= output.get_width() || gid.y >= output.get_height()) return;
    float4 bgra = input.read(gid);
    // CVPixelBuffer BGRA textures from CoreVideo use .rgb component order for correct sRGB.
    float3 rgb = bgra.rgb;
    float3 lab = rgbToLab(rgb);
    output.write(float4(lab, 1.0), gid);
}

inline float minDistance(float3 weightedPixel,
                         constant Signature *signatures,
                         uint count,
                         float3 axisWeights) {
    float best = INFINITY;
    for (uint i = 0; i < count; i++) {
        float3 weightedSignature = signatures[i].lab / axisWeights;
        float d = distance(weightedPixel, weightedSignature);
        best = min(best, d);
    }
    return best;
}

kernel void discriminativeScore(texture2d<float, access::read> labTexture [[texture(0)]],
                                texture2d<float, access::write> scoreTexture [[texture(1)]],
                                constant HeatmapUniforms& uniforms [[buffer(0)]],
                                constant Signature *targetSignatures [[buffer(1)]],
                                constant Signature *backgroundSignatures [[buffer(2)]],
                                uint2 gid [[thread_position_in_grid]]) {
    if (gid.x >= scoreTexture.get_width() || gid.y >= scoreTexture.get_height()) return;

    float3 lab = labTexture.read(gid).rgb;
    float3 weightedPixel = lab / uniforms.axisWeights;

    float dTarget = minDistance(weightedPixel, targetSignatures, uniforms.targetCount, uniforms.axisWeights);
    float dBackground = minDistance(weightedPixel, backgroundSignatures, uniforms.backgroundCount, uniforms.axisWeights);

    float score = dBackground / (dTarget + dBackground + uniforms.weightEpsilon);
    scoreTexture.write(float4(score, score, score, 1.0), gid);
}

inline float3 paletteColor(uint palette, float t) {
    t = clamp(t, 0.0, 1.0);
    switch (palette) {
        case 0: return float3(t);              // white-hot (highlighter)
        case 1: return float3(1.0 - t);        // unused
        default: return float3(t, 0.0, 0.0);   // unused
    }
}

inline float3 ironbowColor(float t) {
    t = clamp(t, 0.0, 1.0);
    const float3 stops[6] = {
        float3(0.0, 0.0, 0.0),
        float3(0.18, 0.0, 0.33),
        float3(0.75, 0.0, 0.0),
        float3(1.0, 0.45, 0.0),
        float3(1.0, 1.0, 0.2),
        float3(1.0, 1.0, 1.0),
    };
    float scaled = t * 5.0;
    int index = int(floor(scaled));
    index = min(index, 4);
    float frac = scaled - float(index);
    return mix(stops[index], stops[index + 1], frac);
}

struct ColormapVertexOut {
    float4 position [[position]];
    float2 texCoord;
};

vertex ColormapVertexOut colormapVertex(uint vertexID [[vertex_id]]) {
    const float2 positions[4] = {
        float2(-1.0, -1.0),
        float2( 1.0, -1.0),
        float2(-1.0,  1.0),
        float2( 1.0,  1.0),
    };
    const float2 texCoords[4] = {
        float2(0.0, 1.0),
        float2(1.0, 1.0),
        float2(0.0, 0.0),
        float2(1.0, 0.0),
    };

    ColormapVertexOut out;
    out.position = float4(positions[vertexID], 0.0, 1.0);
    out.texCoord = texCoords[vertexID];
    return out;
}

fragment float4 colormapFragment(ColormapVertexOut in [[stage_in]],
                                 texture2d<float> cameraTexture [[texture(0)]],
                                 texture2d<float> scoreTexture [[texture(1)]],
                                 constant HeatmapUniforms& uniforms [[buffer(0)]]) {
    constexpr sampler s(filter::linear, address::clamp_to_edge);

    float3 cameraRGB = cameraTexture.sample(s, in.texCoord).rgb;
    float score = scoreTexture.sample(s, in.texCoord).r;
    score = pow(score, uniforms.scoreGamma);

    if (uniforms.displayMode == 0u) {
        float3 heat = ironbowColor(score);
        float3 blended = mix(cameraRGB, heat, uniforms.overlayOpacity);
        return float4(blended, 1.0);
    }

    if (score >= uniforms.probabilityThreshold) {
        float3 highlight = float3(1.0, 0.0, 0.0);
        float3 blended = mix(cameraRGB, highlight, uniforms.overlayOpacity);
        return float4(blended, 1.0);
    }
    return float4(cameraRGB, 1.0);
}
