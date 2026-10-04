# Lock screen

The lock screen has swappable designs. The patched `LockView.qml` is their host: it keeps
the password field, the connection to `Service.qml` and the wake handling, and loads a
design's `Scene.qml` from this checkout's `lock/`. That is outside the shell directory the
patches replace, so a design can span any number of files. Six ship: `rally`, `tunnel`,
`mycelium`, `shore` and `meadow`, described below, and `wallpaper`, Omarchy's own blurred wallpaper.

## Designs

In the wheel, Style › Lockscreen Designs lists the designs (search "lockscreen"); picking
one only switches to it, and the next lock shows it. From a terminal,
`omarchy-lock-design list`, `current` and `set <name>` do the same. The choice is one
word in `~/.config/wheely/lock-design` (`rally` when absent). The lock and its preview
build their view each time they show, reading that file then, so a switch needs no install or
restart.

A design is a folder in `lock/` holding a `Scene.qml`, plus whatever QML, JavaScript,
shaders and images it loads relative to itself. The scene fills the screen behind the field,
which is frosted glass: the scene blurred under a dark tint, edged in the design's accent with a
faint glow.
Every design declares `property Item host`: the host sets it before the scene's bindings
run, and the log warns if it's missing. The rest is optional:

| Member | Use |
|---|---|
| `host` | The `LockView`, for state such as `backgroundPath`, `failureMessage`, `authenticatingPassword` or `passwordText.length` |
| `play()` | Called when the lock shows and automatically when wake completes |
| `hide()` | Called when the display blanks, resetting the design for its next `play()` |
| `leave()` | Called when the password is accepted; the lock releases after 550ms for mycelium or 1.1s for the other designs, whatever the animation does |
| `accent` | The field's edge colour, in the design's own light; white when absent |

A design that fails to load, from a syntax error or a missing folder, leaves the plain
background, and the field still unlocks. Each lock or preview runs in a fresh worker, so edits
appear on its next opening. Restart the shell after adding a design to refresh the wheel's
list; neither needs `install.sh` or sudo. Designs are not Omarchy plugins: only this host loads them onto
the lock surface, so an installed plugin cannot draw where the password is typed.

## Files and installation

| File | Responsibility |
|---|---|
| `patches/shell/plugins/lock/LockView.qml` | Host: password field, wake handling, loads the chosen design |
| `patches/shell/plugins/lock/Service.qml` | PAM flow, unlock delay, display blanking, wake state and the preview |
| `lock-session/Bridge.qml` | Keeps the shell's lock IPC available and starts/reconnects the worker |
| `lock-session/shell.qml` | Runs the installed authentication service and exits after unlock/wake or preview closure |
| `patches/orig/plugins/lock/` | Stock copies used by the verified install/revert workflow |
| `bin/omarchy-lock-design` | Lists the designs, names the chosen one, or sets the one the next lock shows |
| `lock/wallpaper/Scene.qml` | The wallpaper, blurred, fading out on unlock |
| `lock/tunnel/Scene.qml` | The wheel's mark stacked into a corridor, flown through |
| `lock/tunnel/mark.vert` / `.qsb` | Places and fades one mark as the flight goes on, source and compiled |
| `lock/tunnel/mark.frag` / `.qsb` | One mark: its maze and a comet running through it, source and compiled |
| `lock/tunnel/space.frag` / `.qsb` | The glow at the tunnel's far end and the dust, source and compiled |
| `lock/mycelium/Scene.qml` | Grows and draws back the colony, drifts the camera, and draws the canvases its shader reads |
| `lock/mycelium/grow.js` | Grows a colony: its lines, the step that reaches each, and the light it casts |
| `lock/mycelium/mycelium.frag` / `.qsb` | The colony as grown so far on the ground it lights, and its deep hyphae, source and compiled |
| `lock/mycelium/ground.frag` / `.qsb` | The ground's clouds and grain, drawn once, source and compiled |
| `lock/shore/Scene.qml` | Runs the surf's clock, fades the beach in and brings the tide in on unlock |
| `lock/shore/shore.frag` / `.qsb` | The wash: its edge, water, foam and light, and the sand it wets, source and compiled |
| `lock/meadow/Scene.qml` | Prepares the plant tables and near bank, and runs growth, wind and the unlock fade |
| `lock/meadow/garden.js` | Flower lettering and meadow flowers, and their plant table |
| `lock/meadow/foreground.js` | Near ground cover, grass and mossy stones, the stones' outlines, and the larger flowers framing the clearing |
| `lock/meadow/plants.vert` / `.frag` / `.qsb` | Grass, stems, leaves, tendrils and flowers as they grow, and the lower flowers' sway, source and compiled |
| `lock/meadow/meadow.frag` / `.qsb` | Night sky, moon, clouds, fireflies, ground and the swaying garden, source and compiled |
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
| `tests/lock.js` | Finite tracing and drive-off frames, paint sweep, glass clipping and flat-pose bounds |
| `tests/lock-idle.js` | The shared five-second idle blank, the monitor wake allowance and one replay per wake |
| `tests/mycelium.js` | Colony coverage, arrival steps and light distribution |
| `tests/mycelium-render.py` | Strand smoothness at 1080p and 4K, and growth across the packed step boundary |
| `tests/meadow-render.py` | Wind keeps roots fixed, bends stems coherently and moves them smoothly, in the lettering and on the near bank, at 1080p and 4K |
| `tests/lock-render.py` | GPU captures, drive-off exit and design switching checks |
| `tests/lock-process.py` | Offscreen memory, process exit, shell reconnection and crash recovery; simulated compositor and authentication |

