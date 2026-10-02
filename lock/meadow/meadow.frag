#version 440
layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;
layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    float grown;
    float time;
    vec2 resolution;
    float artworkWidth;
};
layout(binding = 1) uniform sampler2D plants;
layout(binding = 2) uniform sampler2D foreground;
layout(binding = 3) uniform sampler2D meadowFlowers;
layout(binding = 4) uniform sampler2D nearFlowers;

float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1,311.7))) * 43758.5453); }
float noise(vec2 p) {
    vec2 i = floor(p), f = fract(p);
    f = f * f * (3.0 - 2.0 * f);
    return mix(mix(hash(i),hash(i + vec2(1,0)),f.x),
               mix(hash(i + vec2(0,1)),hash(i + vec2(1,1)),f.x),f.y);
}

// Layer textures use nearest filtering in ShaderEffect. Blend texels explicitly
// along the moving axis so a slow breeze never snaps a stem by a whole pixel.
vec4 swaySample(sampler2D image, vec2 uv) {
    float x = uv.x * artworkWidth - .5, left = (floor(x) + .5) / artworkWidth;
    return mix(texture(image,vec2(left,uv.y)),texture(image,vec2(left + 1.0 / artworkWidth,uv.y)),fract(x));
}

// The near bank: its swaying flowers over the still ground, grass and stones in the upper half
// of its canvas. Blur taps past the frame's lower edge repeat its last row.
vec4 nearBank(vec2 at) {
    at.y = min(at.y,1.0 - .5 / (.3 * resolution.y));
    vec4 flowers = texture(nearFlowers,at);
    return flowers + texture(foreground,vec2(at.x,.5 * at.y)) * (1.0 - flowers.a);
}

// Gusts travel across the meadow, x screen heights across: a broad sway carries a quicker rustle
// in its wake. plants.vert sways the lower flowers in the same breeze.
float breeze(float x) {
    float gust = pow(.5 + .5 * sin(time * 1.15 - x * 1.8 + .6), 3.0);
    return (.0045 + .0075 * gust) * sin(time * 2.35 - x * 1.5 + .25 * sin(time * .7))
         + .0018 * (.35 + .65 * gust) * sin(time * 4.1 - x * 3.2 + .8);
}

float fbm(vec2 p) {
    float v = 0.0, a = .5;
    for (int i = 0; i < 5; i++) { v += a * noise(p); p = p * 2.03 + 17.0; a *= .5; }
    return v;
}

