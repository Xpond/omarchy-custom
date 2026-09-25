# Lock screen

The lock screen has swappable designs. The patched `LockView.qml` is their host: it keeps
the password field, the connection to `Service.qml` and the wake handling, and loads a
design's `Scene.qml` from this checkout's `lock/`. That is outside the shell directory the
patches replace, so a design can span any number of files. Two ship: `rally`, described
below, and `wallpaper`, Omarchy's own blurred wallpaper.

## Designs

In the wheel, Style › Lockscreen Designs lists the designs (search "lockscreen"); picking
one only switches to it, and the next lock shows it. From a terminal,
`omarchy-lock-design list` and `omarchy-lock-design set <name>` do the same. The choice is one
word in `~/.config/omarchy-custom/lock-design` (`rally` when absent). The host watches that
file, so a switch needs no install or restart.

A design is a folder in `lock/` holding a `Scene.qml`, plus whatever QML, JavaScript,
shaders and images it loads relative to itself. The scene fills the screen behind the field.
Every design declares `property Item host`: the host sets it before the scene's bindings
run, and the log warns if it's missing. The rest is optional:

| Member | Use |
|---|---|
| `host` | The `LockView`, for state such as `backgroundPath`, `failureMessage`, `authenticatingPassword` or `passwordText.length` |
| `play()` | Called when the lock shows, and on the first key or click after a wake |
| `hide()` | Called when the display wakes from blank, so `play()` can run the entrance again |
| `leave()` | Called when the password is accepted; the lock releases 1.1s later, whatever it does |

A design that fails to load, from a syntax error or a missing folder, leaves the plain
background, and the field still unlocks. The wheel lists designs at startup and the shell
caches loaded QML, so after adding or editing a design run `omarchy restart shell`; neither
needs `install.sh` or sudo. Designs are not Omarchy plugins: only this host loads them onto
the lock surface, so an installed plugin cannot draw where the password is typed.

## Files and installation

| File | Responsibility |
|---|---|
| `patches/shell/plugins/lock/LockView.qml` | Host: password field, wake handling, loads the chosen design |
| `patches/shell/plugins/lock/Service.qml` | PAM flow, unlock delay, display blanking and wake state |
| `patches/orig/plugins/lock/` | Stock copies used by the verified install/revert workflow |
| `bin/omarchy-lock-design` | Lists the designs, or sets the one the next lock shows |
| `lock/wallpaper/Scene.qml` | The wallpaper, blurred, fading out on unlock |
| `lock/rally/Scene.qml` | Scenery, contact shadow, floor reflection and the car's framing |
| `lock/rally/Car.qml` | Projection, tracing, paint sweep and drive-off |
| `lock/rally/Paintwork.qml` | Material mask, shaded paint, outlines and comets, in draw order |
| `lock/rally/model.js` | Assembles the car from its parts |
| `lock/rally/shape.js` | Body width, nose warp and the curves every part is drawn with |
| `lock/rally/outlines.js` | Traced outlines: sills, wheels, shell, flank, front, details and wing |
| `lock/rally/cabin.js` | Dash, steering wheel, roll cage, harness and seats |
| `lock/rally/body.js` | Painted panels: bodywork, glass, wheels, mirrors, lamps and wing |
| `lock/rally/livery.js` | Stripes, decals, lettering and the side intake |
| `lock/rally/car-paint.frag` / `.qsb` | Analytical surface normals and city reflections, source and compiled |
| `lock/rally/car-focus.frag` / `.qsb` | Final camera focus pass, source and compiled |
| `lock/rally/neon-city.png` | Illustrated background and paint reflection source |
| `tests/lock.js` | Model, geometry, tracing and drive-off checks |
| `tests/lock-render.py` | GPU captures, drive-off exit and design switching checks |
| `tests/lock_parts.py` | Wing occlusion and wing, mirror and flap shading checks |
| `tests/lock_pixels.py` | Material, scenery and seam regression checks |

Run `./install.sh` to apply the patches. It links `lock/` to `~/.local/share/omarchy-custom/lock`
before updating the QML and restarting the shell, and needs no shader compiler. `./revert.sh`
restores stock files, then removes the link and the design choice only after a successful
restore, so a retained custom lock screen can still render. Installer tests cover both paths,
including failures.

