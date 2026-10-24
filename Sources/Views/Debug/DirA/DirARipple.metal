// Direction A goal ripple (DEBUG mock): one ring across the paper from the house, once a year per goal.
// After Apple's WWDC24 "Create custom visual effects with SwiftUI" ripple.
#include <metal_stdlib>
#include <SwiftUI/SwiftUI.h>
using namespace metal;

[[ stitchable ]]
half4 daRipple(float2 position, SwiftUI::Layer layer, float2 origin, float time,
               float amplitude, float frequency, float decay, float speed) {
    float distance = length(position - origin);
    float delay = distance / speed;
    float t = max(0.0, time - delay);
    float ripple = amplitude * sin(frequency * t) * exp(-decay * t);
    float2 n = distance > 0.001 ? (position - origin) / distance : float2(0.0);
    half4 color = layer.sample(position + ripple * n);
    color.rgb += half(0.18 * (ripple / amplitude)) * color.a;
    return color;
}
