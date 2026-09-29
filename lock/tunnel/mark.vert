// Places one mark of the tunnel where it stands ahead as the flight goes on: the corridor's
// centreline wanders on a few sine waves and the camera flies along it looking down its tangent
// (Scene.qml banks it into the turns). The mark fades in at the far end, and out once past the
// screen's edges.
#version 440

layout(location = 0) in vec4 qt_Vertex;
layout(location = 1) in vec2 qt_MultiTexCoord0;
layout(location = 0) out vec2 qt_TexCoord0;
// The mark's opacity, its grid units per screen pixel, and its comet's head along the maze.
layout(location = 1) out float fade;
layout(location = 2) out float pixel;
layout(location = 3) out float head;

layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    // Distance flown and how far ahead the mark stands, how near the nearest stands, and the span
    // after which one flown past returns, in the mark's grid units.
    float flight;
    float depth;
    float near;
    float span;
    // The tunnel's centre and focal length, in pixels: a unit off the axis, a unit ahead, is this
    // many pixels out.
    vec2 centre;
    float focal;
    // Its turn in radians and size, its comet's start and pace in laps per unit flown, and the
    // tail, way round and hue mark.frag draws it with.
    float turn;
    float size;
    float start;
    float pace;
    float tail;
    float inward;
    vec4 tint;
};

vec2 bend(float s) { return vec2(7.0 * sin(s / 40.0) + 2.0 * sin(s / 17.0 + 1.0), 4.0 * sin(s / 53.0 + 2.0)); }

void main() {
    vec2 here = bend(flight), slope = (bend(flight + 1.0) - bend(flight - 1.0)) / 2.0;
    float scale = size * focal / depth, c = cos(turn), s = sin(turn);
    // The mark's 30 units, and 2 each side for its glow, turned and scaled about its middle.
    vec2 corner = mat2(c, s, -s, c) * (qt_MultiTexCoord0 * 34.0 - 17.0) * scale;
    gl_Position = qt_Matrix * vec4(centre + focal * ((bend(flight + depth) - here) / depth - slope) + corner, 0.0, 1.0);
    qt_TexCoord0 = qt_MultiTexCoord0;
    fade = min(1.0, (depth - near) / 1.5) * pow(1.0 - (depth - near) / span, 3.0);
    pixel = 1.0 / scale;
    head = fract(start + pace * flight);
}
