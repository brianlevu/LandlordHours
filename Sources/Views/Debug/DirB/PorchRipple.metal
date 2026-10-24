#include <metal_stdlib>
#include <SwiftUI/SwiftUI_Metal.h>
using namespace metal;

// Direction B (Porch Light) DEBUG mock: the goal-reached ripple of light across the sky.
// After Apple's WWDC24 ripple sample: a decaying radial wave that also lifts brightness.
[[ stitchable ]] half4 porchRipple(float2 position, SwiftUI::Layer layer, float2 origin, float time,
                                   float amplitude, float frequency, float decay, float speed) {
    float dist = length(position - origin);
    float t = max(0.0, time - dist / speed);
    float wave = amplitude * sin(frequency * t) * exp(-decay * t);
    float2 n = dist > 0.0 ? (position - origin) / dist : float2(0.0);
    half4 color = layer.sample(position + wave * n);
    float light = (t > 0.0) ? 0.35 * exp(-decay * t) * max(0.0, sin(frequency * t)) : 0.0;
    color.rgb += half3(light, light * 0.82, light * 0.55) * color.a;
    return color;
}
