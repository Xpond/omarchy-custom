#version 440
layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;
layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    vec2 resolution;
    vec2 focusHeights;
    float amount;
};
layout(binding = 1) uniform sampler2D source;

void main() {
    // Approximate depth from the near wheels' upper edge to the far roof.
    // Keep the foreground in focus; reach a gentle 1.35px kernel at the far edge.
    float distance = (focusHeights.x - qt_TexCoord0.y * resolution.y)
                   / max(1.0, focusHeights.x - focusHeights.y);
    float radius = 1.35 * resolution.y / 1080.0 * amount * smoothstep(0.08, 1.0, distance);
    if (radius < 0.001) {
        fragColor = texture(source, qt_TexCoord0) * qt_Opacity;
        return;
    }
    vec2 stepSize = vec2(radius) / resolution;
    vec4 color = vec4(0.0);
    // Premultiplied RGB and alpha soften together, so the scene shows through
    // the edge without a dark fringe. A separable 1:2:1 kernel takes nine taps.
    for (int y = -1; y <= 1; y++) {
        for (int x = -1; x <= 1; x++) {
            float weight = (x == 0 ? 2.0 : 1.0) * (y == 0 ? 2.0 : 1.0);
            color += weight * texture(source, qt_TexCoord0 + vec2(x, y) * stepSize);
        }
    }
    fragColor = color * (qt_Opacity / 16.0);
}