Run `./install.sh` to apply the patches. It links `lock/` to `~/.local/share/wheely/lock`
and links the worker plus the installed lock service and Commons under `lock-session/`
before updating the QML and restarting the shell, and needs no shader compiler. `./revert.sh`
restores stock files, then removes the link and the design choice only after a successful
restore, so a retained custom lock screen can still render. Installer tests cover both paths,
including failures.

The desktop shell retains only the bridge. A separate Quickshell process owns PAM and the
lock surfaces, using the same patched service, then exits after unlock and the final wake
command. This releases the renderer's native and graphics caches. The worker stays alive
while locked, including while blanked, and survives a desktop-shell restart. Only lock,
preview and hide-preview commands cross the private runtime socket; passwords stay in the worker.
Its normal startup also runs the existing stranded-lock recovery check before retiring.

## Meadow

Multicolored wildflowers grow into lowercase “omarchy” above a flat meadow occupying the
bottom 20% of the screen, with a soft, irregular grassy edge. Behind it, a night sky deepens
overhead above a sunset glow that meets the meadow's horizon, warmest on the right. Twinkling
stars thin out towards the glow. Banks of cloud, their undersides lit by the sunset, drift
right with the breeze across the upper sky, with clear sky between them. A dim crescent moon
hangs top right behind a thin, drifting haze that shows only in its light, and passing clouds
veil it further. Fireflies, each a hot core in a warm glow, drift and pulse over the meadow.
Larger flowers, overlapping ground cover and low, rounded mossy stones frame a shallow clearing
around the password field. The closest corners soften out of focus to give the garden depth.
The exposed ground has patchy moss, soil grain, tiny pebbles and fallen stems, with finer
detail towards the far edge. Near-ground texture is painted once beneath the foliage.
Grass blades rise and bend over first. Shoots then climb out of the meadow, a green bud
nodding at each tip as it circles and leans; leaves unfold from beside the stem once the tip
has passed, and tendrils coil tighter as they lengthen. Each tip's small searching bend settles
as it climbs, independently of flowering. Buds begin opening during the climb at varied rates,
and gradually lift to face the viewer: sepals fold back and the
petals, each a blade tilted in 3D, spread from a cup to nearly flat, while lavender florets
open from the bottom of the spike. Individual petals loosen at slightly different rates;
the word emerges from the moving buds and finishes within four seconds after
preparation, before the normal five-second idle blank.

