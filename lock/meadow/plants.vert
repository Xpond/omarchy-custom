#version 440
layout(location = 0) in vec4 qt_Vertex;
layout(location = 1) in vec2 qt_MultiTexCoord0;
layout(location = 0) out vec4 shape;  // along and across in garden units, part, half width
layout(location = 1) out vec4 paint;  // ribbon colour, or leaf and flower sizes
layout(location = 2) out vec4 facing; // flower axis, or the lavender spike's direction
layout(location = 3) out vec4 petal;  // direction of a flower's first petal
layout(location = 4) out vec4 stone;  // a near flower's place on the near bank canvas, and its root
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
    float group;  // the lettering, the meadow's other flowers, or the near bank's
    float time;
};
layout(binding = 1) uniform sampler2D plants;

float id;
float hash(float n) { n = fract(n * .1031); n *= n + 33.33; n *= n + n; return fract(n); }
float random(float salt) { return hash(id * 61.0 + salt); }
// garden.js stores each plant field in one texel as 24-bit fixed point.
float field(float row) {
    vec3 t = floor(textureLod(plants, vec2((id + .5) / count, (row + .5) / 12.0), 0.0).rgb * 255.0 + .5);
    return dot(t, vec3(65536.0, 256.0, 1.0)) / 2048.0 - 4096.0;
}

// The breeze meadow.frag bends the lettering with, x screen heights across.
float breeze(float x) {
    float gust = pow(.5 + .5 * sin(time * 1.15 - x * 1.8 + .6), 3.0);
    return (.0045 + .0075 * gust) * sin(time * 2.35 - x * 1.5 + .25 * sin(time * .7))
         + .0018 * (.35 + .65 * gust) * sin(time * 4.1 - x * 3.2 + .8);
}

vec2 top, tip;
float root, bend, waves, radius, kind, phase, tilt, leaves, letter, age, dur, s, progress, sway;
void grow() {
    top = vec2(field(0.0), field(1.0)); root = field(2.0); bend = field(3.0); waves = field(4.0);
    radius = field(5.0); kind = field(6.0); phase = field(7.0); tilt = field(8.0);
    leaves = field(9.0); letter = field(11.0);
    age = grown - field(10.0);
    dur = letter > .5 ? 1.35 + .95 * random(1.0) + .25 * clamp((root - top.y) / 480.0, 0.0, 1.0) : .7 + .4 * random(1.0);
    progress = clamp(age / dur, 0.0, 1.0);
    s = progress * (2.0 - progress);
    // Young tips search gently; their bend settles with growth rather than pulling the
    // flowers sideways into the letters when they open.
    float swing = age * (2.5 + random(2.0)) + phase * 5.0;
    float lean = ((random(3.0) < .5 ? -1.0 : 1.0) * (.12 + .26 * random(4.0))
               + .16 * sin(swing)) * (1.0 - smoothstep(.35, 1.0, progress));
    tip = (root - top.y) * s * .14 * vec2(sin(lean), 1.0 - cos(lean));
    // Low flowers sway from their roots, as far as a few degrees; the lettering's layer is bent
    // by meadow.frag instead.
    sway = group > .5 ? 3.0 * breeze(top.x / 900.0) * (root - top.y) * s : 0.0;
}

// The stem at fraction u of its current length: its final curve grown to s, its young
// tip bent aside.
vec2 stem(float u) {
    float t = u * s;
    return vec2(top.x + bend * (1.0 - t) + sin(t * waves + phase) * 2.5 * (1.0 - t),
                root + (top.y - root) * t) + tip * u * u * u + vec2(sway * u * u, 0.0);
}
// Height fraction of leaf node n, spaced below the lettering.
float node(float n) {
    float band = root - max(top.y + 18.0, 540.0 + random(9.0) * 90.0);
    return band * (.1 + (n + random(10.0 + n)) / leaves * .85) / (root - top.y);
}
// Seconds after the plant starts until its tip climbs past height fraction at.
float passed(float at) { return dur * (1.0 - sqrt(max(1.0 - at, 0.0))); }

