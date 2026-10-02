#version 440
layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;
layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    vec2 resolution;
    float pitch;
    float shake;
    float amount;
};
layout(binding = 1) uniform sampler2D source;
layout(binding = 2) uniform sampler2D paintMask;
layout(binding = 3) uniform sampler2D environment;

// The mask identifies the panel and its plane height. Reconstruct a camera ray
// using the same perspective as Car.qml's project(), in car design units.
const vec3 rightward = vec3(0.8660254, 0.0, -0.5);
const vec3 upward = vec3(0.0993347, 0.9800666, 0.1720527);
const vec3 depth = vec3(0.4900333, -0.1986693, 0.8487626);
vec3 unpose(vec3 p) {
    float c = cos(pitch), s = sin(pitch);
    return vec3(c * p.x - s * p.y, s * p.x + c * p.y, p.z);
}

// Approximate an environment from the painted plate. Reflected directions bend
// its signs and puddles across the panels; mip filtering softens the clear coat,
// and a higher level only a glow of the city for satin black.
vec3 cityLight(vec3 r, float lod) {
    vec2 uv = vec2(fract(0.5 + atan(r.x, r.z) / 6.2831853), clamp(0.5 - r.y * 0.65, 0.02, 0.98));
    vec3 e = pow(textureLod(environment, uv, lod).rgb, vec3(2.2));
    e *= 1.2 + 3.0 * smoothstep(0.2, 0.7, max(e.r, e.b));
    return mix(e, vec3(0.025, 0.07, 0.18), smoothstep(0.45, 0.9, r.y));
}

vec3 flankNormal(vec3 p) {
    float shoulder = exp(-pow((p.y - 71.0) / 5.0, 2.0));
    return vec3(0.085 * sin((p.x - 160.0) / 85.0),
                0.12 + 0.007 * (p.y - 48.0) + 0.12 * shoulder
                + 0.035 * cos((p.x - 210.0) / 70.0), -1.0);
}

// A woven screen in physical surface coordinates. Derivative filtering keeps its fine wires
// stable at oblique angles and across resolutions, instead of constant-width screen-space lines.
vec3 meshLight(vec2 uv, float spacing, float brightness) {
    vec2 cell = uv / spacing;
    vec2 distance = abs(fract(cell + 0.5) - 0.5);
    vec2 aa = max(fwidth(cell), vec2(0.015));
    vec2 wire = 1.0 - smoothstep(vec2(0.10) - aa * 0.5, vec2(0.10) + aa * 0.5, distance);
    float coverage = max(wire.x, wire.y);
    float weave = 0.82 + 0.18 * cos(cell.x * 3.14159) * cos(cell.y * 3.14159);
    vec2 roundWire = sqrt(max(vec2(0.0), 1.0 - pow(clamp(distance / 0.10, 0.0, 1.0), vec2(2.0))));
    float relief = 0.5 + 0.5 * max(roundWire.x * wire.x, roundWire.y * wire.y);
    vec3 steel = vec3(0.30, 0.39, 0.52) * brightness * weave * relief;
    return mix(vec3(0.002, 0.003, 0.006), steel, coverage);
}

// zAt's inlet cheek: the added width fades into the arch, shoulder and sill.
float intakeSide(vec2 q) {
    float base = 84.0 + 4.0 * smoothstep(264.0, 282.0, q.x) * clamp((72.0 - q.y) / 3.0, 0.0, 1.0);
    float blend = smoothstep(0.0, 1.0, min((q.y - 26.0) / 5.0, (72.0 - q.y) / 5.0));
    float width = 8.0 + (clamp(q.y, 31.0, 67.0) - 31.0) / 6.0;
    return base + width * pow(clamp((286.0 - q.x) / 16.0, 0.0, 1.0), 2.0) * blend;
}
vec3 intakeNormal(vec2 q) {
    return vec3((intakeSide(q - vec2(0.02, 0.0)) - intakeSide(q + vec2(0.02, 0.0))) / 0.04,
                (intakeSide(q - vec2(0.0, 0.02)) - intakeSide(q + vec2(0.0, 0.02))) / 0.04, -1.0);
}

