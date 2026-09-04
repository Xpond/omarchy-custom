// The wheel's light on the blurred desktop behind it, evaluated per pixel.
//
// A shader because every stock way of drawing this was visibly segmented. A
// gradient's stops are joined by straight lines, so each stop is a break in
// the slope that the eye reads as a ring; a blurred disc is smooth in
// principle, but MultiEffect blurs through downsampled mips and upscaling
// those interpolates bilinearly, which is piecewise-linear again on a coarser
// grid. Both approximate a curve. Here the curve is evaluated, and what is
// left after that -- eight-bit alpha stepping once every few pixels across a
// thousand of them, the faint ringing that survives any smooth falloff -- is
// broken up by a level of dither.
#version 440

layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;

layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    // How far the wash carries, in units of half the item's height.
    float reach;
    // Alpha at the centre. Zero leaves the desktop alone.
    float amount;
    // Item width over height, so the falloff stays circular on any screen.
    float aspect;
    vec4 tint;
};

// White noise off the pixel's own position. Bit-mixing rather than the usual
// fract(sin(...)): sin of a large argument loses precision on some drivers,
// and a degenerate hash puts low-frequency structure into the wash, which is
// the opposite of the job.
float hash(vec2 p) {
    vec3 q = fract(p.xyx * vec3(0.1031, 0.1030, 0.0973));
    q += dot(q, q.yzx + 33.33);
    return fract((q.x + q.y) * q.z);
}

void main() {
    // Centre-relative, corrected for aspect, in units of half the height.
    vec2 p = (qt_TexCoord0 - 0.5) * 2.0 * vec2(aspect, 1.0);
    float t = length(p) / reach;

    // (1 - t squared) cubed: one at the centre, zero at the reach, and flat
    // at both ends, so there is no radius where the slope turns a corner.
    float f = max(0.0, 1.0 - t * t);

    // Two hashes summed is a triangular distribution a level either side of
    // zero, which is what it takes to mask a step of one level completely --
    // anything narrower leaves part of every band edge standing, and a
    // surviving band edge is the ripple. Only inside the reach: past it there
    // is nothing to dither, and noise out there is just speckle.
    float d = (hash(gl_FragCoord.xy) + hash(gl_FragCoord.xy + 17.13) - 1.0) / 255.0;
    float a = f > 0.0 ? clamp(f * f * f * amount + d, 0.0, 1.0) : 0.0;

    // Qt Quick composites premultiplied.
    fragColor = vec4(tint.rgb * a, a) * qt_Opacity;
}