void main() {
    vec2 uv = qt_TexCoord0, p = uv * vec2(resolution.x / resolution.y, 1.0);
    float aspect = resolution.x / resolution.y, px = 1.0 / resolution.y;
    // Night deepens overhead; the sunset lingers over the meadow, warmest on the right.
    vec3 sky = mix(vec3(.028,.032,.085),vec3(.11,.08,.18),smoothstep(0.0,.52,uv.y));
    float sunset = smoothstep(.15,.9,uv.x), glow = exp(-max(.8 - uv.y,0.0) * (5.0 - 2.0 * sunset));
    vec3 warm = mix(vec3(.5,.17,.3),vec3(1.0,.42,.22),sunset);
    sky += warm * glow * (.35 + .45 * sunset);
    // Stars thin out towards the glow, gone below .6; each twinkles at its own pace.
    if (uv.y < .6) {
        vec2 cell = floor(p * 90.0), q = fract(p * 90.0) - .2 - .6 * vec2(hash(cell),hash(cell + 7.0));
        float h = hash(cell + 31.0), d = length(q) * 12.0;
        if (h > .95) {
            float b = pow((h - .95) / .05,3.0) * (.7 + .3 * sin(time * (1.0 + 2.0 * h) + h * 90.0));
            sky += vec3(.85,.9,1.0) * b * exp(-d * d * (1.1 - .6 * b)) * (1.0 - smoothstep(.25,.6,uv.y));
        }
    }
    // A thin crescent moon with a faint halo; its disk is drawn through the clouds below.
    vec2 moon = p - vec2(aspect * .8,.14);
    float r = .026, lit = (1.0 - smoothstep(r - 2.0 * px,r + px,length(moon)))
        * smoothstep(r * .98 - px,r * .98 + 2.0 * px,length(moon + vec2(.27,.23) * r));
    vec3 moonlight = vec3(.5,.52,.6) * exp(-length(moon) * 9.0);
    sky += vec3(.45,.45,.6) * .07 * exp(-max(length(moon) - r,0.0) * 40.0);
    // Banks of cloud drift with the breeze, with clear sky between them: dark cores,
    // undersides lit by the sunset. A thin haze drifts with them, seen only in the moonlight.
    // Each lock starts with banks framing open sky above the lettering.
    float band = smoothstep(-.1,.2,uv.y) * (1.0 - smoothstep(.34,.52,uv.y));
    if (band > .02) {
        vec2 c = p * vec2(2.2,7.0) - vec2(time * .03 + 9.0,0.0);
        float f = fbm(c), n = f + noise(c * vec2(1.0,.3) + 5.0) + .65 * band - 1.4;
        float cover = smoothstep(.3,.46,n), haze = smoothstep(.3,.6,f) * band;
        sky += .3 * moonlight * haze;
        if (cover > 0.0) {
            float rim = clamp((f - fbm(c + vec2(0.0,.15))) * 10.0,0.0,1.0);
            vec3 light = mix(vec3(.5,.22,.4),warm,.5) * (.45 + .6 * uv.y);
            vec3 cloud = mix(vec3(.1,.07,.15),light,.25 + .75 * rim) + .4 * moonlight;
            sky = mix(sky,cloud,cover * .9);
        }
        sky = mix(sky,vec3(.8,.78,.72),lit * .45 * (1.0 - max(cover,.6 * haze)));
    }
    // Low ground, broken up by tufts and a soft transition into the distant grass. Its edge
    // never rises above .76.
    float ground = 0.0;
    if (uv.y > .75) {
        float edge = .802 + .016 * (noise(vec2(p.x * 5.0,7.0)) - .5)
                         + .012 * (noise(vec2(p.x * 41.0,3.0)) - .5);
        ground = smoothstep(edge - .024,edge + .026,uv.y + .01 * (noise(p * 95.0) - .5));
    }
    vec3 soil = mix(vec3(.035,.07,.057),vec3(.009,.024,.022),smoothstep(.8,1.0,uv.y));
    if (ground > .001) {
        // Perspective compresses the grain towards the far edge of the meadow.
        float depth = clamp((uv.y - .8) / .2,0.0,1.0);
        vec2 earth = vec2((p.x - .5 * resolution.x / resolution.y) * 300.0,(uv.y - .8) * 500.0)
                     / (1.0 + 2.0 * depth);
        float moss = noise(earth * .12), grit = noise(earth);
        vec3 textured = mix(vec3(.024,.032,.025),vec3(.075,.09,.052),moss) * (.55 + .9 * grit);
        soil = mix(soil,textured * (1.0 - .3 * depth),smoothstep(.79,.87,uv.y));
    }
    vec3 color = mix(sky,soil,ground);
    // Quadratic bending has zero slope at the base, so there is no hinge at the horizon.
    vec2 wind = uv;
    float height = clamp((.8 - uv.y) / .45,0.0,1.0);
    wind.x += breeze(p.x) * height * height * resolution.y / resolution.x;
    vec4 plant = swaySample(plants,wind);
    color = color * (1.0 - plant.a) + plant.rgb;
    if (uv.y > .7) {
        vec2 nearUV = vec2(uv.x,(uv.y - .7) / .3);
        // The meadow's lower flowers stand behind the near bank.
        vec4 flowers = texture(meadowFlowers,nearUV);
        color = color * (1.0 - flowers.a) + flowers.rgb;
        // The closest corners fall out of focus; the central clearing stays sharp.
        float blur = smoothstep(.87,1.02,uv.y) * smoothstep(.22,.49,abs(uv.x - .5));
        vec4 near = nearBank(nearUV);
        if (blur > .01) {
            vec2 step = blur * .0025 * vec2(resolution.y / resolution.x,1.0 / .3);
            near = vec4(0.0);
            for (int x = -2; x <= 2; x++) for (int y = -2; y <= 2; y++) {
                float wx = x == 0 ? 6.0 : abs(float(x)) == 1.0 ? 4.0 : 1.0;
                float wy = y == 0 ? 6.0 : abs(float(y)) == 1.0 ? 4.0 : 1.0;
                near += nearBank(nearUV + vec2(x,y) * step) * wx * wy / 256.0;
            }
        }
        // A gentle fade reveals the bank while the lettering begins to grow.
        near *= smoothstep(0.0,.7,grown);
        color = color * (1.0 - near.a) + near.rgb;
    }
    // Fireflies drift over the meadow, each glowing and fading at its own pace.
    {
        vec2 grid = p * 7.0, cell = floor(grid);
        for (int x = -1; x <= 1; x++) for (int y = -1; y <= 1; y++) {
            vec2 id = cell + vec2(x,y);
            // Only rows 4 to 6 can hold a firefly between .6 and .97 high.
            if (id.y < 4.0 || id.y > 6.0) continue;
            float pick = hash(id + 43.0);
            if (pick > .6) continue;
            vec2 center = .25 + .5 * vec2(hash(id),hash(id + 19.0))
                        + .22 * vec2(sin(time * .21 + pick * 40.0),cos(time * .17 + pick * 27.0));
            float fly = (id.y + center.y) / 7.0;
            if (fly < .6 || fly > .97) continue;
            float d = length(grid - id - center) * 1080.0 / 7.0 / (.8 + .8 * hash(id + 71.0));
            float pulse = .45 + .55 * pow(.5 + .5 * sin(time * (.5 + pick) + pick * 50.0),2.0);
            // A hot core inside a warm glow and a wide, faint halo.
            color += pulse * (vec3(1.0,.95,.78) * exp(-d * d * .15)
                   + vec3(1.0,.72,.28) * (.4 * exp(-d * d * .012) + .12 * exp(-d * .05)));
        }
    }
    float vignette = 1.0 - .3 * smoothstep(.35,.85,length((uv - .5) * vec2(1.0,.8)));
    color = color * vignette + (hash(gl_FragCoord.xy) - .5) / 700.0;
    fragColor = vec4(color,1.0) * qt_Opacity;
}