`garden.js` packs blossoms tightly along rounded, evenly spaced letter strokes, each on a
warm, lit, nearly upright stem that wavers slightly. Pointed leaves and curling tendrils
gather below the lettering, leaving the letters' insides open; flower heads are drawn after
all foliage, so no leaf hides part of a letter. Smaller flowers and grass clumps are scattered
near the ground. Daisies, cosmos, poppies, blue flowers and lavender spikes vary in petal
shape, size, tilt and foliage. Their layout uses a 900-unit-high frame, the word centred in it.
Plants grow as live geometry. A small canvas holds a table of every plant, one 24-bit
fixed-point field per texel, which `plants.vert` reads to shape each part of each plant at the
current moment: three grid meshes draw grass, then stems, leaves and tendrils, then flower
heads, each part a ribbon of quads whose end rows collapse so parts never join. `plants.frag`
antialiases ribbons and leaves across their width and ray-casts each flower head's sepals,
petals and centre as tilted blades and a disc, keeping the two nearest surfaces per pixel.
The meshes render the lettering and grass into a layer while growth runs; once it finishes
the layer stays still, and `meadow.frag` bends it with a quicker sway, traveling gusts and a
smaller rustle, continuing through the end of growth. Bending grows quadratically above the
meadow, keeping the roots still; explicit horizontal interpolation prevents pixel-sized jumps
in the texture. The lower flowers, the meadow's and the near bank's larger ones, sway from
their own roots in the same breeze, a few degrees at most: `plants.vert` bends their stems and
carries leaves and heads along, redrawing them every frame into two layers covering the
bottom 30%. A second canvas paints the near bank's ground, grass and stones once, back to
front so each stone hides what grows behind it, and returns its flowers for the plant shaders.
Below that, it holds each stone's outline and front edge, so `plants.frag` hides the flowers
rooted behind it. `meadow.frag` draws the sky and ground, the meadow's flowers behind the near
bank and its own in front, and softly reveals the bank and blurs its closest corners.
Blanking stops the clock; waking regrows the garden. Unlocking
fades it within the host's 1.1-second release delay. At 1080p `meadow.frag` takes about 0.28ms
on a GTX 1080 Ti at full clocks, skipping stars, ground noise, cloud rims and fireflies wherever
they cannot show; the swaying lower flowers add about 0.12ms a frame, and the plant layer about
0.2ms while it grows.

Rebuild the shaders after GLSL changes:

```bash
for shader in meadow.frag plants.vert plants.frag; do
  /usr/lib/qt6/bin/qsb --glsl '100 es,120,150' --hlsl 50 --msl 12 \
    -o lock/meadow/$shader.qsb lock/meadow/$shader
done
```

## Tunnel

Forty copies of the wheel's mark, stacked in perspective, form a corridor flown through
first person. The mark is the centrelines of Omarchy's icon on its 30-unit grid: drawn 0.1
wide they cover every stroke pixel of the wheel's `mark.png`; the tunnel draws them 0.07
wide. Marks stand every 4 units, each 0.7–1.3× in size and turned at random; the
choice is fixed by its place along the corridor, so a mark keeps it as it nears, and one flown
past returns to the far end as another. It fades in there, and fades out from 3 units ahead to
1.5, where even the smallest is already past the edges of a 16:9 screen.
The corridor's centreline wanders on a few sine waves; the camera looks down its tangent, so
the far end swings, and it banks into the turns. The view is 90° high: a mark 14 units
ahead fills the screen's height.

Each mark is a `ShaderEffect`: `mark.vert` places it from the distance flown, and `mark.frag`
draws the maze's 17 stretches and a comet through them as the wheel's runs: out from where the
bottom bar meets the inner square, splitting at every junction. Each stretch carries its ends'
distances along the maze, which match `mark.png`'s at every junction. A mark's place picks its
hue, from cyan to magenta, and its comet's start, pace (0.3–0.8 laps a second at cruise), tail
(12–35% of the run) and way round: three in ten run back in from the ends. The comets keep time
with the flight, so they race on unlock. Behind the marks, `space.frag` lights the far end,
where the tunnel's tangent meets the screen, and dust drifts past as small dots, each its own
size. Before evaluating a dust mote's heading and coverage, the shader rejects pixels farther
from its radial distance than the largest mote can reach. This leaves identical pixels while
roughly halving the dust pass's GPU cost.