Three files exceed the ~200-line limit, each reading best whole: `LockView.qml` (about 300
lines, mostly the stock password field), `Car.qml` (about 350: the car's state and the logic
that drives it) and `Paintwork.qml` (about 300: a mask and paint that must stay in step).

## Rally

A fixed front-left view of a Sport quattro S1 E2 assembles as blue comets trace its outlines.
The wireframe builds over 2940ms, followed by a 600ms paint sweep from nose to tail.
Successful authentication starts the car, spins the wheels and launches it left;
the session unlocks after the 1.1-second drive-off.

The scene uses a painted neon-city plate behind the live car, a contact shadow,
a subdued wet-floor reflection and a 480×72 dark glass password field. The grille
and wheel wells have solid dark backing so the bright pavement cannot show through.
The accepted artwork is **1672×941**, generated with the built-in imagegen tool.
A native 4K replacement is deferred. The original prompt is saved beside the image.

The car is framed at 89% scale about screen centre, then lowered by 4% of screen
height. The shadow and floor reflection share these transforms through the drive-off.
The paint layer uses smooth filtering so the smaller car keeps clean edges.

## Model and animation

`carModel()` in `model.js` returns `{ parts, surfaces, panes, dash }`. Parts are 3D polylines with
cumulative distances and trace timings; surfaces carry a paint tone and optional
wheel axle. Design units are approximately centimetres: x along the car, y upward,
z across it, with the near side at negative z.

- `warp()` shortens the nose; `shape()` leans and rounds the bumper. Every outline,
  surface and decal uses the same transform.
- `zAt()` defines the body width and box flares. `along()` samples flank lines so
  they follow those flares; `across()` and `smooth()` form crowned tops and soft edges.
- The body has black window frames, a painted windscreen surround, six spotlights,
  solid navy mirrors, a charcoal roll cage and two bucket seats with red harnesses.
  Interior outlines are clipped to glass and occluded by the seats and dashboard.
- Wheels have a tyre radius of 32, dished gold mesh rims and recessed hubs. Wheel
  parts rotate around their axle; visible tread edges marked `still` follow the wheel
  without rotating. Tyres are black rubber with a shine along the shoulder.
  Each tyre has a complete 20-unit-deep cylinder, projected as one convex silhouette
  behind the bodywork. The wheel-well backing reaches the bottom of each opening,
  keeping the tread and recess solid when the body pitches during launch.
- Decals are geometry on the body: Martini bands wrap continuously around the
  bumper and sweep over the rear quarter. Lettering follows the same surfaces.

`project()` uses yaw 30°, downward pitch 0.2 radians and perspective distance 1400.
The scale fits 88% of the width or 80% of the height; the camera centre is four design
units above screen centre. The shader reconstructs rays from these same values. Its
nose constants are post-warp positions (front-face anchor x 7, bumper corner base 18,
spotlight planes 7 and 5.7, headlamps 14); pre-warp values silently miss the lamps.

Each outline takes `max(300, length / 0.9)` milliseconds. `add()` starts one every
22ms across all groups: sills, wheels, body, glass, then cabin. This keeps 13–15
outlines in flight without pauses between groups. `car.traced` ends the tracing;
`car.paintTime` is the paint sweep; `car.duration` is their sum. Each comet has three
heat bands and a glow, with its flight offset easing to zero as tracing completes.
`frame()` rebuilds finished outlines only when another part completes. Line groups
0–3 cover interior, detail, panels and silhouette; group 4 renders construction edges
beneath paint. `underPaint` marks edges the paint covers (the rear opening, rounded
bumper join, wing and intake mouth), preserving the tracing without drawing a seam
over a continuous painted surface.

| Drive-off time | Behaviour |
|---|---|
| 0–300ms | Lamps flicker on; the body idles with a small shake |
| 300–500ms | Wheels spin; the body pitches nose-up around the rear axle |
| 500–1100ms | The car scales and slides left with trailing speed streaks |

Wheel rotation advances by up to 0.14 radians per frame to avoid apparent reverse
rotation. Body surfaces pitch and shake; wheel surfaces do not. The shader undoes
the body pose before shading so the environment stays fixed. The floor reflection mirrors
the car about its tyre-contact line, blurs and fades it, and follows the animations.