// A ribbon of n segments takes n + 3 rows. The first and last collapse onto its end edges, so
// neighbouring parts are only joined by zero-area triangles.
float along(float k, float n) { return clamp(k - 1.0, 0.0, n) / n; }
void emit(vec2 centre, vec2 direction, float halfWidth, float side, float k, float n, float u) {
    if (k < .5 || k > n + 1.5) side = 0.0;
    vec2 normal = normalize(vec2(-direction.y, direction.x));
    shape.xyw = vec3(u, side * (halfWidth + pixel), halfWidth);
    vec2 at = centre + normal * shape.y;
    if (group > 1.5) stone = vec4(at.x / wide, .5 + (at.y - 630.0) / 540.0, root, 1.0);
    gl_Position = qt_Matrix * vec4(at * unit, 0.0, 1.0);
}

// Clumps of three blades rise and bend over as they lengthen.
void blade(float k, float side) {
    float clump = floor(id / 3.0), shade = random(6.0);
    float g = clamp((grown - .1 - shade * .5 - random(7.0) * .2) / .7, 0.0, 1.0);
    if (g <= 0.0) return;
    g *= 2.0 - g;
    vec2 base = vec2(hash(clump * 61.0 + 1.0) * wide + random(2.0) * 9.0, 732.0 + hash(clump * 61.0 + 3.0) * 190.0 + random(4.0) * 6.0);
    float tall = (12.0 + hash(clump * 61.0 + 5.0) * 60.0) * (.5 + random(8.0) * .7) * g;
    float lean = (random(9.0) - .5) * 45.0 * g * g, u = along(k, 4.0);
    vec2 a = vec2(lean * .2, -tall * .6), b = vec2(lean, -tall);
    paint = vec4(shade > .5 ? vec3(.227, .388, .251) : vec3(.141, .271, .184), 1.0);
    emit(base + 2.0 * u * (1.0 - u) * a + u * u * b, (1.0 - u) * a + u * (b - a) - vec2(0.0, 1e-4),
         (.2 + shade * .4) * (1.0 - .5 * u), side, k, 4.0, u);
}

void stemPart(float k, float side) {
    float u = along(k, 16.0), young = smoothstep(.55, 1.0, u) * (1.0 - s), shade = mod(floor(phase), 3.0);
    vec3 green = shade < .5 ? vec3(.420, .478, .196) : shade < 1.5 ? vec3(.490, .529, .220) : vec3(.353, .416, .180);
    // Fresh growth near the tip is thinner and paler.
    paint = vec4(mix(green, vec3(.62, .70, .32), young * .8), 1.0);
    emit(stem(u), stem(u + .01) - stem(u - .01) - vec2(0.0, 1e-4), .55 * (1.0 - .45 * young), side, k, 16.0, u);
}

// Leaves unfold beside the stem once its tip has climbed past their node.
void leaf(float slot, float k, float side) {
    float n = floor(slot / 2.0), pair = slot - n * 2.0, at, size, angle;
    float flip = mod(n + floor(phase), 2.0) > .5 ? 1.0 : -1.0;
    if (slot > 5.5) {
        // A small leaf may tuck in just under the flower.
        if (letter < .5 || random(16.0) > .5) return;
        at = 1.0 - 16.0 / (root - top.y); size = 9.0 + random(17.0) * 4.0;
        angle = (random(18.0) < .5 ? 1.0 : -1.0) * (.8 + random(19.0) * .7);
    } else {
        if (n >= leaves || (pair > .5 && random(20.0 + n) > .25)) return;
        at = node(n);
        size = (letter > .5 ? 13.0 + random(23.0 + slot) * 13.0 : 8.0 + radius * .8) * (1.0 - .3 * at) * (1.0 - .15 * pair);
        angle = (pair > .5 ? -flip : flip) * (.6 + random(29.0 + slot) * .9);
    }
    float g = clamp((age - passed(at) - .1) / .6, 0.0, 1.0);
    if (g <= 0.0) return;
    // Folded up against the stem, it turns outwards, lengthens and opens flat.
    float open = smoothstep(0.0, 1.0, g);
    angle = -1.5708 + angle * mix(.2, 1.0, open);
    float reach = size * 1.2 * (.1 + .9 * g * (2.0 - g)) * (.7 + .3 * random(35.0 + slot));
    float width = size * (.32 + random(41.0 + slot) * .22) * mix(.25, 1.0, open), u = along(k, 1.0);
    vec2 direction = vec2(cos(angle), sin(angle));
    paint = vec4(reach, width, open, floor(random(47.0 + slot) * 5.0));
    shape.z = 1.0;
    emit(stem(at / s) + direction * reach * u, direction, width * .6, side, k, 1.0, u * reach);
}