void main() {
    vec4 base = texture(source, qt_TexCoord0);
    vec4 mask = texture(paintMask, qt_TexCoord0);
    mask.rgb /= max(mask.a, 0.001);
    int panel = int(floor(mask.r * 16.0 + 0.5));
    if (panel == 0 || base.a < 0.001 || amount == 0.0) {
        fragColor = base * qt_Opacity;
        return;
    }
    float scale = min(resolution.x * 0.88 / 480.0, resolution.y * 0.8 / 200.0);
    vec2 screen = (qt_TexCoord0 * resolution - vec2(resolution.x * 0.5,
                   resolution.y * 0.5 - 4.0 * scale)) / scale;
    vec3 origin = vec3(221.0, 60.0, 0.0) - depth * 1400.0;
    vec3 ray = normalize(rightward * screen.x - upward * screen.y + depth * 1400.0);
    // Wheels (8-11: rim lip, spokes, hub, tyre) turn but never pitch with the body.
    bool wheel = panel >= 8 && panel <= 11;
    if (!wheel) {
        origin = vec3(322.0, 30.0, 0.0) + unpose(origin - vec3(322.0, 30.0 + shake, 0.0));
        ray = unpose(ray);
    }
    // Green flags variants: on a top (3) the wing's plane, on panel 12 the wing's carbon tips or the intake.
    bool wing = panel == 3 && mask.g > 0.99, side = panel == 12 && mask.g > 0.2 && mask.g < 0.5;
    bool intake = side && mask.g > 0.35, tip = side && !intake;
    bool intakePaint = intake && mask.b < 0.4, intakeCheek = intake && mask.b < 0.1;
    bool mirror = panel == 16 && abs(mask.g - 0.5) > 0.2;
    bool flap = panel == 16 && !mirror;
    vec3 n = vec3(0.0, 0.0, -1.0);
    vec3 anchor = vec3(220.0, 60.0, -84.0);
    if (flap) {
        n = vec3(-1.0, 0.0, 0.0);
        anchor.x = screen.x < 60.0 ? 137.0 : 359.0;
    } else if (wheel) {
        anchor.z = panel == 10 ? -76.0 : -86.0;
    } else if (panel == 15) {
        anchor.z = 0.0;
    } else if (intake) {
        n = vec3(-1.0, 0.0, 0.0);
        anchor = vec3(mask.b > 0.9 ? 271.5 : 270.0, 49.0, -92.0);
    } else if (tip) {
        // Blue marks the far one.
        anchor.z = mask.b > 0.5 ? 77.0 : -77.0;
    } else if (panel == 2 || panel == 7 || (panel >= 12 && panel <= 14)) {
        n = normalize(vec3(-1.0, panel == 7 ? 0.35 : 0.0, 0.0));
        anchor = vec3(7.0, 36.0, 0.0);
    } else if (wing) {
        // outlines.js's wing: a 24-unit chord, rising 1.5, with a 2-unit section.
        n = normalize(vec3(-1.5 / 24.0, 1.0, 0.0));
        anchor = vec3(396.0, 121.63, 0.0);
    } else if (panel == 3) {
        float h = mask.g * 160.0;
        n = normalize(vec3(h < 95.0 && h > 60.0 ? -0.12 : 0.0, 1.0, 0.0));
        anchor = vec3(h > 120.0 ? 265.0 : 95.0, h, 0.0);
    } else if (panel == 4) {
        n = normalize(vec3(0.0, 0.25, -1.0));
        anchor = vec3(220.0, 90.0, -80.0);
    } else if (panel == 6) {
        n = normalize(vec3(-0.55, 0.84, 0.0));
        anchor = vec3(180.0, 111.0, 0.0);
    }
    // Sides standing clear of the flank (the wing's fins) carry their plane in green.
    if (panel == 1 && mask.g > 0.0) anchor.z = mask.g * 200.0 - 100.0;
    vec3 p = origin + ray * (dot(anchor - origin, n) / dot(ray, n));
    float recess = 1.0, wallCoverage = 1.0, radius = 0.0;
    vec2 d = vec2(0.0);
    if (mirror) {
        // Intersect the same rounded housing as mirrorRing: |x/10|^3 + |y/5|^3 + |z/8|^3 = 1.
        float side = mask.g > 0.5 ? 1.0 : -1.0;
        vec3 size = vec3(10.0, 5.0, 8.0), centre = vec3(168.0, 103.0, side * 94.0);
        vec3 o = (origin - centre) / size, direction = ray / size;
        vec3 slab = min((-vec3(1.0) - o) / direction, (vec3(1.0) - o) / direction);
        float near = max(slab.x, max(slab.y, slab.z)), far = -dot(o, direction) / dot(direction, direction);
        for (int i = 0; i < 12; i++) {
            float t = (near + far) * 0.5;
            vec3 q = abs(o + direction * t);
            if (dot(q * q, q) > 1.0) near = t; else far = t;
        }
        vec3 q = o + direction * far;
        n = q * abs(q) / size;
        p = origin + ray * far;
    } else if (panel == 1 || panel == 4 || panel == 5) {
        // One continuous crown and shoulder across the flank, wheel skirts and the wing's fins,
        // whose clear coat carries on the body's reflections.
        n.xy = flankNormal(p).xy;
        if (panel == 5) {
            // Intersect the far wall of the wheel opening (radius 36). Its depth
            // runs from the painted lip at z=-88 to the inner edge at z=-80.
            float axle = p.x < 220.0 ? 100.0 : 322.0;
            vec2 offset = origin.xy - vec2(axle, 30.0);
            float a = dot(ray.xy, ray.xy), b = dot(offset, ray.xy);
            float discriminant = b * b - a * (dot(offset, offset) - 36.0 * 36.0);
            // The visible wall is behind the axle; the sill return is ahead of it.
            // Clamp at the cylinder tangent to cover the polygon's antialiased edge.
            if (p.x > axle) {
                vec3 wall = origin + ray * ((-b + sqrt(max(0.0, discriminant))) / a);
                recess = clamp((wall.z + 88.0) / 8.0, 0.0, 1.0);
                // The mask's edge coverage extends onto the body. Keep that paint
                // unoccluded, especially where the return tapers to a point.
                vec3 opening = origin + ray * ((-88.0 - origin.z) / ray.z);
                vec3 inside = origin + ray * ((-80.0 - origin.z) / ray.z);
                float nearRadius = length(opening.xy - vec2(axle, 30.0));
                float farRadius = length(inside.xy - vec2(axle, 30.0));
                if (nearRadius >= 36.0) recess = 0.0;
                // A subpixel return needs partial shadow coverage. Full-strength
                // shadow at its vanishing tip left a dark line despite exact joins.
                wallCoverage = smoothstep(0.0, 1.5, max(0.0, farRadius - nearRadius) * scale);
            }
        }
    } else if (wing) {
        // A symmetric NACA section, 2 thick: its upper surface's slope along the chord, turning down
        // round the leading edge to face forward, and just under it.
        float c = (p.x - 384.0) / 24.0;
        if (c > 0.0) {
            c = max(c, 1e-4);
            float thick = 0.2969 / (2.0 * sqrt(c)) - 0.126 - 0.7032 * c + 0.8529 * c * c - 0.4144 * c * c * c;
            n = normalize(vec3(-(1.5 + 10.0 * thick) / 24.0, 1.0, 0.0));
        } else {
            n = normalize(vec3(-1.0, -0.5 * clamp(-c / 0.03, 0.0, 1.0), 0.0));
        }
    } else if (panel == 3) {
        n.z = p.z * 0.0025;
        n.x += (p.x - anchor.x) * 0.00065;
    } else if (panel >= 12 && panel <= 14 && !side) {
        // Lamps bulge from the nose. Find the nearest spotlight (outlines.js's spots, once warp moves
        // the face back 10: two above at x=7, four below at x=5.7) in its own plane, as an
        // offset in radii; failing that, the headlamps at x=14 curve across their height.
        vec3 hi = origin + ray * ((7.0 - origin.x) / ray.x);
        vec3 lo = origin + ray * ((5.7 - origin.x) / ray.x);
        vec3 head = origin + ray * ((14.0 - origin.x) / ray.x);
        vec2 up = (hi.yz - vec2(67.5, sign(hi.z) * 33.0)) / 9.0;
        vec2 down = (lo.yz - vec2(46.5, sign(lo.z) * (abs(lo.z) < 33.0 ? 19.0 : 47.0))) / 8.5;
        d = dot(up, up) < dot(down, down) ? up : down;
        // Cans (marked in green) are cylinders round their lens; glass and chrome domes face forward.
        if (panel == 12) {
            if (mask.g > 0.5) n = normalize(vec3(-0.3, d));
        } else {
            if (dot(d, d) > 1.44) d = vec2(clamp((head.y - 63.0) / 4.5, -1.0, 1.0), 0.0);
            n = normalize(vec3(-1.0, 0.8 * d));
        }
    } else if (tip) {
        // The carbon tips curl over: rising above the plane, their faces turn up and forward.
        float curl = clamp((p.y - 120.3 - (p.x - 384.0) / 16.0) / 6.0, 0.0, 1.0);
        n = vec3(-0.55 * curl, mix(-0.25, 0.8, curl), -1.0);
    } else if (panel == 7) {
        // The rounded bumper must turn all the way into the flank. Its front-plane
        // intersection extends past z=-88; project the side tangent onto that plane.
        float sideT = (-88.0 - origin.z) / ray.z;
        vec3 side = origin + ray * sideT;
        float foot = -9.0 + 0.8 * clamp(side.y - 18.0, 0.0, 5.0);
        float cornerX = 18.0 + foot + 0.35 * (clamp(side.y, 23.0, 49.0) - 36.0);
        float turn = smoothstep(cornerX - 19.0, cornerX, side.x);
        float angle = turn * 1.5707963;
        // At the tangent, use the flank's exact normal AND lighting position.
        // Matching only its Y normal left a visible change at the material boundary.
        vec3 flank = origin + ray * ((-84.0 - origin.z) / ray.z);
        n = vec3(-cos(angle), 0.35, -sin(angle))
          + turn * (flankNormal(flank) - vec3(0.0, 0.35, -1.0));
        p = mix(p, flank, turn);
    }
    if (intakeCheek) {
        // Intersect the same blended surface that carries the painted livery.
        float t = (-94.0 - origin.z) / ray.z;
        for (int i = 0; i < 5; i++) {
            vec3 q = origin + ray * t;
            t += (q.z + intakeSide(q.xy)) / dot(intakeNormal(q.xy), ray);
        }
        p = origin + ray * t;
        n = intakeNormal(p.xy);
    }
    float cheekBlend = intakeCheek ? (1.0 - smoothstep(280.0, 286.0, p.x)) * smoothstep(26.0, 30.0, p.y) * (1.0 - smoothstep(68.0, 72.0, p.y)) : 0.0;
    if (intakeCheek) n = mix(flankNormal(p), n, cheekBlend);
    float intakeWidth = 8.0 + clamp((p.y - 31.0) / 6.0, 0.0, 6.0);
    vec2 intakeUV = vec2(-p.z - 85.0, p.y - 31.0) / vec2(intakeWidth, 36.0);
    if (wheel) {
        vec2 radial = p.xy - vec2(p.x < 220.0 ? 100.0 : 322.0, 30.0);
        radius = length(radial);
        // The tyre's flat sidewall rolls over at its shoulder.
        float curve = panel == 8 ? clamp((radius - 22.1) / 1.45, -0.92, 0.92)
                    : panel == 10 ? radius / 14.0
                    : panel == 11 ? 0.85 * smoothstep(27.0, 32.5, radius) : 0.42;
        n = vec3(normalize(radial) * curve, -sqrt(1.0 - curve * curve));
    }
    n = normalize(n);
    vec3 v = -ray, r = reflect(ray, n);
    // The environment stays fixed while the body pitches; wheel normals never pitch.
    if (!wheel) r = vec3(cos(pitch) * r.x + sin(pitch) * r.y,
                           -sin(pitch) * r.x + cos(pitch) * r.y, r.z);
    vec3 pigment = pow(clamp(base.rgb / base.a, 0.0, 1.0), vec3(2.2));
    vec3 light;
    float fresnel = 0.07 + 0.93 * pow(1.0 - max(dot(n, v), 0.0), 5.0);
    vec3 sun = normalize(vec3(-0.4, 0.8, -0.5));
    if (flap) {
        float exposed = 1.0 - smoothstep(3.0, 19.0, p.y);
        light = pigment * (0.14 + 0.64 * exposed) * vec3(0.85, 0.9, 1.0);
    } else if (mirror || tip) {
        float sky = pow(max(dot(r, sun), 0.0), 16.0);
        light = pigment * (0.22 + 0.5 * max(dot(n, sun), 0.0))
              + cityLight(r, 7.0) * (0.025 + fresnel * 0.18) + vec3(0.55, 0.65, 0.8) * sky;
    } else if (intake && !intakePaint) {
        float edgeShade = smoothstep(0.05, 0.3, intakeUV.x) * (1.0 - 0.92 * smoothstep(0.65, 0.94, intakeUV.y));
        if (mask.b > 0.9) light = meshLight(vec2(-p.z, p.y), 0.85, 0.065) * edgeShade;
        else {
            // The exposed rear wall catches sky light; the overhanging top stays in shadow.
            float rearWall = smoothstep(0.55, 0.9, intakeUV.x);
            float floorLight = 1.0 - smoothstep(0.03, 0.12, intakeUV.y);
            float topShadow = 1.0 - 0.9 * smoothstep(0.87, 0.99, intakeUV.y);
            light = pigment * vec3(0.10, 0.13, 0.18) * (0.12 + 0.8 * rearWall + 0.2 * floorLight) * topShadow;
        }
    } else if (panel == 11) {
        // Black rubber: a flat sidewall rolling over at the shoulder. The shine is analytic, a sky
        // highlight and a soft pink glow from the signs: sampling the city across the quickly
        // turning shoulder smeared it into streaks.
        float shoulder = smoothstep(26.0, 31.0, radius);
        float sky = pow(max(dot(r, sun), 0.0), 30.0);
        float neon = pow(max(dot(r, normalize(vec3(0.6, 0.2, -0.8))), 0.0), 8.0);
        // Only the rubber darkens; the white lettering keeps its own colour.
        light = pigment * mix(0.45, 1.0, pigment.g)
              + (vec3(sky * 1.2) + vec3(0.3, 0.06, 0.14) * neon) * fresnel * 2.0 * shoulder;
    } else if (panel == 12 && !intakePaint) {
        // Gloss black plastic: the flat panel mirrors the city; the spotlight cans only glow with it.
        light = mask.g > 0.5 ? pigment * 0.85 + cityLight(r, 7.0) * (0.004 + fresnel * 0.03)
                             : pigment * 0.5 + cityLight(r, 3.5) * (0.03 + fresnel * 0.2);
    } else if (panel == 13) {
        // Lamp glass over a silvered reflector, bright in a ring round the dark bulb, with
        // the city and a hard sky highlight on the dome.
        light = pigment * (0.15 + 0.6 * smoothstep(0.15, 0.85, length(d))) + cityLight(r, 5.0) * (0.2 + fresnel * 0.8)
              + vec3(pow(max(dot(r, sun), 0.0), 24.0) * 0.6);
    } else if (panel == 14) {
        // Chrome reflects nearly everything, darkening where it faces away from the sky.
        light = cityLight(r, 5.0) * pigment * 1.1 + pigment * (0.05 + 0.3 * pow(max(dot(r, sun), 0.0), 6.0));
    } else if (panel == 15) {
        // The cabin sits in shadow: a pool of light mid-cabin falls off into the footwells and
        // corners, neon spilling blue through the windscreen and pink through the rear windows.
        float pool = exp(-pow((p.x - 250.0) / 80.0, 2.0) - pow((p.y - 105.0) / 30.0, 2.0));
        light = pigment * (0.08 + 0.18 * smoothstep(40.0, 115.0, p.y) + 0.45 * pool)
              * mix(vec3(0.7, 0.82, 1.0), vec3(1.0, 0.7, 0.85), smoothstep(150.0, 330.0, p.x));
    } else if (wheel) {
        // Satin gold uses a broad highlight instead of detailed city reflections.
        float edge = pow(1.0 - max(dot(n, v), 0.0), 5.0);
        vec3 metal = mix(pigment, vec3(1.0), edge);
        float highlight = pow(max(dot(r, sun), 0.0), 4.0);
        light = pigment * (0.30 + 0.25 * max(n.y, 0.0)) + metal * highlight * 0.85;
    } else {
        float diffuse = 0.20 + 0.36 * max(dot(n, sun), 0.0);
        diffuse *= mix(0.58, 1.0, smoothstep(18.0, 80.0, p.y));
        light = pigment * vec3(0.65, 0.75, 1.0) * diffuse + cityLight(r, mix(3.5, 6.0, cheekBlend)) * mix(0.10 + fresnel * 0.70, 0.06 + fresnel * 0.18, cheekBlend);
        if (wing) {
            // A broad sky reflection rolls over the airfoil's nose, across every livery colour.
            light += vec3(0.20, 0.25, 0.36) * pow(max(dot(n, normalize(vec3(-0.5, 0.86, 0.0))), 0.0), 24.0);
        }
        // The front box flare stands 4 proud of the door below the shoulder: its rear step (x 142-144)
        // faces away and it shades the door just behind.
        if (panel == 1) {
            float below = smoothstep(72.0, 66.0, p.y) * smoothstep(14.0, 20.0, p.y);
            float stepFace = smoothstep(141.5, 142.5, p.x) * (1.0 - smoothstep(143.5, 144.5, p.x));
            float behind = smoothstep(143.5, 144.5, p.x) * (1.0 - smoothstep(144.5, 152.0, p.x));
            light *= 1.0 - below * (0.35 * stepFace + 0.16 * behind);
            // The far fin's inner face falls into the wing's shade toward the plane.
            if (mask.g > 0.5) light *= 0.85 - 0.35 * smoothstep(104.0, 118.0, p.y);
        }
        light += pigment * (vec3(0.005, 0.04, 0.095) * (1.0 - smoothstep(60.0, 250.0, p.x))
                          + vec3(0.16, 0.007, 0.055) * smoothstep(190.0, 420.0, p.x));
        // Match the paint at the lip, then fall smoothly into the wheel well's ambient shadow.
        if (panel == 5) light = mix(light, pigment * 0.04, smoothstep(0.0, 0.85, recess) * wallCoverage);
    }
    // Lighting colours the white paint; the clear coat reflects above the stripes too.
    vec3 color = pow(clamp(light, 0.0, 1.0), vec3(1.0 / 2.2));
    fragColor = vec4(mix(base.rgb, color * base.a, mask.a * amount), base.a) * qt_Opacity;
}
