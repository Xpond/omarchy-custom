#version 440

layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;

layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    vec2 resolution;
    float ringRadius;
    float bandWidth;
    float arcFrom;
    float arcSpan;
    float direction;
    float motion;
    float spin;
    vec4 baseColor;
    vec4 tint;
    float presence;
};

layout(binding = 1) uniform sampler2D discMask;

void main() {
    vec2 p = (qt_TexCoord0 - 0.5) * resolution;
    float d = length(p) - ringRadius;
    // Coverage is the only variation across the stroke: no subpixel
    // highlights or secondary edges to shimmer as the circle moves.
    float aa = max(fwidth(d), 0.5);
    float coverage = 1.0 - smoothstep(-aa * 0.5, aa * 0.5, abs(d) - bandWidth * 0.5);
    coverage *= 1.0 - texture(discMask, qt_TexCoord0).a;

    float along = mod(atan(p.y, p.x) - arcFrom, 6.28318530718);
    float angleAA = max(aa / max(ringRadius, 1.0), 0.035);
    float arc = smoothstep(0.0, angleAA, along)
              * (1.0 - smoothstep(arcSpan - angleAA, arcSpan, along)) * presence;
    // The tail fades toward the resting ring; reversing swaps its ends.
    // At rest, retain the even bracket around the selected disc.
    float progress = clamp(along / max(arcSpan, angleAA), 0.0, 1.0);
    float tail = smoothstep(0.0, 1.0, direction > 0.0 ? progress : 1.0 - progress);
    arc *= mix(1.0, tail, motion);
    // Resting ring and trail share one stroke, including its antialiasing.
    vec4 resting = vec4(baseColor.rgb * 0.14, baseColor.a * 0.14);
    resting *= 1.0 - spin;
    vec4 lit = vec4(tint.rgb * 0.72, tint.a * 0.72);
    fragColor = mix(resting, lit, arc) * coverage * qt_Opacity;
}
