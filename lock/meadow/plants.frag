#version 440
layout(location = 0) in vec4 shape;
layout(location = 1) in vec4 paint;
layout(location = 2) in vec4 facing;
layout(location = 3) in vec4 petal;
layout(location = 4) in vec4 stone;
layout(location = 0) out vec4 fragColor;
layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    float grown;
    float part;
    float count;
    float rows;
    float unit;
    float pixel;
    float wide;
    float group;
    float time;
};
layout(binding = 2) uniform sampler2D foreground;

const vec3 light = vec3(.449, -.399, .799);

// How much of a pixel centred at d the band [-w, w] covers, in garden units.
float cover(float d, float w) {
    return clamp((min(d + pixel * .5, w) - max(d - pixel * .5, -w)) / pixel, 0.0, 1.0);
}
float inside(float edge) { return clamp(.5 - edge / max(fwidth(edge), 1e-4), 0.0, 1.0); }

// Shadow, body and lit tones of the five leaf greens.
vec3 green(float i, float tone) {
    vec3 a = i < .5 ? vec3(.173, .259, .125) : i < 1.5 ? vec3(.204, .314, .122) : i < 2.5 ? vec3(.122, .196, .098)
           : i < 3.5 ? vec3(.153, .251, .165) : vec3(.110, .176, .106);
    vec3 b = i < .5 ? vec3(.337, .459, .176) : i < 1.5 ? vec3(.416, .541, .192) : i < 2.5 ? vec3(.231, .329, .149)
           : i < 3.5 ? vec3(.310, .431, .208) : vec3(.204, .314, .173);
    vec3 c = i < .5 ? vec3(.624, .706, .314) : i < 1.5 ? vec3(.722, .776, .361) : i < 2.5 ? vec3(.427, .541, .235)
           : i < 3.5 ? vec3(.561, .682, .345) : vec3(.373, .490, .271);
    return tone < .5 ? a : tone < 1.5 ? b : c;
}

// The two nearest surfaces under this pixel, enough to antialias overlapping petals.
vec4 near = vec4(0.0), far = vec4(0.0);
float nearZ = -1e4, farZ = -1e4;
void keep(vec4 colour, float z) {
    if (colour.a <= 0.0) return;
    if (z > nearZ) { far = near; farZ = nearZ; near = colour; nearZ = z; }
    else if (z > farZ) { far = colour; farZ = z; }
}

// Finds where q lies on a plane through the flower's centre spanned by a and b, projected
// flat onto the screen, and each coordinate's screen gradient so edges stay a pixel soft even
// when steeply foreshortened. Edge-on planes keep a sliver of thickness, as curved petals do.
vec2 unproject(vec2 q, vec2 a, vec2 b, out vec2 du, out vec2 dv) {
    float l = length(a);
    vec2 ah = l > 1e-4 ? a / l : normalize(vec2(-b.y, b.x));
    l = max(l, .02);
    float across = dot(b, vec2(-ah.y, ah.x));
    dv = vec2(-ah.y, ah.x) / (across < 0.0 ? min(across, -.15) : max(across, .15));
    du = (ah - dot(b, ah) * dv) / l;
    return vec2(dot(q, du), dot(q, dv));
}

