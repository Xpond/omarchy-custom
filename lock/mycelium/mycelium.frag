// Reveal the colony by arrival time, light its ground, and drift the surface and deep hyphae.
#version 440

layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;

layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    vec2 resolution;
    // How many of the colony's steps have grown, and seconds shown.
    float grown;
    float time;
    // The camera's pan in pixels, zoom and roll.
    vec4 camera;
    // The sizes of the light and the deep hyphae, in texels.
    vec2 lightSize;
    vec2 deepSize;
};
// The lines, anti-aliased; the step that reaches each of their pixels, in red and green; the light
// they cast: how much of the colony lies about, in red, and the step that reaches it on average,
// in eighths, in green; the deep hyphae, whose red over their alpha is the step that reaches them
// in eighths; and the ground (ground.frag).
layout(binding = 1) uniform sampler2D lines;
layout(binding = 2) uniform sampler2D reach;
layout(binding = 3) uniform sampler2D light;
layout(binding = 4) uniform sampler2D deep;
layout(binding = 5) uniform sampler2D ground;

// Cubic B-spline reconstruction from four bilinear samples, for lines and low-resolution maps.
vec4 soft(sampler2D image, vec2 size, vec2 uv) {
    vec2 at = uv * size - 0.5, i = floor(at), f = at - i;
    vec2 w0 = (1.0 - f) * (1.0 - f) * (1.0 - f) / 6.0, w3 = f * f * f / 6.0;
    vec2 w1 = (4.0 - 6.0 * f * f + 3.0 * f * f * f) / 6.0, w2 = 1.0 - w0 - w1 - w3;
    vec2 g0 = w0 + w1, g1 = w2 + w3;
    vec2 lo = (i - 0.5 + w1 / g0) / size, hi = (i + 1.5 + w3 / g1) / size;
    return g0.y * (g0.x * texture(image, lo) + g1.x * texture(image, vec2(hi.x, lo.y)))
         + g1.y * (g0.x * texture(image, vec2(lo.x, hi.y)) + g1.x * texture(image, hi));
}

// Where this pixel looks through the camera, in screen heights from the centre, on a layer that
// pans and zooms by share of the camera's drift: less, deeper down.
vec2 view(float share) {
    vec2 p = (qt_TexCoord0 - 0.5) * resolution - share * camera.xy;
    return mat2(cos(camera.w), sin(camera.w), -sin(camera.w), cos(camera.w)) * p
         / ((1.0 + share * (camera.z - 1.0)) * resolution.y);
}

void main() {
    // The colony sways over the ground by up to 2.5 pixels at 1080p, in slow waves about a third of
    // the screen's height long, crossing.
    vec2 p = view(1.0), aspect = vec2(resolution.y / resolution.x, 1.0);
    vec2 sway = vec2(sin(dot(p, vec2(17.0, 9.0)) + 0.9 * time) + sin(dot(p, vec2(-8.0, 19.0)) + 0.6 * time + 2.0),
                     sin(dot(p, vec2(11.0, -15.0)) + 0.7 * time + 4.0) + sin(dot(p, vec2(19.0, 6.0)) + 0.5 * time + 1.0));
    vec2 uv = (p + sway * (1.25 / 1080.0)) * aspect + 0.5;

    // Decode after filtering: the packed step is linear in red and green. Divide out coverage
    // at the mask's edge; rounding channels would put hard pixel boundaries back into the tips.
    vec4 t = texture(reach, uv);
    float age = t.a > 0.001 ? grown - dot(t.rg / t.a, vec2(65280.0, 255.0)) : -1.0;
    // Reconstruct the fine lines smoothly as they move across pixels. Bilinear sampling leaves
    // triangular teeth along shallow slopes, especially visible under the bright tip colour.
    float line = soft(lines, resolution, uv).a * clamp(age, 0.0, 1.0);
    // White hot over the tip's last few steps, cooling through cyan to teal behind it.
    float hot = exp(-max(age, 0.0) / 6.0);
    float fresh = exp(-max(age, 0.0) / 80.0);
    vec3 colour = mix(vec3(0.22, 0.46, 0.52), vec3(0.55, 0.9, 1.0), fresh) + 1.2 * hot;

    // The ground: near black whatever the theme, clouded and grained, darker toward the corners.
    vec2 soil = texture(ground, p * aspect + 0.5).rg;
    vec3 dark = mix(vec3(0.006, 0.009, 0.012), vec3(0.040, 0.052, 0.060), soil.r)
              * (0.85 + 0.3 * soil.g) * (1.0 - 0.5 * smoothstep(0.3, 0.8, length(qt_TexCoord0 - 0.5)));
    // Lit by the colony once growth has reached it, most just behind its front.
    vec4 l = soft(light, lightSize, uv);
    float since = grown - l.g * 255.0 * 8.0;
    float lit = l.r * smoothstep(-20.0, 30.0, since) * (1.0 + 2.0 * exp(-max(since, 0.0) / 60.0));
    vec3 base = dark * (1.0 + 22.0 * vec3(0.5, 0.9, 1.0) * lit) + vec3(0.012, 0.055, 0.065) * lit;
    // The deep hyphae: the colony again, turned half round and a tenth larger, moving three fifths
    // as far with the camera, and reached just behind the surface.
    vec4 d = soft(deep, deepSize, -view(0.6) / 1.1 * aspect + 0.5);
    float deepAt = d.a > 0.004 ? d.r / d.a * 255.0 * 8.0 : 1e6;
    base += vec3(0.05, 0.16, 0.19) * d.a * smoothstep(1.15 * deepAt + 10.0, 1.15 * deepAt + 70.0, grown)
          * (0.4 + 0.6 * lit);

    fragColor = vec4(mix(base, colour, line), 1.0) * qt_Opacity;
}