## Paint and shader

Visible geometry uses `Shape.CurveRenderer`. A separate offscreen material mask uses
`GeometryRenderer`: interpolating discrete material IDs at its edges would select
unrelated materials. Mask red stores `panel / 16`; green stores top-plane height / 160,
or on black plastic whether it is a spotlight can. Cabin tones get one mask fill each:
overlapping tones merged into one path cancel under either fill rule.
The solid far cabin panels use winding fill: odd-even curve tessellation dropped
triangles through the windscreen and beside the seat as the body pitched during drive-off.

| Mask ID | Surface |
|---|---|
| 0 | Excluded: glass, centre caps, glints and background |
| 1 | Flank, wheel skirts and wing fins (green encodes their Z plane) |
| 2 | Front faces |
| 3 | Hood, roof, deck, bumper ledge; wing (green 1) |
| 4 | Upper flank |
| 5 | Inner arch walls and recessed sill return |
| 6 | Windscreen surround |
| 7 | Rounded bumper |
| 8–10 | Gold rim lip, spokes and hub |
| 11 | Tyre sidewalls, treads and volume |
| 12 | Gloss black lamp panel, spotlight cans, intake and wing carbon tips |
| 13 | Lamp and indicator glass |
| 14 | Chrome bezels and spotlight rims |
| 15 | Cabin shell, seats, dash and roll cage |
| 16 | Rounded mirror housings (green 0 near / 1 far) and rubber flaps (green 0.5) |

