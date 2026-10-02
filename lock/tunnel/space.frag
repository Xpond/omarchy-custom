#version 440

layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;

layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    vec2 resolution;
    // The tunnel's far end on screen, in pixels, and the camera's bank, in radians.
    vec2 vanish;
    float roll;
    // Flight wraps at 160 grid units; focal length is pixels per unit at depth 1.
    float flight;
    float focal;
    vec4 glow;
};

float hash(float n) { return fract(sin(n * 12.9898) * 43758.5453); }

void main() {
    vec2 q = (qt_TexCoord0 * resolution - vanish) / focal;
    float r = length(q);

    vec3 colour = vec3(0.008, 0.011, 0.024) + glow.rgb * (0.3 * exp(-r * r * 30.0) + 0.07 * exp(-r * r * 2.0));

    // Dust motes occupy angular cells, with radii of 0.6-2px at 1080p.
    float angle = atan(q.y, q.x) - roll;
    vec2 toward = vec2(cos(angle), sin(angle)) * r;
    for (int layer = 0; layer < 3; ++layer) {
        float cells = 90.0 + 60.0 * float(layer);
        float here = floor(angle / 6.2831853 * cells);
        // A dot near the edge of its direction's cell reaches into the next.
        for (int side = -1; side <= 1; ++side) {
            float cell = mod(here + float(side), cells);
            float seed = cell + float(layer) * 311.0;
            float off = 16.0 + 60.0 * hash(seed + 1.0);
            float depth = 4.0 + mod(160.0 * hash(seed + 2.0) - flight, 160.0);
            // A mote cannot reach a pixel farther from its radial distance than its largest radius.
            if (abs(r - off / depth) * focal > 2.0 * focal / 540.0 + 0.501) continue;
            float heading = (cell + 0.2 + 0.6 * hash(seed)) / cells * 6.2831853;
            float radius = (0.6 + 1.4 * hash(seed + 3.0)) * focal / 540.0;
            float d = length(toward - off / depth * vec2(cos(heading), sin(heading))) * focal;
            float mote = 1.0 - smoothstep(radius - 0.5, radius + 0.5, d);
            colour += mix(glow.rgb, vec3(1.0), 0.6) * 0.8 * mote
                    * smoothstep(164.0, 60.0, depth) * smoothstep(4.0, 8.0, depth);
        }
    }
    fragColor = vec4(colour, 1.0) * qt_Opacity;
}
