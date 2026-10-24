// Direction C mock (DEBUG screens only): goal reached, one ripple across the pressed page.
// After Apple's WWDC24 "Create custom visual effects with SwiftUI" ripple sample.
#include <metal_stdlib>
#include <SwiftUI/SwiftUI_Metal.h>
using namespace metal;

[[ stitchable ]] half4 dircRipple(float2 position, SwiftUI::Layer layer, float2 origin, float time,
                                  float amplitude, float frequency, float decay, float speed) {
    float distance = length(position - origin);
    float delay = distance / speed;
    time = max(0.0, time - delay);
    float amount = amplitude * sin(frequency * time) * exp(-decay * time);
    float2 n = distance > 0.0 ? normalize(position - origin) : float2(0.0);
    half4 color = layer.sample(position + amount * n);
    // A faint press shadow on the crest, no glow.
    color.rgb -= half(0.06 * (amount / amplitude)) * color.a;
    return color;
}