// A ring of petals or sepals, each a flat blade growing from the centre's rim, tilted open
// radians out from the axis. Its outline: widest at 70% of its length, with rounded shoulders
// and a shallow notch at the tip.
void whorl(vec2 q, vec3 n, vec3 e1, vec3 e2, float petals, float open, float rim, float size, float breadth,
           float turn, float opacity, vec3 base, vec3 tip, vec3 back) {
    float loosen = sin(3.1416 * paint.y);
    for (int i = 0; i < 12; i++) {
        if (float(i) >= petals) break;
        float angle = turn + 6.2832 * float(i) / petals;
        vec3 outward = cos(angle) * e1 + sin(angle) * e2, across = cos(angle) * e2 - sin(angle) * e1;
        // Petals loosen at slightly different rates, then settle into the same mature pose.
        float unfurl = open + .22 * sin(float(i) * 2.4 + turn) * loosen;
        vec3 d = cos(unfurl) * n + sin(unfurl) * outward, normal = cross(d, across);
        vec2 du, dv, uv = unproject(q - rim * outward.xy, d.xy, across.xy, du, dv);
        float len = size * (1.0 + .1 * sin(float(i) * 5.0 + turn)), t = (uv.x + rim) / len;
        float w = size * (.1 + (.75 * breadth - .07) * clamp(t * (1.4 - t) / .49, 0.0, 1.0))
                * sqrt(max(1.0 - pow(max(t - .9, 0.0) / .13, 2.0), 0.0));
        float end = max(-uv.x, uv.x + rim - len * (.92 + .77 * abs(uv.y) / size));
        float alpha = opacity * clamp(.5 - max((abs(uv.y) - w) / length(dv), end / length(du)) / pixel, 0.0, 1.0);
        // Inner faces run from base to tip colour with a fine central vein; backs are duller.
        vec3 colour = normal.z > 0.0 ? mix(base, tip, smoothstep(0.0, .55, t)) : back;
        colour = mix(colour, base, .45 * (1.0 - smoothstep(.1, .35, abs(uv.y))) * step(.23, t) * step(t, .82) * step(0.0, normal.z));
        colour *= .72 + .4 * max(dot(normal * sign(normal.z), light), 0.0);
        keep(vec4(colour * alpha, alpha), rim * outward.z + uv.x * d.z + uv.y * across.z);
    }
}

vec4 flower(vec2 q) {
    // Beyond its reach no petal can cover the pixel. Keep this exit before any flower work:
    // without it NVIDIA's compiler can produce a shader that runs about 20 times slower.
    if (dot(q, q) > shape.w * shape.w) return vec4(0.0);
    float size = paint.x, bloom = paint.y, kind = paint.z, turn = paint.w;
    vec3 n = facing.xyz, e1 = petal.xyz, e2 = cross(n, e1);
    float petals = kind < .5 ? 12.0 : kind < 1.5 ? 8.0 : kind < 2.5 ? 5.0 : 6.0;
    float breadth = kind < .5 ? .23 : kind < 1.5 ? .48 : kind < 2.5 ? .85 : .38;
    vec3 base = kind < .5 ? vec3(.588, .451, .278) : kind < 1.5 ? vec3(.573, .153, .345) : kind < 2.5 ? vec3(.651, .196, .212) : vec3(.224, .286, .529);
    vec3 tip = kind < .5 ? vec3(1.0, .941, .780) : kind < 1.5 ? vec3(.937, .545, .733) : kind < 2.5 ? vec3(1.0, .576, .439) : vec3(.592, .749, .918);
    // Green sepals hold the bud closed and fold back ahead of the petals, which lengthen and
    // unfold gradually. The centre widens as they open, so the closed bud wraps it.
    float ripe = smoothstep(0.0, .8, bloom), centre = size * (kind < .5 ? .28 : .19) * mix(.4, 1.0, ripe);
    float open = .12 + 1.28 * smoothstep(.05, 1.0, bloom);
    if (bloom < 1.0) whorl(q, n, e1, e2, 5.0, max(open + .35, mix(.3, 2.2, ripe)), centre * .8, size * .62, .3, turn + .6,
                           1.0 - smoothstep(.6, 1.0, bloom), vec3(.28, .40, .18), vec3(.46, .60, .32), vec3(.22, .32, .16));
    whorl(q, n, e1, e2, petals, open, centre * .7, size * mix(.5, 1.0, ripe), breadth, turn,
          1.0, base, tip, mix(base, tip, .5) * .7);
    // The centre lies across the axis, domed slightly proud of the petals, speckled with pollen.
    vec2 du, dv, c = unproject(q, e1.xy, e2.xy, du, dv);
    float pollen = 0.0;
    vec2 spoke = vec2(1.0, 0.0);
    for (int grain = 0; grain < 9; grain++) {
        pollen = max(pollen, 1.0 - smoothstep(.2, .45, length(c - centre * sqrt(float(grain) / 10.0) * spoke)));
        spoke = mat2(-.737, .675, -.675, -.737) * spoke;  // turned by the golden angle, 2.4 radians
    }
    vec3 disc = mix(kind > 1.5 && kind < 2.5 ? vec3(.204, .188, .216) : vec3(.741, .529, .227),
                    kind > 1.5 && kind < 2.5 ? vec3(.678, .525, .518) : vec3(.961, .835, .514), pollen);
    // Seen edge on it hides inside the bud.
    float alpha = clamp(.5 - (length(c) - centre) / max(length(c.x * du + c.y * dv) / max(length(c), 1e-4), 1e-4) / pixel, 0.0, 1.0)
                * smoothstep(.15, .4, abs(n.z));
    keep(vec4(disc * alpha, alpha), c.x * e1.z + c.y * e2.z + centre * .4 * n.z);
    return near + far * (1.0 - near.a);
}

