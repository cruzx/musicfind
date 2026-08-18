#include <metal_stdlib>
#include <SwiftUI/SwiftUI_Metal.h>
using namespace metal;

static float fluidHash(float2 point) {
    point = fract(point * float2(123.34, 456.21));
    point += dot(point, point + 45.32);
    return fract(point.x * point.y);
}

static float fluidNoise(float2 point) {
    float2 cell = floor(point);
    float2 local = fract(point);
    local = local * local * (3.0 - 2.0 * local);

    float a = fluidHash(cell);
    float b = fluidHash(cell + float2(1.0, 0.0));
    float c = fluidHash(cell + float2(0.0, 1.0));
    float d = fluidHash(cell + float2(1.0, 1.0));
    return mix(mix(a, b, local.x), mix(c, d, local.x), local.y);
}

static float fluidFBM(float2 point) {
    float value = 0.0;
    float amplitude = 0.55;
    for (int octave = 0; octave < 4; octave++) {
        value += amplitude * fluidNoise(point);
        point = point * 2.03 + float2(17.13, 9.71);
        amplitude *= 0.48;
    }
    return value;
}

[[ stitchable ]] half4 fluidSwipeMask(
    float2 position,
    half4 color,
    float2 size,
    float progress,
    float direction,
    float time
) {
    float2 safeSize = max(size, float2(1.0));
    float2 uv = position / safeSize;
    float axis = direction >= 0.0 ? 1.0 - uv.x : uv.x;
    float eased = progress * progress * (3.0 - 2.0 * progress);

    float2 flowPoint = float2(uv.x * 2.2 - time * 0.22 * direction, uv.y * 3.4);
    float broadNoise = fluidFBM(flowPoint) - 0.48;
    float fineNoise = fluidNoise(flowPoint * 3.1 + float2(time * 0.16, -time * 0.11)) - 0.5;
    float curl = sin(uv.y * 10.5 + time * 1.25) * 0.035;
    float turbulence = broadNoise * 0.23 + fineNoise * 0.055 + curl;
    turbulence *= mix(1.0, 0.28, eased);

    float front = eased * 1.18 - 0.08 + turbulence;
    float softness = mix(0.025, 0.085, 1.0 - abs(progress * 2.0 - 1.0));
    float alpha = 1.0 - smoothstep(front - softness, front + softness, axis);

    float edgeDistance = abs(axis - front);
    float vapor = fluidNoise(float2(uv.x * 5.0 + time * 0.18, uv.y * 8.0 - time * 0.30));
    float wisps = smoothstep(0.76, 0.96, vapor) * (1.0 - smoothstep(0.02, 0.22, edgeDistance));
    alpha = max(alpha, wisps * smoothstep(0.02, 0.24, eased));
    alpha = progress >= 0.995 ? 1.0 : clamp(alpha, 0.0, 1.0);

    return half4(color.rgb, color.a * half(alpha));
}

[[ stitchable ]] half4 lenticularArtwork(
    float2 position,
    SwiftUI::Layer albumLayer,
    float2 size,
    texture2d<half, access::sample> artistTexture,
    float2 motion,
    float stripeWidth
) {
    constexpr sampler imageSampler(coord::normalized, address::clamp_to_edge, filter::linear);
    float2 safeSize = max(size, float2(1.0));
    float2 uv = clamp(position / safeSize + motion * float2(0.004, 0.002), 0.0, 1.0);
    half4 albumColor = albumLayer.sample(position - motion * float2(1.4, 0.7));
    half4 artistColor = artistTexture.sample(imageSampler, uv);

    float viewAmount = smoothstep(-0.08, 0.68, motion.x + motion.y * 0.16);
    float phase = (position.x / max(stripeWidth, 2.0)) + motion.x * 0.78;
    float rib = sin(phase * 6.2831853);
    float threshold = mix(0.72, -0.72, viewAmount);
    float artistMask = smoothstep(threshold - 0.16, threshold + 0.16, rib);

    float ridge = pow(max(0.0, 1.0 - abs(rib)), 12.0);
    half3 mixedColor = mix(albumColor.rgb, artistColor.rgb, half(artistMask));
    mixedColor += half3(ridge * (0.025 + 0.035 * abs(motion.x)));
    return half4(mixedColor, max(albumColor.a, artistColor.a));
}