// A tendril coils tighter as it matures: each step turns further and shortens.
vec2 coil(vec2 p, float turn, float flip, float curl, float steps) {
    float step = 2.6;
    for (int j = 0; j < 14; j++) {
        float f = clamp(steps - float(j), 0.0, 1.0);
        turn += flip * .55 * curl; p += vec2(cos(turn), sin(turn)) * step * f; step *= .88;
    }
    return p;
}
void tendril(float k, float side) {
    if (random(50.0) > 1.0 - pow(.7, leaves)) return;
    float n = floor(random(51.0) * leaves), at = node(n), g = clamp((age - passed(at) - .25) / .9, 0.0, 1.0);
    if (g <= 0.0) return;
    float flip = mod(n + floor(phase), 2.0) > .5 ? 1.0 : -1.0, u = along(k, 14.0), steps = u * 14.0 * g;
    vec2 base = stem(at / s);
    float turn = -1.5708 + flip * .5, curl = mix(.15, 1.0, g);
    paint = vec4(.659, .659, .322, 1.0);
    emit(coil(base, turn, flip, curl, steps), coil(base, turn, flip, curl, steps + .05) - coil(base, turn, flip, curl, steps - .05),
         .225, side, k, 14.0, u);
}

// The head rides the tip as a bud, then lifts to face us and opens.
void flower(float k, float side) {
    vec2 p = stem(1.0), up = normalize(p - stem(.96) - vec2(0.0, 1e-4));
    // Flowering overlaps the climb, with a separate clock for each bud.
    float bloom = clamp((age - .48 * dur - .2 * random(5.0)) / (letter > .5 ? 1.05 + .65 * random(6.0) : .7), 0.0, 1.0);
    float lift = smoothstep(.25, .95, progress);
    float depth = .4 * cos(age * (2.5 + random(2.0)) + phase * 5.0) * (1.0 - progress);
    float size = radius * (.3 + .7 * smoothstep(0.0, 1.0, s));
    // Turned by sin(phase) * .5 and foreshortened to tilt.
    float spin = sin(phase) * .5, lean = acos(clamp(tilt, 0.0, 1.0));
    vec3 face = vec3(sin(lean) * sin(spin), -sin(lean) * cos(spin), cos(lean));
    vec3 axis = normalize(mix(normalize(vec3(up, depth)), face, lift));
    if (kind > 3.5) facing = vec4(normalize(mix(up, vec2(sin(spin), -cos(spin)), lift)), mix(1.0, tilt, lift), 0.0);
    else facing = vec4(axis, 0.0);
    petal = vec4(normalize(cross(vec3(1.0, 0.0, 0.0), axis)), 0.0);
    paint = vec4(size, bloom, kind, phase);
    // Reaches as far as its longest sepal or petal, a pixel beyond for antialiasing.
    float extent = size * (kind > 3.5 ? 2.9 : max(.75, mix(.6, 1.15, smoothstep(0.0, .8, bloom)))) + pixel, u = along(k, 1.0);
    emit(p + vec2(0.0, (u * 2.0 - 1.0) * extent), vec2(0.0, 1.0), extent, side, k, 1.0, 0.0);
    shape.xyz = vec3(-shape.y, (u * 2.0 - 1.0) * extent, kind > 3.5 ? 3.0 : 2.0);
}

void main() {
    float row = floor(qt_MultiTexCoord0.y * count * rows + .5), side = qt_MultiTexCoord0.x * 2.0 - 1.0;
    id = floor(row / rows);
    float k = row - id * rows;
    shape = vec4(0.0); paint = vec4(0.0); facing = vec4(0.0); petal = vec4(0.0); stone = vec4(0.0);
    // Hidden parts put every vertex in one place.
    gl_Position = vec4(0.0, 0.0, 0.0, 1.0);
    if (id >= count) return;
    if (part < .5) { blade(k, side); return; }
    grow();
    // The lettering and the meadow's other flowers share a table, but each has its own layer.
    if (age <= 0.0 || (group < 1.5 && (letter > .5) != (group < .5))) return;
    if (part > 1.5) flower(k, side);
    else if (k < 19.0) stemPart(k, side);
    else if (k < 47.0) leaf(floor((k - 19.0) / 4.0), mod(k - 19.0, 4.0), side);
    else tendril(k - 47.0, side);
}
