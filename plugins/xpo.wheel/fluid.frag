// Adapted from slastra/hyprglaze shaders/fluid.frag, commit 120c508.
// Copyright (c) 2026 Shaun Lastra. MIT license: LICENSE.hyprglaze.
// Six merging fields draw moving contours; no audio or desktop capture.
#version 440

layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;

layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    float phase;
    float reveal;
    float quietRadius;
    vec2 resolution;
    vec4 warm;
    vec4 cool;
    vec3 sun;
    vec3 moon;
};

// Compress the sampled field locally so its contours swell around the light.
// The smooth falloff leaves distant contours on their original paths.
vec2 bend(vec2 p, vec3 body, float radius, float strength, float unit) {
    vec2 d = p - (body.xy - 0.5) * resolution / unit;
    return d * body.z * strength * exp(-dot(d, d) / (radius * radius));
}

void main() {
    float unit = max(1.0, min(resolution.x, resolution.y));
    vec2 p = (qt_TexCoord0 - 0.5) * resolution / unit;
    vec2 fluidPoint = p - bend(p, sun, 0.38, 0.60, unit)
                       - bend(p, moon, 0.23, 0.28, unit);
    // The counted-up day never wraps, so neither does the fluid's motion.
    float t = phase * 5.0;
    float field = 0.0;
    vec3 pigment = vec3(0.0);

    for (int i = 0; i < 6; ++i) {
        float fi = float(i);
        vec2 centre = vec2(
            0.35 * sin(t * (0.3 + fi * 0.07) + fi * 1.5),
            0.35 * cos(t * (0.2 + fi * 0.09) + fi * 2.1)
        ) * resolution / unit;
        float radius = 0.14 + 0.04 * sin(t + fi);
        vec2 d = fluidPoint - centre;
        float contribution = radius * radius / (dot(d, d) + radius * radius);
        field += contribution * 0.65;
        pigment += mix(cool.rgb, warm.rgb, 0.5 + 0.5 * sin(fi * 2.4)) * contribution * 0.65;
    }
    pigment /= max(field, 0.001);

    // Antialiased contour bands retain a constant screen-space thickness.
    float levels = field * 6.0;
    float distanceToLine = abs(fract(levels + 0.5) - 0.5);
    float line = 1.0 - smoothstep(0.0, max(fwidth(levels) * 1.5, 0.005), distanceToLine);
    float presence = smoothstep(0.08, 0.45, field);
    float outside = smoothstep(quietRadius * 0.85, quietRadius * 1.35, length(p) * unit);

    // Leave the sky and blurred desktop visible between the contours.
    // A faint tint gives the fluid body without painting a second backdrop.
    float alpha = presence * outside * (0.025 + 0.65 * line)
                * clamp(reveal, 0.0, 1.0) * qt_Opacity;
    fragColor = vec4(pigment * alpha, alpha);
}