QML works out each mark's depth every frame, and the random picks for its place only when it
comes round again; its position, size, turn, fade and comet head come from the vertex shader, so
a frame moves 40 marks without moving 40 items. A mark faded below a thousandth isn't drawn, and
`mark.frag` returns early for points farther than any glow from the grid lines every stretch
lies on. At 1080p on a GTX 1080 Ti the tunnel holds 144fps using about a tenth of a CPU core and
0.76ms of GPU time a frame at full clocks.

`play()` fades the tunnel in over 1.2s while it accelerates to 8 units a second.
`leave()` accelerates tenfold and fades out within the 1.1s before the lock releases.
The flight pauses while the display is blank. After GLSL changes, rebuild the shaders:

```bash
/usr/lib/qt6/bin/qsb --glsl '100 es,120,150' --hlsl 50 --msl 12 -b \
  -o lock/tunnel/mark.vert.qsb lock/tunnel/mark.vert
/usr/lib/qt6/bin/qsb --glsl '100 es,120,150' --hlsl 50 --msl 12 \
  -o lock/tunnel/mark.frag.qsb lock/tunnel/mark.frag
/usr/lib/qt6/bin/qsb --glsl '100 es,120,150' --hlsl 50 --msl 12 \
  -o lock/tunnel/space.frag.qsb lock/tunnel/space.frag
```

## Mycelium

Fine hyphae grow from the centre, with white tips cooling through cyan to teal. They light a
mottled ground, with a softer colony beneath them for depth. The camera drifts and the strands
sway slowly. Unlocking draws the colony back into the centre while it fades.

`grow.js` builds a new colony each lock in a coordinate space 1080 units high. Twelve strands
step outward, wander, branch into open space and fuse when they meet another strand. Each tapers
according to the length it feeds, including its branches. The result contains paths grouped by
width, segments grouped by arrival step, and a coarse map of density and average arrival time.
The scene calls `begin()` and resumes its builder with a 3ms budget on each timer tick, so colony
creation leaves time for input and the first frame. It pauses while blanked and releases the
builder when complete.

`Scene.qml` draws four canvases once, each on the canvas thread rather than holding up the lock:
the arrival map takes a quarter of a second. Growth starts once all four have drawn.

- `web`: antialiased surface lines.
- `times`: arrival steps packed into red and green, drawn without antialiasing. Wider strokes
  cover the line edges; earlier steps win at intersections.
- `shine`: the coarse light map.
- `deeper`: the colony at half resolution, with arrival time in its colour.

`ground.frag` draws the background once. `mycelium.frag` combines it with the canvases in one
full-screen pass. Cubic B-spline sampling smooths the surface lines during camera motion and
magnifies the light and deep layers. This removes the triangular edges left by bilinear line
sampling. The arrival map is sampled linearly and decoded without rounding its channels,
dividing out alpha at its edges; interpolation also works across the packed 255-to-256 boundary.

Growth advances at 45 steps a second on the frame clock, starting once the colony is drawn.
Both growth and camera motion pause when the display is blank. `hide()` resets growth and
freezes the ground while blanked; `play()` resumes both automatically after wake. `leave()`
keeps the camera moving while it retracts and fades over the host's 550ms unlock delay; then the
clock stops.

After GLSL changes, rebuild the shaders:

```bash
for f in mycelium ground; do /usr/lib/qt6/bin/qsb --glsl '100 es,120,150' --hlsl 50 --msl 12 \
  -o lock/mycelium/$f.frag.qsb lock/mycelium/$f.frag; done
```

## Shore

Where the wash meets the sand, seen close from high above: shallow water fills the top of the
screen, damp sand the bottom, and the water's edge moves across the middle. Every six seconds or
so a foaming bore comes down through the water, runs up the sand under a rope of foam and slides
back. Unlocking brings the tide in as the beach fades.

