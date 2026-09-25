// The ground the colony grows over, drawn once for the camera to move across: in red, where it
// clouds up; in green, its grain. The colony's shader colours it.
#version 440

layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;

layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    vec2 resolution;
};

float hash(vec3 p) {
    p = fract(p * 0.3183099 + 0.1) * 17.0;
    return fract(p.x * p.y * p.z * (p.x + p.y + p.z));
}

// Smooth noise in [0, 1], changing about once a unit.
float noise(vec3 p) {
    vec3 i = floor(p), f = fract(p);
    f = f * f * (3.0 - 2.0 * f);
    return mix(mix(mix(hash(i), hash(i + vec3(1, 0, 0)), f.x),
                   mix(hash(i + vec3(0, 1, 0)), hash(i + vec3(1, 1, 0)), f.x), f.y),
               mix(mix(hash(i + vec3(0, 0, 1)), hash(i + vec3(1, 0, 1)), f.x),
                   mix(hash(i + vec3(0, 1, 1)), hash(i + vec3(1, 1, 1)), f.x), f.y), f.z);
}

void main() {
    // In screen heights from the centre: clouds a few tenths across, their octaves turned so no
    // grid shows, over a grain of a few pixels.
    vec2 p = (qt_TexCoord0 - 0.5) * resolution / resolution.y, g = p * 2.5;
    float warp = noise(vec3(g * 1.7, 5.0)), cloud = 0.0, weight = 0.55;
    for (int octave = 0; octave < 4; ++octave) {
        cloud += weight * noise(vec3(g + 1.3 * warp, float(octave) * 3.7));
        g = mat2(0.8, 0.6, -0.6, 0.8) * g * 2.1;
        weight *= 0.5;
    }
    fragColor = vec4(smoothstep(0.2, 0.8, cloud), noise(vec3(p * 420.0, 1.0)), 0.0, 1.0);
}