The S1 wing is kept compact: a 24-unit chord and a 2-unit airfoil section from x 384
to 408, rising from 120 to 121.5. It stands on white fins flush with the deck's edges
(z ±76), no deeper than the plane: from a short foot (x 393–403) their front edges
sweep forward to its nose, like the S1's, with carbon tips curving up over the
trailing edge. The deck runs flat to the tail (the Quattro's lip is gone), and each
fin's rear edge rises from the tail's top corner, so nothing pokes out beside it.
The fins share the flank's curved clear-coat normal, so the body's reflections carry
across them; the far fin's inner face darkens toward the plane's shade. The carbon
tips use the mirror housings' glossy material, their normals curling up and forward
toward the top edge into a sky highlight; mask blue marks the far tip's plane. The
plane, far fin and far tip render before the cabin/body in both paint and mask; only
the near fin and tip render afterward. Wing tracing sits under the paint, so the roof
and C-pillar hide the far fin.
The mirrors are flattened rounded housings, with an explicit rear rim and short
mount. Their shader intersects the same rounded-box surface used by the geometry.
The intake mouth lies on the flare's front face at x=270, spanning its width in z.
Its mesh sits behind that plane along the car's length. A painted outer cheek blends
back into the arch at x=286 and into the shoulder/sill above and below. The body and
livery share this surface; the shader intersects the same shape. Intake mask green
0.4 uses blue 1 for mesh, 0.5 for the return, 0.25 for the front lip, and 0 for the cheek.
The ochre rubber flaps shade continuously into the arch.

These mask IDs are separate from the QML paint-tone indices into `car.paint`:
`Paint { tone: N }` fills tone N's surfaces in its pigment, and `Inked` strokes a tone
at its `car.ink` width. Bumper tone 28 has its own surface group and the same pigment
as flank tone 0. It must not inherit the upper-flank pigment: even a small difference
leaves a visible seam below the stripes.

The fragment shader reconstructs each surface position, adds analytical curvature to
its normal, and samples the city artwork in the reflected direction. This treats the
2D plate as an approximate environment, not a calibrated panorama. A fixed mip level
keeps the clear-coat reflections soft at both 1080p and 4K. Cooler, dimmer diffuse light
and pink spill from the signs replace the white studio lighting.
It shades in linear colour and converts back for display. Reflections cover the
livery; gold retains its satin response. Shading covers whatever the mask holds,
so unpainted tracing is unchanged and the metal arrives with the paint.
Gold uses one broad reflection lobe for a continuous satin highlight on the hubs and
rims. Its lighting branch skips the body clear coat's detailed city reflections.
Tyre sidewalls are flat, rolling over at the shoulder, where they shine with analytic
lights only: a sky highlight and a soft pink glow. Mirroring the city there washed them
grey, and even its bright lights alone smeared into streaks across the turning shoulder.
Spotlight cans sample the city at a high mip level, only as a faint glow. The rim barrel
has no outline: seen through the mesh, it read as the tyre's far side. Lamps are domed
round the known spotlight centres (headlamps curve across their height): glass shows a
bright reflector ring round a dark bulb and chrome mirrors a softened city. The cabin
sits in shadow with a pool of light mid-cabin, blue at the front and pink at the rear.
The nose's fine lines and spotlights draw inside the shaded layer so the spotlights can
be lit; their draw order is unchanged.

Every painted group is a `Coat`, clipped at `car.front` until `painted == 1`.
Sliding the clip avoids reshaping surfaces each frame. The material mask uses the
same clip on a wrapping `Item`, since a layered shape cannot clip its own paths.
`car.wavefront` follows the surface crossings, stroked in the comets' blue.

This approximates curved panels on projected polygons. It is not a full 3D mesh or
PBR renderer; glass and outlines retain their existing rendering.

### Joins that must stay continuous

- **Bumper:** `faceAt()`/`shape()` and the shader agree on the corner and lower foot;
  the tangent matches the flank's full normal and lighting position.
- **Wheel skirts:** share the flank's normal field, without a separate radial highlight.
- **Inner returns:** a radius-36 cylinder blends from the lip at z=-88 to shadow at
  z=-80; coverage outside the opening preserves body lighting. Shadow fades below
  1.5 pixels of projected width. The sill return shares this recessed material.
- **Arch geometry:** `wallAngles()` solves the projected edge meeting; `arch()` uses
  one two-degree grid for the opening and returns, without an extra return stroke.
- **Draw order:** construction lines stay beneath paint, including the rear opening
  and bumper joins.

The final focus pass covers the complete car, including its outlines. A height
ramp between the projected tops of the near wheels and the far roof approximates
depth: wheels and lower body stay sharp, while upper edges soften with a nine-tap
Gaussian kernel reaching 1.35 pixels at 1080p (scaled for 4K). Premultiplied color
and alpha blur together to blend into the scenery without dark fringes. The ramp
follows body pitch, lives inside the departure transforms, and fades in with paint.

After GLSL changes, rebuild the bundled shaders:

```bash
/usr/lib/qt6/bin/qsb --glsl '100 es,120,150' --hlsl 50 --msl 12 \
  -o lock/rally/car-paint.frag.qsb lock/rally/car-paint.frag
/usr/lib/qt6/bin/qsb --glsl '100 es,120,150' --hlsl 50 --msl 12 \
  -o lock/rally/car-focus.frag.qsb lock/rally/car-focus.frag
```

## Wake and authentication

The service blanks the display five seconds after the last input. Waking keeps it
on for at least ten seconds. The waking key/click only wakes it; the next key/click
starts the drawing. Mouse movement wakes but does not start the animation. This
avoids playing the entrance while a monitor is still restoring its picture after
DPMS; the system does not report when that picture becomes visible.

Authentication stays in the stock trusted lock plugin. On success, `unlocking`
disables input and calls `driveOffThenUnlock()`; its 1100ms timer calls `finishUnlock()`.
`LockView` input handlers preserve the wake-before-draw ordering.

## Verification

```bash
node tests/lock.js
python3 tests/lock-render.py
python3 tests/install.py
```

The GPU test opens a temporary preview, never a session lock. The expanded capture
sequence has a 150-second timeout. It needs a working
Wayland/OpenGL session, Quickshell and ImageMagick. Captures go to `/tmp/lock-render/`
or a directory supplied as its argument. They cover tracing, paint, parked and
drive-off states at 1080p and 4K, including a check that the car clears the frame. Geometry probes read unlit twins
of the drive-off frames, since the shader darkens the cabin. Last, the host switches to `wallpaper`
and then to a missing design: the field stays on both, and the missing one leaves the plain background.

`lock_parts.py` compares wing-visible and wing-hidden captures at 1080p and 4K,
checks that the roof and C-pillar over the far fin are unchanged, that the near fin
and carbon tip aren't shaded flat, and checks curved mirror highlights and smooth
flap shading. It can re-check existing captures: `python3 tests/lock_parts.py /tmp/lock-render`.

`lock_pixels.py` decodes captures once and checks scenery, neon reflections, night
lighting, opaque grille/arch backing, material isolation, black rubber with a neutral shine, satin gold,
cabin fills and continuous panel joins. Its material coordinates are car-space pixels;
`pixels()` applies the scene framing, which must match `carFraming` and `carLower`.
Probes on a part move with it: the rear-wheel probes followed the axle to x 322.
Reflection gradients are allowed; abrupt seams are rejected. Sharp/focused
pairs check that distant edges soften while the foreground and background stay crisp.
`lock.js` checks geometry, clipping, tracing pace and finite drive-off frames,
including solid tyres across their full width, closed lower wheel wells, and the
wing's near fin covering the tail's top corner.
Inspect whole captures as well as pixel probes; cleanup should preserve both.

`omarchy-shell lock preview` and `omarchy-shell lock hidePreview` show/hide the real
view without locking. That preview plays the entrance but does not exercise PAM,
drive-off or wake flow. For lock events, inspect the user journal for `omarchy lock`:
`display: blank`, `display: wake`, `unlock: driving off`, `unlocked`.

Use GPU captures for visual checks; SVGs miss Qt fill defects and the software
renderer has crashed on this scene. Use a timeout and file-backed Quickshell logs
so crash-handler pipes cannot hold the test open.

## S1 E2 history

The car began as an Ur-quattro and was converted to the Sport quattro S1 E2 against
`car-refs/`, 57 local photos (git-ignored) of the HB Audi Team S1 E2 #2 (Mikkola/Hertz).
Its side profile was overlaid on `car-refs/05.jpg`, aligned at the front axle and
ground and scaled by the real 2224 mm wheelbase. The new proportions are permanent:

| Design units (≈ cm) | Ur-quattro model | S1 E2 photo | Model now |
|---|---|---|---|
| Front overhang | 79 | ~98 | ~99 (nose warp 30 → 10) |
| Wheelbase | 252 | 222 | 222 (rear axle 352 → 322) |
| Door rear edge → rear axle | 90 | ~56 | 60 |
| Rear axle → tail | 92 | ~83 | 83 (tail 444 → 405) |

Roof (134) and belt (93) already matched. The glass, cabin, rocker step, stripes, fuel
flap, taillamp, streak points and the shader's pitch pivot followed the rear axle, and
`carLower` gained its 3% x shift to re-centre the shorter car.

Rejected along the way; don't retry these without a new direction from the user:

- **Bonnet vents:** triangular S1 openings, aligned louvres, black-backed pockets with
  woven floors and tapered outboard cutouts all read as grilles laid on the hood, with
  pixelated edges and stripes cut between slots. The bonnet is continuous; a new attempt
  must solve the flatness, the edges and the stripe clash.
- **Side intake:** side-facing recesses read as pasted on and flat, even with deeper
  shading. The mouth now faces forward on the flare's front face.
- **Mirrors:** pointed cones; now rounded, flattened housings.
- **Wing:** a 46–60 unit chord on grey block supports with end plates read as bigger than
  the car, and its far side drew over the roof. The Quattro's deck lip poked out beside
  it; the deck now runs flat to the tail, without the lip or its black rubber strip.
- **Mud flaps:** flat colour bands; now continuously shaded rubber.

## Remaining work

- Custom Martini/Omarchy livery on the S1 E2 body; aero parts remain subject to visual review.
- Thin gaps along the roof and belt show during pitch.
- Multi-monitor and fingerprint unlock still need device testing. Typing immediately
  after waking can start the drawing before the display is visible.
- Sustained 144 Hz pacing needs measurement; native 4K artwork is deferred.
  Earlier 144fps results predate the metallic shader and are not current benchmarks.

If the real lock gets stuck, switch to a TTY with Ctrl+Alt+F2 and log in. Run
`./revert.sh` from this checkout to restore the verified stock files, then restart
the session. Reverting from a working desktop also restarts the shell automatically.