`shore.frag` draws everything in one full-screen pass from the time alone; `Scene.qml` only runs
the clock. Surges differ in strength, rhythm and angle, and in how uneven their fronts are. Each
reaches each stretch of shore at its own time, a second or two apart, and runs its own distance, so
its edge keeps changing shape: stretches race ahead, lag, or drain back while others still advance.
Running up, its lip frays into small tongues that form and fade; draining back, the thinning film
tears into patches. Its reach is a parabola in time, warped so the backwash takes longer than the
run up, and the next surge catches the backwash near the centre, so the edge stays about the
middle.

Each surge arrives as a foaming bore that thins to a rope of foam along its edge, with lace
drifting in patches on the water behind. Foam, ripples and the light they focus ride on the
topmost water, stretching as it spreads and sliding back with the backwash; a new surge's water
runs over the old under its foam. The ripples bend the sand seen through the water, their light
draws a moving web on it, the surface mirrors the sky and glints, and the shallows turn green,
then turquoise, as reds are absorbed. The foam casts a soft shadow up the beach. Where the
backwash draws back, the sand shines with the sky in draining patches and dries within 16 seconds,
and a thin line of bubbles is stranded where each surge stopped. The dry sand is pale and warm,
golden brown where wet, with fine grains, some dark and some catching the sun, patches of wind
ripples and small bumps lit from up the beach, and faint lines of grit where earlier surges
stopped.

600 surges make an hour, then the surf repeats. The ripples and the light drift a whole number of
their repeats in that hour, so the scene wraps its clock to the hour seamlessly and the shader's
floats stay precise. Each lock opens at a random point in the hour, and the clock pauses while the
display is blank. `play()` fades the beach in over 1.2s; `leave()`
raises the tide 1.2 screen heights and fades it out within the 1.1s before the lock releases. A
surge whose water can't reach a point, however far its lip frays, skips its water there. At 1080p a
frame takes 1.3ms of GPU time on a GTX 1080 Ti at full clocks, the most of any design.

After GLSL changes, rebuild the shader:

```bash
/usr/lib/qt6/bin/qsb --glsl '100 es,120,150' --hlsl 50 --msl 12 \
  -o lock/shore/shore.frag.qsb lock/shore/shore.frag
```

## Rally

A fixed front-left view of a Sport quattro S1 E2 assembles as blue comets trace its outlines.
The wireframe builds over 2940ms, followed by a 600ms paint sweep from nose to tail.
Successful authentication starts the car, spins the wheels and launches it left;
the session unlocks after the 1.1-second drive-off.

The scene uses a painted neon-city plate behind the live car, a contact shadow,
and a subdued wet-floor reflection. The grille
and wheel wells have solid dark backing so the bright pavement cannot show through.
The accepted artwork is **1672×941**, generated with the built-in imagegen tool.

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

The body keeps its parked shapes through the drive-off and takes its pose as one flat transform,
`car.bodyPose`: the affine least-squares fit, over every eighth body outline point, from where they
park to where the pose takes them. Paintwork's body shapes (`BodyCoat`, `BodyInk`, `BodyMask`)
carry it; the wheels' shapes sit between them in the same drawing order and are projected again only
as they turn. Streaks trail on screen from the posed body. The fit matches the shake within 0.5px,
but a flat transform can't show the squat's parallax: at full pitch it strays 4.7px on average and up
to 20px at 1080p (twice that at 4K). Re-posing the body exactly cost about 40ms of projection and
tessellation a frame and held the first 500ms near 25fps; the whole drive now keeps the display's 144fps.
`project()` runs once per size: width and height each report a resize, and the car completes at its size.

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
`Paint { tone: N }` fills tone N's body surfaces in its pigment (`Wheel` its wheel
surfaces), and `Inked` strokes a tone at its `car.ink` width. Bumper tone 28 has its own
surface group and the same pigment as flank tone 0. It must not inherit the upper-flank pigment: even a small difference
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
Before the paint starts both are transparent, so the layers redrawn for every tracing frame skip
them; transparent rather than invisible, since a hidden shape misses updates to its paths.
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