// Lavender florets open from the bottom of the spike upwards.
vec4 lavender(vec2 q) {
    float size = paint.x, bloom = paint.y, height = mix(.3, 1.0, bloom);
    vec2 axis = facing.xy;
    float up = dot(q, axis) / facing.z, side = dot(q, vec2(-axis.y, axis.x));
    float stalk = cover(side, .35) * clamp((up + 4.0) / pixel, 0.0, 1.0) * clamp((size * 2.5 * height - up) / pixel, 0.0, 1.0);
    vec4 colour = vec4(vec3(.318, .451, .302) * stalk, stalk);
    for (int bud = 0; bud < 9; bud++) {
        float b = float(bud), open = smoothstep(b / 12.0, b / 12.0 + .4, bloom);
        float r = size * (.3 - b * .018) * (.55 + .45 * open);
        vec2 at = vec2((mod(b, 2.0) > .5 ? 1.0 : -1.0) * size * .22, b * size * .25 * height + .3 * r);
        float alpha = inside(length(vec2(side - at.x, (up - at.y) / .7)) - r);
        vec3 tint = mix(vec3(.40, .50, .35), mod(b, 2.0) > .5 ? vec3(.329, .278, .502) : vec3(.745, .608, .863), open);
        colour = vec4(tint * alpha, alpha) + colour * (1.0 - alpha);
    }
    return colour;
}

void main() {
    vec4 colour;
    if (shape.z > 2.5) colour = lavender(shape.xy);
    else if (shape.z > 1.5) colour = flower(shape.xy);
    else if (shape.z > .5) {
        // A pointed leaf on a short stalk, lit along one side, with a paler midrib.
        float reach = paint.x, width = paint.y, stalk = reach * .17;
        float t = clamp((shape.x - stalk) / (reach - stalk), 0.0, 1.0), side = clamp(shape.y / (width * .6), -1.0, 1.0);
        float blade = cover(shape.y, width * .54 * pow(sin(3.1416 * pow(t, .77)), .8));
        float alpha = max(blade, cover(shape.y, .25) * step(shape.x, stalk * 1.2));
        vec3 tint = side < 0.0 ? mix(green(paint.w, 1.0), green(paint.w, 2.0), -side) : mix(green(paint.w, 1.0), green(paint.w, 0.0), side);
        // Still half folded, one half faces the light and the other falls into shade.
        tint *= 1.0 - (1.0 - paint.z) * .35 * sign(shape.y);
        tint = mix(tint, green(paint.w, 2.0), (1.0 - smoothstep(.1, .25, abs(shape.y))) * step(.05, t) * step(t, .85));
        colour = vec4(tint * alpha, alpha);
    } else {
        // Stems, grass and tendrils are round: lit on the side facing the sunset.
        float alpha = cover(shape.y, shape.w);
        colour = vec4(paint.rgb * (.9 + .2 * clamp(shape.y / max(shape.w, .01), -1.0, 1.0)) * alpha, alpha);
    }
    // A stone hides the near flowers rooted behind its front edge, which its outline holds in the
    // lower half of the near bank's canvas, from 800 to 1000.
    if (stone.w > .5) {
        vec4 mask = texture(foreground,stone.xy);
        if (mask.a > 0.0 && stone.z < 800.0 + 200.0 * mask.r / mask.a) colour *= 1.0 - mask.a;
    }
    fragColor = colour * qt_Opacity;
}
