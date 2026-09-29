// One mark of the tunnel: the wheel's maze of centrelines, with a comet running through it as
// the wheel's does, out from where the bottom bar meets the inner square and splitting at every
// junction. Drawn on the icon's 30-unit grid, with 2 units around it for the glow.
#version 440

layout(location = 0) in vec2 qt_TexCoord0;
// From mark.vert: the mark's opacity, its grid units per screen pixel, and its comet's head along
// the maze, 0 at its start and 1 at the far end.
layout(location = 1) in float fade;
layout(location = 2) in float pixel;
layout(location = 3) in float head;
layout(location = 0) out vec4 fragColor;

// As mark.vert's.
layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    float flight;
    float depth;
    float near;
    float span;
    vec2 centre;
    float focal;
    float turn;
    float size;
    float start;
    float pace;
    // How far back the comet's tail reaches, and 1 to run it back in from the maze's ends.
    float tail;
    float inward;
    vec4 tint;
};

vec2 p;
float nearest = 1e6;
float along = 0.0;

// A stretch from a to b, whose ends lie da and db along the maze from the comet's start.
void stretch(vec2 a, vec2 b, float da, float db) {
    vec2 ab = b - a;
    float len = length(ab);
    float t = clamp(dot(p - a, ab) / (len * len), 0.0, 1.0);
    float d = length(p - a - ab * t);
    if (d < nearest) {
        nearest = d;
        // Two fronts meet partway along some stretches: the nearer one counts.
        along = min(da + t * len, db + (1.0 - t) * len);
    }
}

void main() {
    p = qt_TexCoord0 * 34.0 - 2.0;
    // Every stretch lies on one of these lines across the grid, so a point far from all of them is
    // far from the maze: past 1.25 units the glow has faded below half a level.
    vec2 off = min(min(abs(p - 1.0), abs(p - 5.0)), min(min(abs(p - 15.0), abs(p - 25.0)), abs(p - 29.0)));
    if (min(off.x, off.y) > max(1.25, pixel)) {
        fragColor = vec4(0.0);
        return;
    }
    stretch(vec2(15, 25), vec2(15, 29), 0.0, 4.0);
    stretch(vec2(15, 29), vec2(1, 29), 4.0, 18.0);
    stretch(vec2(1, 29), vec2(1, 15), 18.0, 24.0);
    stretch(vec2(1, 15), vec2(1, 1), 24.0, 38.0);
    stretch(vec2(1, 1), vec2(15, 1), 38.0, 44.0);
    stretch(vec2(15, 1), vec2(29, 1), 44.0, 58.0);
    stretch(vec2(29, 1), vec2(29, 29), 58.0, 86.0);
    stretch(vec2(29, 29), vec2(18, 29), 86.0, 97.0);
    stretch(vec2(15, 25), vec2(5, 25), 0.0, 10.0);
    stretch(vec2(5, 25), vec2(5, 15), 10.0, 20.0);
    stretch(vec2(5, 15), vec2(5, 5), 20.0, 30.0);
    stretch(vec2(5, 5), vec2(15, 5), 30.0, 40.0);
    stretch(vec2(15, 5), vec2(15, 1), 40.0, 44.0);
    stretch(vec2(5, 15), vec2(1, 15), 20.0, 24.0);
    stretch(vec2(15, 25), vec2(25, 25), 0.0, 10.0);
    stretch(vec2(25, 25), vec2(25, 5), 10.0, 30.0);
    stretch(vec2(25, 5), vec2(22, 5), 30.0, 33.0);

    // 97 is the farthest the comet runs.
    float a = along / 97.0;
    if (inward > 0.5) a = 1.0 - a;
    // How far behind the head, as a share of the run: negative just ahead of it, where the
    // front softens over about a unit, as the glow does to the side.
    float behind = fract(head - a + 0.01) - 0.01;
    float hot = smoothstep(-0.01, 0.0, behind) * (1.0 - smoothstep(0.0, tail, behind));

    // The line is 0.07 wide, the comet up to twice that. Thinner than a pixel, it is drawn a
    // pixel wide and dimmer, so distant marks fade instead of breaking up.
    float width = 0.07 * (1.0 + hot);
    float drawn = max(width, pixel);
    float core = (1.0 - smoothstep(drawn * 0.5 - pixel * 0.5, drawn * 0.5 + pixel * 0.5, nearest))
               * min(1.0, width / pixel);
    float glow = hot * exp(-nearest * nearest * 4.0);

    // The resting line in the mark's own hue, whitening towards the comet's head.
    vec3 fire = mix(tint.rgb, vec3(1.0), 0.6 * hot * hot);
    vec3 line = mix(tint.rgb * 0.5, fire, hot) * core;
    // Premultiplied: the line covers what's behind it, the glow only adds light.
    fragColor = vec4(line + tint.rgb * glow * 0.45, core) * qt_Opacity * fade;
}