The service blanks the display after five seconds of inactivity, starting on lock and
restarting on input. After waking a blank display, a ten-second minimum allows the physical
monitor to recover: this display was measured taking about 4.2 seconds to show a picture after
DPMS returned. Input never shortens that allowance; afterward it gets the normal five seconds.
These rules apply to every current and future design, regardless of animation progress.
One wake starts the animation automatically. The countdown pauses while the wake command runs,
so it cannot expire while that command is restoring the display. An in-flight blank command
finishes before a queued wake starts. Input after a quiet second runs the wake scripts;
steady typing or a moving mouse just restarts the timeout. The wake allowance is a margin,
not a signal that the physical monitor has finished waking.

Authentication stays in the stock trusted lock plugin. On success, `driveOffThenUnlock()`
sets `unlocking`, which disables input; its independent timer calls `finishUnlock()`
after 550ms for mycelium or 1100ms for the other designs. Each lock view sets the interval from
its selected design; 1100ms remains the fallback if no view loads. The field fades out within
300ms, still reading "Checking…", so it is gone before any design finishes its exit.

## Verification

```bash
node tests/lock.js
node tests/mycelium.js
node tests/check.js
node tests/lock-idle.js
python3 tests/mycelium-render.py
python3 tests/meadow-render.py
python3 tests/lock-render.py
python3 tests/lock-process.py
python3 tests/install.py
```

The GPU test opens a temporary preview, never a session lock. It needs a working
Wayland/OpenGL session, Quickshell and ImageMagick. Captures go to `/tmp/lock-render/`
or a directory supplied as its argument. The car is captured parked, then departed, when it
must have cleared the frame. Then the host switches to `tunnel`,
which must draw its lines; `mycelium`, whose colony 1.5s after its textures are ready must have grown about the centre with
no line beyond it, where only the dark ground shows; `shore`, whose water must fill the top edge and
sand the bottom corner wherever in the surf it opens; `meadow`, which must have grown flowers;
then `wallpaper` and a missing design. The field's top edge shows each design's accent, white
for `shore`, `wallpaper` and the missing design, which leaves the plain background. Half a second
after the password is accepted, sooner than the shortest release, only that background remains
where the field was.

`tests/mycelium.js` grows colonies from fixed seeds at four
screen shapes: each must cross over 95% of the screen's 60-unit squares, every line drawn must have
its step, and its light must cover the screen, reaching the corners after the centre.

`tests/mycelium-render.py` renders three isolated, shallow-angle strands through the scene and
shader at 1080p and 4K. It checks brightness variation along their edges and growth across the
packed step's 255-to-256 boundary. Captures go to `/tmp/mycelium-render/` or the directory supplied
as its argument.

`lock.js` checks that every tracing and drive-off frame is finite, the paint sweeps the whole
car behind a lit edge, inside outlines are clipped to the glass, and the body's flat drive-off
pose keeps within half a pixel of the exact shake and 5px on average of the squat.
The tests check behaviour, not looks: inspect whole captures for visual changes.

`omarchy-shell lock preview` and `omarchy-shell lock hidePreview` show/hide the real
view without locking. That preview plays the entrance but does not exercise PAM,
drive-off or wake flow. For lock events, inspect the user journal for `omarchy lock`:
`display: blank`, `display: wake`, `unlock: driving off`, `unlocked`.

Use GPU captures for visual checks; SVGs miss Qt fill defects and the software
renderer has crashed on this scene. Use a timeout and file-backed Quickshell logs
so crash-handler pipes cannot hold the test open.

## S1 E2 history

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

- The S1 E2's aero parts remain subject to visual review.
- Thin gaps along the roof and belt show during pitch.
- Multi-monitor and fingerprint unlock still need device testing. Typing immediately
  after a wake command completes can precede the physical display becoming visible.
- Native 4K artwork is deferred.

If the real lock gets stuck, switch to a TTY with Ctrl+Alt+F2 and log in. Run
`./revert.sh` from this checkout to restore the verified stock files, then restart
the session. Reverting from a working desktop also restarts the shell automatically.
