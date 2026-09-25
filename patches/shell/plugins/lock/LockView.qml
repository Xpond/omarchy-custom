import QtQuick
import Quickshell
import QtQuick.Effects
import QtQuick.Shapes
import qs.Commons

Item {
  id: root

  property url sceneImage: "file://" + Quickshell.env("HOME") + "/.local/share/omarchy-custom/neon-city.png"
  property url paintShader: "file://" + Quickshell.env("HOME") + "/.local/share/omarchy-custom/car-paint.frag.qsb"
  property url focusShader: "file://" + Quickshell.env("HOME") + "/.local/share/omarchy-custom/car-focus.frag.qsb"
  property string backgroundPath: ""
  property int backgroundVersion: 0
  property bool fingerprintConfigured: false
  property bool authenticatingPassword: false
  property string failureMessage: ""
  property int failedAttempts: 0
  property bool inputEnabled: true
  property bool loadBackground: true
  property string passwordText: ""
  property bool syncingPasswordText: false
  // Set once authentication succeeds: the car drives off before the lock releases.
  property bool driving: false
  // True while the display is off.
  property bool blanked: false
  // Set on wake. The picture can take seconds to come back and nothing reports when, so
  // the car waits hidden and draws on the next key or click, when the screen is surely up.
  property bool awaitingInput: false

  readonly property string placeholderText: "Enter Password"
  readonly property int fieldWidth: 480
  readonly property int fieldHeight: 72
  // Room each side of the text for the lock icon and the submit button.
  readonly property int fieldInset: 64
  readonly property int fieldFontSize: Math.round(Style.font.heading * 1.125)
  readonly property int passwordDotFontSize: Math.round(Style.font.heading * 1.33)
  readonly property int passwordDotLetterSpacing: Math.round(Style.font.heading * 0.19)
  // Space to keep clear on each side of the field for the fingerprint icon
  // (icon width plus a gap) so the centered dots never run under it.
  readonly property real fingerprintReserve: fingerprintConfigured ? Math.round(fingerprintIcon.implicitWidth + 12) : 0
  // Shrink the dots to fit once the password outgrows the field, so every
  // keystroke stays visible — otherwise long passwords clip with no feedback.
  readonly property real passwordDotScale: dotMetrics.advanceWidth > 0
    ? Math.min(1, (passwordInput.width - 4) / dotMetrics.advanceWidth)
    : 1
  readonly property bool showPasswordCursor: inputEnabled && !authenticatingPassword && failureMessage.length === 0
  readonly property bool errorState: failureMessage.length > 0
  readonly property color neonColor: errorState ? Color.lock.borderError : "#8fd0ff"

  signal submitPassword(string password)
  signal passwordTextEdited(string password)
  signal clearFailureRequested()
  signal wakeRequested()

  function forcePasswordFocus() {
    passwordInput.forceActiveFocus()
  }

  function clearPassword() {
    passwordTextEdited("")
  }

  function syncPasswordText() {
    if (passwordInput.text === passwordText) return
    syncingPasswordText = true
    passwordInput.text = passwordText
    syncingPasswordText = false
  }

  onPasswordTextChanged: syncPasswordText()
  onInputEnabledChanged: {
    if (inputEnabled) Qt.callLater(forcePasswordFocus)
  }
  Component.onCompleted: {
    syncPasswordText()
    if (inputEnabled) Qt.callLater(forcePasswordFocus)
    if (loadBackground) car.play()
  }
  onLoadBackgroundChanged: if (loadBackground) car.play()
  onDrivingChanged: if (driving) car.driveOff()
  onBlankedChanged: if (!blanked && loadBackground) { awaitingInput = true; car.hide() }

  // Called before an input reports the wake, so the input that wakes the screen
  // doesn't also start the drawing.
  function startOnInput() {
    if (!awaitingInput) return
    awaitingInput = false
    car.play()
  }

  // Measures the masked password at full size; passwordDotScale compares this
  // against the field width to decide how far the dots must shrink to fit.
  TextMetrics {
    id: dotMetrics
    font.family: Style.font.family
    font.pixelSize: root.passwordDotFontSize
    font.letterSpacing: root.passwordDotLetterSpacing
    text: "●".repeat(passwordInput.text.length)
  }

  Rectangle {
    anchors.fill: parent
    color: Color.background

    // Painted scenery stays flat; the live car and its reflection render above it.
    Image {
      id: city
      anchors.fill: parent
      source: root.sceneImage
      fillMode: Image.PreserveAspectCrop
      smooth: true
      mipmap: true
    }

    MouseArea {
      anchors.fill: parent
      hoverEnabled: true
      onClicked: { root.startOnInput(); root.wakeRequested(); root.forcePasswordFocus() }
      onPositionChanged: root.wakeRequested()
    }

    // Contact shadow follows the car's shared framing and departure transforms.
    Canvas {
      anchors.fill: car
      opacity: car.painted
      transform: [carGrow, carSlide, carFraming, carLower]
      property var ground: car.ground
      onGroundChanged: requestPaint()
      onWidthChanged: requestPaint()
      onHeightChanged: requestPaint()
      onPaint: {
        if (!car.view) return
        var g = getContext("2d"), a = ground[0], b = ground[1], c = car.view([211, -2, 0])
        g.reset(); g.translate(c[0], c[1])
        g.rotate(Math.atan2(b.y - a.y, b.x - a.x))
        g.scale(Math.hypot(b.x - a.x, b.y - a.y) * 0.9, height * 0.105)
        var shade = g.createRadialGradient(0, 0, 0.15, 0, 0, 1)
        shade.addColorStop(0, "#ee02040a"); shade.addColorStop(0.7, "#c902040a"); shade.addColorStop(1, "#0002040a")
        g.fillStyle = shade; g.beginPath(); g.arc(0, 0, 1, 0, Math.PI * 2); g.fill()
      }
    }

    // The wet floor mirrors the car, blurred and fading away from the tyres.
    ShaderEffectSource { id: carImage; anchors.fill: car; sourceItem: car; visible: false }

    Item {
      id: floorFade
      anchors.fill: car
      visible: false
      layer.enabled: true
      // Fades over a fifth of the height, square to the contact line.
      readonly property real reach: car.height * 0.2 / Math.hypot(car.ground[1].x - car.ground[0].x, car.ground[1].y - car.ground[0].y)
      Shape {
        anchors.fill: parent
        ShapePath {
          strokeColor: "transparent"
          fillGradient: LinearGradient {
            x1: (car.ground[0].x + car.ground[1].x) / 2; y1: (car.ground[0].y + car.ground[1].y) / 2
            x2: x1 + (car.ground[1].y - car.ground[0].y) * floorFade.reach; y2: y1 - (car.ground[1].x - car.ground[0].x) * floorFade.reach
            GradientStop { position: 0; color: "#ffffffff" }
            GradientStop { position: 1; color: "#00ffffff" }
          }
          PathRectangle { width: floorFade.width; height: floorFade.height }
        }
      }
    }

    MultiEffect {
      anchors.fill: car
      source: carImage
      maskEnabled: true
      maskSource: floorFade
      maskSpreadAtMin: 1
      blurEnabled: true
      blur: 0.8
      blurMax: 64
      opacity: 0.14
      transform: [carMirror, carGrow, carSlide, carFraming, carLower]
      Matrix4x4 { id: carMirror; matrix: car.mirror }
    }

    // 3D line-art Sport quattro S1 E2 seen from the front-left quarter. Comets like the wheel's
    // logo trace every outline and leave the line behind them; then the car parks, and
    // drives off screen when the lock is released. Lines are GPU paths, and finished
    // outlines are rebuilt only when another completes, so a frame moves just the comets.
    Item {
      id: car

      property color lineColor: Color.lock.text
      // A fixed blue, so the comets read as trails against the lines: the theme accent can be
      // darker than the lines (#8d8d8d here), and the lines' own color hides the comets in them.
      property color glowColor: "#7fd4ff"
      property real clock: duration
      // Drive-off timeline, 0..1 over driveTime.
      property real drive: 0
      // Polylines per path: finished and tracing outlines by level (inside and far, fine,
      // panels, outline, beneath paint), and the comets' tail, body, head and the head's glow.
      property var lines: [[], [], [], [], []]
      property var tracing: [[], [], [], [], []]
      property var comets: [[], [], [], []]
      // Rally livery by tone (see carModel); the Shape below sets the order they're drawn in. Tones with an
      // ink width are stroked that wide rather than filled.
      readonly property var paint: [
        "#f2f2ee", "#f2f2ee", "#f6f6f3", "#e9eae8", "#f2f2ee",    // 0-4 bodywork: flank, sides and front, tops, upper sides, shadow
        "#26121a24", "#9fb3c3", "#1c1d1f", "#dcb865",               // 5-8 tinted glass, lamp lenses, rubber, polished rim lips
        "#1c2c5e", "#3aa3e0", "#d42a2a", "#141414", "#f2f2ee",    // 9-13 decals: navy, blue, red, black, white
        "#1c2c5e", "#f2f2ee", "#141414",                           // 14-16 lettering: navy, white, black
        "#d9dce0", "#1d1f23", "#d3dee7", "#ffffff", "#e8963a",    // 17-21 the spotlights' chrome rims, the black lamp panel and centre caps, lens tops, glints, indicators
        "#2e281c",                                                 // 22 the dark dish behind the mesh
        "#1d1f23", "#3a3e45", "#2c3d70", "#5b6069",               // 23-26 inside: seat backs, seats, seat panels, steering
        "#0b0c0e",                                                 // 27 window trim
        "#f2f2ee", "#caa652", "#caa652",                          // 28-30 rounded bumper (same pigment as flank 0), gold mesh spokes, hubs
        "#3a3e46",                                                 // 31 the dash's top
        "#1c2c5e",                                                 // 32 the C-pillar, over the decals
        "#080b11", "#141c29", null,                                // 33-35 near mirror rim and shell; spare slot
        "#1d1f23", "#141c29", "#080b11", null,                     // 36-39 far mirror mount, shell, rim; spare slot
        "#5b6069", "#5b6069",                                      // 40-41 the wipers' arms and blades, over their lines
        "#141518", "#2a2d33", "#212c52",                           // 42-44 inside, deeper in shadow: the far seat's back, face and panel
        "#c2c4c0", "#9c9e9a",                                      // 45-46 the cabin's shell, mid grey under the dark cage: far side (shaded, see cabin), bulkhead
        "#141518", "#2c2e33", "#c4262b", "#50535a",                // 47-50 the roll cage's far tubes, dark on the grey shell: shadow, body; harness straps; highlight
        "#141518", "#2c2e33", "#50535a",                           // 51-53 its near tubes, over the seats: shadow, body, highlight
        "#8a8c88", "#a07d8a96",                                    // 54-55 the parcel shelf; the far windows from inside, showing out
        "#38d8dee2",                                               // 56 the windscreen, catching the sky: lighter than the side glass
        "#c9cdd2", "#16171a", "#c3d0da", "#ffffff",              // 57-60 the headlamps' chrome bezels; the spotlights' cans and bar, lenses, glints
        "#161719",                                                // 61 full tyre volume behind the body and sidewall
        "#f6f6f3", "#f2f2ee", "#aeb0ad", "#141518", "#1d1f23",    // 62-66 the wing: plane, near and far fins, far and near carbon tips
        "#6a707c", null, "#1c2c5e", "#3aa3e0", "#d42a2a",         // 67-71 the tips' rims; spare slot; the wing's stripes
        "#f2f2ee", "#090c10", "#f2f2ee", "#f2f2ee",               // 72-75 intake lip, screen, inner return and painted outer cheek
        "#c79943"]                                                 // 76 mud flaps
      readonly property var ink: ({ 14: 2.2, 15: 1.6, 16: 2.2, 26: 2.6, 29: 1.4, 40: 1.8, 41: 1, 49: 5, 33: 0.6, 38: 0.6 })
      // Paint sweeps on once every outline has landed, never over a car still flying together. The
      // outlines settle with it: the silhouette into a thin light edge, panel lines into dark gaps.
      readonly property real painted: Math.min(1, Math.max(0, (clock - traced) / paintTime))
      readonly property color gapColor: "#15171a"
      // Screen polygons of the painted surfaces by tone.
      property var fills: paint.map(function() { return [] })
      // Paint floods on nose to tail behind a wavefront rather than fading up whole, so it arrives the
      // way the outlines did. span is the x the bodywork covers on screen, a unit out at each end so the
      // car is bare at 0 and wholly covered at 1; front is how far the paint has reached; coating is
      // whether it is still going on, and so still clipped; wavefront is where front cuts the surfaces.
      property var span: null
      readonly property real front: span ? Math.max(0, span[0] + (span[1] - span[0]) * painted) : 0
      readonly property bool coating: painted < 1
      property var wavefront: []
      // The cabin's far side, lit from the belt down to the floor's shadow, as screen points.
      property var cabin: [Qt.point(0, 0), Qt.point(0, 1)]
      // The near tyres' contact points, as screen points: the floor mirrors the car about the line through them.
      property var ground: [Qt.point(0, 1), Qt.point(1, 1)]
      readonly property matrix4x4 mirror: {
        var a = ground[0], k = (ground[1].y - a.y) / (ground[1].x - a.x)
        return Qt.matrix4x4(1, 0, 0, 0, 2 * k, -1, 0, 2 * (a.y - k * a.x), 0, 0, 1, 0, 0, 0, 0, 1)
      }
      property int finished: -1
      // Design units to screen, set by project(); the drive-off reuses it to pose the car.
      property var view: null
      property var focusHeights: Qt.point(1, 0)
      // Drive-off: its length in ms, wheel turn in radians, launch progress (0..1),
      // headlamp glow (0..1), the lamp outlines that glow, and the body's pose (pitch in
      // radians, shake), which the paint shader undoes.
      readonly property int driveTime: 1100
      property real rolled: 0
      property real launch: 0
      property real lamps: 0
      property var glowing: []
      property var pose: [0, 0]
      // Speed streaks trail from these: headlamps, taillamp, mirror, roof, chassis ends, tyres.
      readonly property var streakFrom: [[14, 63, -80], [14, 63, -59], [14, 63, 59], [14, 63, 80], [401, 85, -81], [167.4, 103, -100],
        [210, 130, -64], [300, 131, -64], [210, 130, 64], [1, 15, -88], [397, 16, -88], [100, -2, -88], [322, -2, -88]]
      readonly property var model: carModel()
      readonly property var parts: model.parts
      // The last outline lands at traced; the paint sweeps on over the paintTime after it, and the
      // draw-in runs for both.
      readonly property int traced: Math.ceil(parts.reduce(function(end, part) { return Math.max(end, part.end) }, 0))
      readonly property int paintTime: 600
      readonly property int duration: traced + paintTime
      // Matches the wheel's 2px comet ring at 1080p.
      readonly property real base: Math.max(1, height / 540)

      anchors.fill: parent
      // The nose points left and toward the camera: slide left, dip, and grow.
      transform: [
        Scale { id: carGrow; origin.x: car.width * 0.3; origin.y: car.height * 0.6; xScale: 1 + 0.3 * car.launch; yScale: 1 + 0.3 * car.launch },
        Translate { id: carSlide; x: -car.width * 1.2 * car.launch; y: car.height * 0.14 * car.launch },
        // Frame the car, shadow and reflection together, including the entire drive-off.
        Scale { id: carFraming; origin.x: car.width / 2; origin.y: car.height / 2; xScale: 0.89; yScale: 0.89 },
        Translate { id: carLower; x: car.width * 0.03; y: car.height * 0.04 }
      ]

      component Stroke: ShapePath {
        property alias paths: polylines.paths
        fillColor: "transparent"
        capStyle: ShapePath.RoundCap
        joinStyle: ShapePath.RoundJoin
        PathMultiline { id: polylines }
      }

      // A shape covering the car, holding one level of its outlines.
      component Ink: Shape {
        anchors.fill: parent
        preferredRendererType: Shape.CurveRenderer
      }

      // A shape holding paint, cut off at the wavefront so only what has been laid down shows.
      // Sliding the clip costs nothing, where reshaping every surface each frame would have to
      // retessellate the whole car. Once the paint is on, the clip lifts: the drive-off poses the
      // car past where it parked, and the span was measured there.
      component Coat: Shape {
        width: car.coating ? car.front : car.width
        height: car.height
        clip: car.coating
        preferredRendererType: Shape.CurveRenderer
      }

      component Fill: ShapePath {
        property alias paths: polygons.paths
        strokeColor: "transparent"
        fillRule: ShapePath.OddEvenFill
        PathMultiline { id: polygons }
      }
      component Cabin: Fill { fillColor: Qt.rgba(15/16, 0, 0, 1) }
      // A tone's surfaces in its paint, or stroked at its ink width (see paint).
      component Paint: Fill { property int tone; fillColor: car.paint[tone]; paths: car.fills[tone] }
      component Inked: Stroke { property int tone; strokeColor: car.paint[tone]; strokeWidth: car.base * car.ink[tone]; paths: car.fills[tone] }

      // Focus the complete car, including outlines, inside its framing and departure transforms.
      Item {
        anchors.fill: parent
        layer.enabled: true
        layer.smooth: true
        layer.effect: ShaderEffect {
          property var source
          property vector2d resolution: Qt.vector2d(car.width, car.height)
          property vector2d focusHeights: Qt.vector2d(car.focusHeights.x, car.focusHeights.y)
          property real amount: car.painted
          fragmentShader: root.focusShader
        }

      // Panel mask in car coordinates: R is the surface kind, G the top's height / 160 or, on black
      // plastic, whether it is a spotlight can.
      // It uses the same even-odd cutouts as the paint, so glass and wheel wells stay clear.
      Item {
        id: paintPanels
        anchors.fill: parent
        visible: false
        layer.enabled: true
        // The same clip as a Coat, but on an Item around the shape: inside a layer a shape does
        // not clip its own paths, and the mask has to stop where the paint does or the metal
        // would shade a panel the wavefront hasn't reached yet.
        Item {
          width: car.coating ? car.front : car.width
          height: car.height
          clip: car.coating
          Shape {
            width: car.width
            height: car.height
            // Discrete IDs must not blend at edges: intermediate IDs shade the wrong plane.
            preferredRendererType: Shape.GeometryRenderer
            Fill { fillColor: Qt.rgba(1/16, 176/200, 0, 1); paths: car.fills[64] }
            Fill { fillColor: Qt.rgba(12/16, 0.25, 1, 1); paths: car.fills[65] }
            Fill { fillColor: Qt.rgba(3/16, 1, 0, 1); paths: car.fills[62] }
            Fill { fillColor: Qt.rgba(1, 0.5, 0, 1); paths: car.fills[76] }
            Fill { fillColor: Qt.rgba(11/16, 0, 0, 1); paths: car.fills[61] }
            Fill { fillColor: Qt.rgba(1, 1, 0, 1); paths: car.fills[37] }
            Inked { tone: 38; strokeColor: "black" }
            // The cabin, one fill per tone: overlapping tones merged into one path would cancel out.
            Cabin { fillRule: ShapePath.WindingFill; paths: car.fills[45] }
            Cabin { paths: car.fills[54] }
            Cabin { paths: car.fills[46] }
            Cabin { fillRule: ShapePath.WindingFill; paths: car.fills[47] }
            Cabin { fillRule: ShapePath.WindingFill; paths: car.fills[48] }
            Cabin { fillRule: ShapePath.WindingFill; paths: car.fills[50] }
            Cabin { paths: car.fills[42] }
            Cabin { paths: car.fills[43] }
            Cabin { paths: car.fills[44] }
            Cabin { paths: car.fills[23] }
            Cabin { paths: car.fills[24] }
            Cabin { paths: car.fills[25] }
            Inked { tone: 49; strokeColor: Qt.rgba(15/16, 0, 0, 1) }
            Cabin { fillRule: ShapePath.WindingFill; paths: car.fills[51] }
            Cabin { fillRule: ShapePath.WindingFill; paths: car.fills[52] }
            Cabin { fillRule: ShapePath.WindingFill; paths: car.fills[53] }
            Inked { tone: 26; strokeColor: Qt.rgba(15/16, 0, 0, 1) }
            Cabin { fillRule: ShapePath.WindingFill; paths: car.fills[31] }
            Fill { strokeColor: fillColor; strokeWidth: car.base; fillColor: Qt.rgba(1/16, 0, 0, 1); paths: car.fills[0] }
            Fill { strokeColor: fillColor; strokeWidth: car.base; fillColor: Qt.rgba(2/16, 0, 0, 1); paths: car.fills[1] }
            Fill { strokeColor: fillColor; strokeWidth: car.base; fillColor: Qt.rgba(3/16, 85/160, 0, 1); paths: car.fills[2].slice(0, 1) }
            Fill { strokeColor: fillColor; strokeWidth: car.base; fillColor: Qt.rgba(3/16, 133/160, 0, 1); paths: car.fills[2].slice(1, 2) }
            Fill { strokeColor: fillColor; strokeWidth: car.base; fillColor: Qt.rgba(3/16, 101/160, 0, 1); paths: car.fills[2].slice(2, 3) }
            Fill { strokeColor: fillColor; strokeWidth: car.base; fillColor: Qt.rgba(3/16, 51/160, 0, 1); paths: car.fills[2].slice(3, 4) }
            Fill { strokeColor: fillColor; strokeWidth: car.base; fillColor: Qt.rgba(4/16, 0, 0, 1); paths: car.fills[3].slice(0, 2).concat(car.fills[3].slice(4)) }
            Fill { strokeColor: fillColor; strokeWidth: car.base; fillColor: Qt.rgba(6/16, 0, 0, 1); paths: car.fills[3].slice(2, 4) }
            Fill { strokeColor: fillColor; strokeWidth: car.base; fillColor: Qt.rgba(7/16, 0, 0, 1); paths: car.fills[28] }
            Fill { strokeColor: fillColor; strokeWidth: car.base; fillColor: Qt.rgba(5/16, 0, 0, 1); paths: car.fills[4] }
            Fill { fillColor: Qt.rgba(11/16, 0, 0, 1); fillRule: ShapePath.WindingFill; paths: car.fills[7] }
            Fill { fillColor: Qt.rgba(8/16, 0, 0, 1); paths: car.fills[8] }
            Fill { fillColor: "black"; paths: car.fills[22] }
            Inked { tone: 29; strokeColor: Qt.rgba(9/16, 0, 0, 1) }
            Fill { fillColor: Qt.rgba(10/16, 0, 0, 1); paths: car.fills[30] }
            Fill { fillColor: Qt.rgba(1, 0, 0, 1); paths: car.fills[34] }
            Inked { tone: 33; strokeColor: "black" }
            Fill { fillColor: "black"; paths: car.fills[18] }
            // The lamp panel is tone 18's last surface, after the centre caps and the mirror's arm.
            Fill { fillColor: Qt.rgba(12/16, 0, 0, 1); paths: car.fills[18].slice(-1) }
            Fill { fillColor: Qt.rgba(13/16, 0, 0, 1); paths: car.fills[6].concat(car.fills[21]) }
            Fill { fillColor: Qt.rgba(14/16, 0, 0, 1); paths: car.fills[57] }
            Fill { fillColor: Qt.rgba(12/16, 1, 0, 1); fillRule: ShapePath.WindingFill; paths: car.fills[58] }
            Fill { fillColor: Qt.rgba(14/16, 0, 0, 1); paths: car.fills[17] }
            Fill { fillColor: Qt.rgba(13/16, 0, 0, 1); paths: car.fills[59] }
            Fill { fillColor: "black"; paths: car.fills[60] }
            // The intake has green 0.4, mesh blue 1 and reveal blue 0.5; the wing's carbon tips green 0.25, the
            // far one blue 1. Mirrors/flaps use panel 16; the wing is a top shaded along its chord (green 1). Its
            // fins are sides standing at z = 200 green - 100, not the flank's -84.
            // One fill each: the intake's recess and rear wall overlap, and would cancel in one path.
            Fill { fillColor: Qt.rgba(12/16, 0.4, 0, 1); paths: car.fills[75] }
            Fill { fillColor: Qt.rgba(12/16, 0.4, 1, 1); paths: car.fills[73] }
            Fill { fillColor: Qt.rgba(12/16, 0.4, 0.5, 1); paths: car.fills[74] }
            Fill { fillColor: Qt.rgba(12/16, 0.4, 0.25, 1); paths: car.fills[72] }
            Fill { fillColor: Qt.rgba(1/16, 24/200, 0, 1); paths: car.fills[63] }
            Fill { fillColor: Qt.rgba(12/16, 0.25, 0, 1); paths: car.fills[66] }
          }
        }
      }

      // Shade the paint and its livery together, with the cabin, tyres and the nose's plastic, lamps
      // and chrome. Glass and outlines keep their own colours. The enclosing car also supplies the wet-floor
      // reflection.
      Item {
        anchors.fill: parent
        layer.enabled: true
        layer.smooth: true
        layer.effect: ShaderEffect {
          property var source
          property var paintMask: paintPanels
          property var environment: city
          property vector2d resolution: Qt.vector2d(car.width, car.height)
          property real pitch: car.pose[0]
          property real shake: car.pose[1]
          // Shading covers whatever the panel mask holds, which is only the paint laid down so far.
          property real amount: car.painted > 0 ? 1 : 0
          fragmentShader: root.paintShader
        }
        // Construction edges at the rear opening and rounded bumper sit under paint.
        // Only their exposed silhouettes keep ink once the surfaces are filled.
        Ink {
          Stroke { strokeColor: car.settle(0.85, car.gapColor, 0.45); strokeWidth: car.base * (1 - 0.2 * car.painted); paths: car.lines[4] }
          Stroke { strokeColor: car.settle(0.85, car.gapColor, 0.45); strokeWidth: car.base * (1 - 0.2 * car.painted); paths: car.tracing[4] }
        }
        Coat {
          Paint { tone: 64; strokeColor: Qt.alpha(car.gapColor, 0.6); strokeWidth: car.base * 0.7 }
          Paint { tone: 65; strokeColor: car.paint[67]; strokeWidth: car.base * 0.8 }
          Paint { tone: 62; strokeColor: Qt.alpha(car.gapColor, 0.6); strokeWidth: car.base * 0.7 }
          Paint { tone: 69 }
          Paint { tone: 70 }
          Paint { tone: 71 }
          Paint { tone: 76 }
          Paint { tone: 61 }
          // The far mirror, then the inside, then the window trim and tinted glass: the bodywork covers them but
          // for the windows.
          Paint { tone: 36 }
          Paint { tone: 37 }
          Inked { tone: 38 }
          // The cabin: the far windows, the far side lit from its windows and darkening down, the parcel shelf and
          // bulkhead, then the cage's far tubes, which merge where they overlap (winding).
          Paint { tone: 55 }
          Fill {
            // Solid cabin panels: odd-even curve tessellation drops triangles as the body pitches.
            fillRule: ShapePath.WindingFill
            paths: car.fills[45]
            fillGradient: LinearGradient {
              x1: car.cabin[0].x; y1: car.cabin[0].y; x2: car.cabin[1].x; y2: car.cabin[1].y
              GradientStop { position: 0; color: "#b0b2ae" }
              GradientStop { position: 1; color: "#5a5d5a" }
            }
          }
          Paint { tone: 54 }
          Paint { tone: 46 }
          Paint { tone: 47; fillRule: ShapePath.WindingFill }
          Paint { tone: 48; fillRule: ShapePath.WindingFill }
          Paint { tone: 50; fillRule: ShapePath.WindingFill }
          Paint { tone: 42 }
          Paint { tone: 43 }
          Paint { tone: 44 }
          Paint { tone: 23 }
          Paint { tone: 24 }
          Paint { tone: 25 }
          Inked { tone: 49 }
          Paint { tone: 51; fillRule: ShapePath.WindingFill }
          Paint { tone: 52; fillRule: ShapePath.WindingFill }
          Paint { tone: 53; fillRule: ShapePath.WindingFill }
          Inked { tone: 26 }
          Paint { tone: 31; fillRule: ShapePath.WindingFill }
          Paint { tone: 27 }
          Paint { tone: 5 }
          Paint { tone: 56 }
          Paint { tone: 0; strokeColor: fillColor; strokeWidth: car.base }
          Paint { tone: 1; strokeColor: fillColor; strokeWidth: car.base }
          Paint { tone: 2; strokeColor: fillColor; strokeWidth: car.base }
          Paint { tone: 3; strokeColor: fillColor; strokeWidth: car.base }
          Paint { tone: 28; strokeColor: fillColor; strokeWidth: car.base }
          Paint { tone: 4 }
          Paint { tone: 75 }
          Paint { tone: 72 }
          Paint { tone: 7; fillRule: ShapePath.WindingFill }
          Paint { tone: 8 }
          Paint { tone: 22 }
          Inked { tone: 29 }
          Paint { tone: 30 }
        }

        Ink {
          Stroke { strokeColor: car.settle(0.35, car.gapColor, 0.2); strokeWidth: car.base * 0.7; paths: car.lines[0] }
          Stroke { strokeColor: car.settle(0.85, car.gapColor, 0.45); strokeWidth: car.base * (1 - 0.2 * car.painted); paths: car.lines[2] }
          Stroke { strokeColor: car.settle(0.35, car.gapColor, 0.2); strokeWidth: car.base * 0.7; paths: car.tracing[0] }
          Stroke { strokeColor: car.settle(0.85, car.gapColor, 0.45); strokeWidth: car.base * (1 - 0.2 * car.painted); paths: car.tracing[2] }
        }

        Coat {
          Paint { tone: 9 }
          Paint { tone: 10 }
          Paint { tone: 11 }
          Paint { tone: 12 }
          Paint { tone: 13 }
          Paint { tone: 32 }
          Paint { tone: 18 }
          // The intake's painted lip stays under the livery.
          Paint { tone: 73 }
          Paint { tone: 74 }
          Paint { tone: 57 }
          Paint { tone: 34 }
          Inked { tone: 33 }
          Paint { tone: 6 }
          Paint { tone: 19 }
          Paint { tone: 20 }
          Paint { tone: 21 }
          Inked { tone: 14 }
          Inked { tone: 15 }
          Inked { tone: 16 }
        }

        Ink {
          Stroke { strokeColor: car.settle(0.6, car.gapColor, 0.3); strokeWidth: car.base * (0.8 - 0.1 * car.painted); paths: car.lines[1] }
        }
        // Only the near fin and its tip sit in front of the body. The top and far side
        // are drawn behind it, so the roof and hatch correctly hide them.
        Coat {
          Paint { tone: 63; strokeColor: Qt.alpha(car.gapColor, 0.6); strokeWidth: car.base * 0.7 }
          Paint { tone: 66; strokeColor: car.paint[67]; strokeWidth: car.base * 0.8 }
        }
        // The spotlights stand in front of everything on the nose, so they're painted over its fine lines (the
        // grille's slats would show through them), their rims edged dark in place of their own.
        Coat {
          Paint { tone: 58; fillRule: ShapePath.WindingFill }
          Paint { tone: 17; strokeColor: Qt.alpha(car.gapColor, 0.6); strokeWidth: car.base * 0.7 }
          Paint { tone: 59 }
          Paint { tone: 60 }
        }
      }

      Ink {
        Stroke { strokeColor: car.settle(1, car.lineColor, 0.35); strokeWidth: car.base * (1.5 - 0.8 * car.painted); paths: car.lines[3] }
      }
      // The wipers, painted over their own fine lines.
      Coat {
        Inked { tone: 40 }
        Inked { tone: 41 }
      }
      Ink {
        Stroke { strokeColor: car.settle(0.6, car.gapColor, 0.3); strokeWidth: car.base * (0.8 - 0.1 * car.painted); paths: car.tracing[1] }
        Stroke { strokeColor: car.settle(1, car.lineColor, 0.35); strokeWidth: car.base * (1.5 - 0.8 * car.painted); paths: car.tracing[3] }
        Stroke { strokeColor: Qt.alpha(car.glowColor, 0.3 * car.lamps); strokeWidth: car.base * 8; paths: car.glowing }
        Stroke { strokeColor: Qt.alpha(car.glowColor, car.lamps); strokeWidth: car.base * 1.8; paths: car.glowing }
        // The paint's lit edge, in the comets' own blue: the outlines were traced by light, and the
        // paint is laid down behind it the same way.
        Stroke { strokeColor: Qt.alpha(car.glowColor, 0.22); strokeWidth: car.base * 7; paths: car.wavefront }
        Stroke { strokeColor: Qt.alpha(car.glowColor, 0.85); strokeWidth: car.base * 1.6; paths: car.wavefront }
        Stroke { strokeColor: Qt.alpha(car.glowColor, 0.18); strokeWidth: car.base * 5; paths: car.comets[3] }
        Stroke { strokeColor: Qt.alpha(car.glowColor, 0.35); strokeWidth: car.base * 1.2; paths: car.comets[0] }
        Stroke { strokeColor: Qt.alpha(car.glowColor, 0.7); strokeWidth: car.base * 1.6; paths: car.comets[1] }
        Stroke { strokeColor: car.glowColor; strokeWidth: car.base * 2.2; paths: car.comets[2] }
      }

      }

      // The line color at alpha a, moved toward color to at alpha b as the paint comes in.
      function settle(a, to, b) {
        var c = lineColor, t = painted
        return Qt.rgba(c.r + (to.r - c.r) * t, c.g + (to.g - c.g) * t, c.b + (to.b - c.b) * t, a + (b - a) * t)
      }

      function carModel() {
        var list = [], i
        // Half-width: the doors 84 up to the shoulder (y 72), leaning in to the belt (y 90) and on to the roof.
        // Box flares stand 4 proud below the shoulder: the front one steps out over 2 units up to x 143;
        // the rear one swells from just behind the door (x 264) and is full by its arch's lip (x 282).
        function zAt(x, y) {
          var body = y <= 72 ? 84 : y <= 90 ? 84 - (y - 72) / 18 * 4 : 80 - Math.min(40, y - 90) / 40 * 18
          var k = Math.min(1, Math.max(0, (143 - x) / 2 + 0.5, (x - 264) / 18))
          var flare = body + 4 * k * k * (3 - 2 * k) * Math.min(1, Math.max(0, (72 - y) / 3))
          // The forward-facing inlet's outer cheek rejoins the arch at x=286.
          if (x >= 270 && x < 286 && y >= 26 && y <= 72) {
            var blend = Math.min(1, (y - 26) / 5, (72 - y) / 5)
            blend = blend * blend * (3 - 2 * blend)
            flare += (8 + (Math.max(31, Math.min(67, y)) - 31) / 6) * Math.pow((286 - x) / 16, 2) * blend
          }
          return flare
        }
        function lift(pts, s) { return pts.map(function(p) { return [p[0], p[1], s * zAt(p[0], p[1])] }) }
        // The nose is drawn 10 longer than the car's: every outline and surface is warped as it's added, the
        // front face (x 8 and ahead) moving back whole and the fender ahead of the front arch (x 8-58) closing
        // up, so from the arch back nothing moves. unwarp places a decal there undistorted.
        // Before that the bumper is shaped, after the S1's: below the lamp panel (y 53) it leans forward toward
        // the bottom, 0.35 a unit down to its foot (y 23), so its ledge is a bevel and its foot and chin jut; and
        // its near corner is rounded in plan, radius 8, easing out over the last 4 below the panel, so it wraps
        // round into the flank, its edge leaning with the face (a radius growing downward undid the lean there).
        // The far corner, seen edge-on, stays square: rounded, its bulge stood past the face's outline. The round
        // moves the face back onto it and the flank's front edge back to its end, but leaves the flank behind that.
        // level() stands a part upright on the lean: the spotlights.
        function slope(y) { return y >= 53 ? 0 : (Math.max(23, y) - 36) * 0.35 }
        function level(pts) { return pts.map(function(p) { return [p[0] - slope(p[1]), p[1], p[2]] }) }
        function faceAt(y) { return y <= 18 ? -9 : y <= 23 ? -9 + (y - 18) * 0.8 : y <= 49 ? -5 : -5 + (y - 49) * 2 / 3 }
        function shape(p) {
          var x = p[0], y = p[1]
          if (x >= 8 || y >= 53) return p
          var r = 8 * Math.min(1, (53 - y) / 4), d = Math.min(r, Math.max(0, -p[2] - 88 + r))
          if (d > 0) x = Math.max(x, faceAt(y) + r - Math.sqrt(r * r - d * d))
          return [x + slope(y), y, p[2]]
        }
        function warp(p) { p = shape(p); var x = p[0]; return [x <= 8 ? x + 10 : x < 58 ? 18 + (x - 8) * 0.8 : x, p[1], p[2]] }
        function unwarp(x) { return x <= 18 ? x - 10 : x < 58 ? 8 + (x - 18) / 0.8 : x }
        // Wheels are drawn at radius 30 and grown to 32 about their axle (at height 30), so the tyres fill
        // their arches as the real car's do.
        function grow(p, axle) { return [axle + (p[0] - axle) * 16 / 15, 30 + (p[1] - 30) * 16 / 15, p[2]] }
        // A flank line at height y, every 2 units, so it follows the flares.
        function along(y, x0, x1) {
          var pts = []
          for (var x = x0; x < x1; x += 2) pts.push([x, y])
          return pts.concat([[x1, y]])
        }
        // Catmull-Rom through the points, n steps a span, so a few points make a soft edge.
        function smooth(pts, n) {
          var out = [pts[0]]
          for (var i = 0; i < pts.length - 1; i++) {
            var a = pts[Math.max(0, i - 1)], b = pts[i], c = pts[i + 1], d = pts[Math.min(pts.length - 1, i + 2)]
            for (var j = 1; j <= n; j++) {
              var t = j / n
              out.push(b.map(function(_, k) {
                return b[k] + 0.5 * t * (c[k] - a[k] + t * (2 * a[k] - 5 * b[k] + 4 * c[k] - d[k] + t * (3 * b[k] - a[k] - 3 * c[k] + d[k])))
              }))
            }
          }
          return out
        }
        // Arc in the side plane z, from a0 to a1 degrees.
        function arc(cx, cy, r, a0, a1, n, z) {
          var pts = []
          for (var i = 0; i <= n; i++) { var a = (a0 + (a1 - a0) * i / n) * Math.PI / 180; pts.push([cx + r * Math.cos(a), cy + r * Math.sin(a), z]) }
          return pts
        }
        // Both edges of a wheel opening use the same two-degree grid. Independently
        // tessellated arcs left slivers where the body and its inner return meet.
        function arch(x, a0, a1, z) {
          var pts = [], step = a1 > a0 ? 2 : -2
          function at(a) { a *= Math.PI / 180; return [x + 36 * Math.cos(a), 30 + 36 * Math.sin(a), z] }
          pts.push(at(a0))
          for (var a = step > 0 ? Math.floor(a0 / 2) * 2 + 2 : Math.ceil(a0 / 2) * 2 - 2; (a1 - a) * step > 0; a += step) pts.push(at(a))
          pts.push(at(a1))
          return pts
        }
        // Exact meeting of the projected z=-88 opening and z=-80 inner edge.
        // Camera matches project(): yaw pi/6, pitch 0.2, distance 1400.
        function wallAngles(x) {
          var camera = [221 - 700 * Math.cos(0.2), 60 + 1400 * Math.sin(0.2), -1400 * Math.cos(Math.PI / 6) * Math.cos(0.2)]
          var k = (-80 - camera[2]) / (-88 - camera[2]), lo = 0, hi = Math.PI / 2, q
          for (var i = 0; i < 40; i++) {
            var a = (lo + hi) / 2
            q = [camera[0] + k * (x + 36 * Math.cos(a) - camera[0]), camera[1] + k * (30 + 36 * Math.sin(a) - camera[1])]
            if (Math.hypot(q[0] - x, q[1] - 30) > 36) lo = a
            else hi = a
          }
          return [Math.atan2(q[1] - 30, q[0] - x) * 180 / Math.PI, a * 180 / Math.PI]
        }
        function ring(cx, cy, r, n, z) { return arc(cx, cy, r, 0, 360, n, z) }
        // A point on a panel crowned by lift at the middle, and a line across the car along it.
        function crown(x, y, lift, z) { return [x, y + lift * (1 - Math.pow(z / zAt(x, y), 2)), z] }
        // A flat one (lift 0) runs denser near its ends, where the bumper's corners round off.
        function across(x, y, lift) {
          var ks = []
          for (var i = 0; i <= 12; i++) ks.push(i / 6 - 1)
          if (!lift) ks = [-1, -0.99, -0.97, -0.94, -0.9].concat(ks.slice(1, 12), [0.9, 0.94, 0.97, 0.99, 1])
          return ks.map(function(k) { return crown(x, y, lift, zAt(x, y) * k) })
        }
        // Where the flare lip around an axle meets height y, ahead (-1) or behind (1).
        function lip(axle, y, side) { return axle + side * Math.sqrt(1600 - (y - 30) * (y - 30)) }
        // Ten spokes zigzag from hub to rim; a second pass, offset by one tooth, crosses them.
        function mesh(x, pass) {
          var pts = []
          for (var k = 0; k <= 20; k++) {
            var a = (k + pass) / 20 * 2 * Math.PI, r = k % 2 ? 19.5 : 9
            pts.push([x + r * Math.cos(a), 30 + r * Math.sin(a), k % 2 ? -85 : -76])
          }
          return pts
        }
        // Rounded rectangle on a face plane x, corners of radius r.
        function rrect(x, y0, y1, za, zb, r) {
          var z0 = Math.min(za, zb), z1 = Math.max(za, zb), pts = []
          var corners = [[z1 - r, y1 - r, 0], [z0 + r, y1 - r, 90], [z0 + r, y0 + r, 180], [z1 - r, y0 + r, 270]]
          corners.forEach(function(c) {
            for (var j = 0; j <= 4; j++) { var a = (c[2] + j * 22.5) * Math.PI / 180; pts.push([x, c[1] + r * Math.sin(a), c[0] + r * Math.cos(a)]) }
          })
          return pts.concat([pts[0]])
        }
        // Circle on a face plane x.
        function disc(x, y, z, r) {
          var pts = []
          for (var j = 0; j <= 32; j++) { var a = j / 32 * 2 * Math.PI; pts.push([x, y + r * Math.sin(a), z + r * Math.cos(a)]) }
          return pts
        }
        // Six grille slats on one side, from the frame to the outer ring, as one serpentine that
        // steps along the frame and along the ring, so no step shows.
        function slats(side) {
          var pts = [], zc = side * 12.75
          function edge(y) { return [4, y, zc + side * Math.sqrt(36 - (y - 63) * (y - 63))] }
          for (var j = 0; j < 6; j++) {
            var y = 68 - j * 2
            if (j % 2) {
              for (var t = 1; t < 4; t++) pts.push(edge(y + 2 - t / 2))
              pts.push(edge(y), [4, y, side * 40])
            } else pts.push([4, y, side * 40], edge(y))
          }
          return pts
        }
        // Rounded rectangle on a side plane z.
        function plate(x0, x1, y0, y1, z, r) {
          return rrect(0, y0, y1, x0, x1, r).map(function(p) { return [p[2], p[1], z] })
        }
        // A closed convex outline in the side plane, moved in by d: the glass inside its frame.
        function inset(poly, d) {
          var n = poly.length - 1, area = 0, lines = [], out = []
          for (var i = 0; i < n; i++) area += poly[i][0] * poly[i + 1][1] - poly[i + 1][0] * poly[i][1]
          for (i = 0; i < n; i++) {
            var a = poly[i], b = poly[i + 1], k = (area > 0 ? d : -d) / Math.hypot(b[0] - a[0], b[1] - a[1])
            lines.push([a[0] - (b[1] - a[1]) * k, a[1] + (b[0] - a[0]) * k, b[0] - a[0], b[1] - a[1]])
          }
          for (i = 0; i < n; i++) {
            var p = lines[(i + n - 1) % n], q = lines[i], den = p[2] * q[3] - p[3] * q[2]
            var t = Math.abs(den) < 1e-9 ? 1 : ((q[0] - p[0]) * q[3] - (q[1] - p[1]) * q[2]) / den
            out.push([p[0] + p[2] * t, p[1] + p[3] * t])
          }
          return out.concat([out[0]])
        }
        // A point just above the windscreen, which rises 0.625 a unit from the cowl.
        function screen(x, z) { var p = crown(x, 90 + (x - 146) * 0.625, 2, z); p[1] += 0.6; return p }
        // Each outline is traced at a comet's pace: 900 units a second, never quicker than 300ms,
        // and drawn at a weight: 3 the body's outline, 2 its panels (the default), 1 fine detail.
        // They set off in the order they're added, one every pace ms, so the same handful is ever in
        // flight and the car builds at an even rate: sills, wheels, body, glass, then the cabin seen
        // through it. Timing each group from its own base instead let groups overlap, which stalled
        // the trace between them and then landed half the car at once.
        var pace = 22
        function add(pts, weight) {
          pts = pts.map(warp)
          var cum = [0]
          for (var i = 1; i < pts.length; i++) cum.push(cum[i - 1] + Math.hypot(pts[i][0] - pts[i - 1][0], pts[i][1] - pts[i - 1][1], pts[i][2] - pts[i - 1][2]))
          var len = cum[cum.length - 1], start = list.length * pace
          var part = { pts: pts, cum: cum, len: len, start: start, end: start + Math.max(300, len / 0.9), weight: weight === undefined ? 2 : weight }
          list.push(part)
          return part
        }

        // Per wheel: its axle, and the angles this camera sees, worked out by projection: the tread's
        // inner edge under the arch, from where the arch hides it to the tyre's silhouette; and the
        // arch's rolled lip turning in 8 to its inner wall, seen in the arch's rear half up to wall[0], where its edge passes behind the opening's, at wall[1].
        var wheels = [{ x: 100, tread: [224, 238.7], wall: wallAngles(100) },
          { x: 322, tread: [225, 246.6], wall: wallAngles(322) }]
        // Flares' bottom edges with round arch openings, the front flare's rear edge, and the rocker
        // set in under the doors, from where it clears that edge on screen (x 147.5) to its step out
        // to the rear flare; then the wheels, then the flare lips around them.
        add([[-9, 15, -88]].concat(arch(100, 202.9, -22.9, -88), [[142, 16, -88]]), 3)
        add([[284.5, 16, -88]].concat(arch(322, 202.9, -22.9, -88), [[397, 16, -88]]), 3).underPaint = true
        add(lift([[142, 16], [142, 69], [142, 72]], -1), 1)
        add([[147.5, 16, -78], [282.5, 16, -78], [284.5, 16, -88]], 3)
        for (var w = 0; w < 2; w++) {
          var x = wheels[w].x
          // Tyre, rim lip, BBS cross-spoke mesh dished in to the hub, hub, centre cap and badge.
          var wheel = [
            ring(x, 30, 30, 72, -84), ring(x, 30, 22, 60, -86), ring(x, 30, 19.5, 60, -85),
            mesh(x, 0), mesh(x, 1),
            ring(x, 30, 9, 36, -76), ring(x, 30, 5.5, 24, -77), ring(x, 30, 3, 16, -78)
          ]
          // Wheel parts carry their axle: they turn, and don't pitch with the body. Tyre outline, rim lip panel, the rest fine.
          for (var k = 0; k < wheel.length; k++) add(wheel[k].map(function(p) { return grow(p, x) }), [3, 2, 1][Math.min(k, 2)]).axle = x
          // The tread stays where the camera sees it: it follows the wheel but doesn't turn. Its inner
          // edge runs on into its silhouette line, back to the tyre face. The rim's barrel gets no line:
          // seen through the mesh, it read as the tyre's far side showing through the rim.
          var tread = wheels[w].tread
          var part = add(arc(x, 30, 30, tread[0], tread[1], 10, -64).concat([arc(x, 30, 30, tread[1], tread[1], 1, -84)[0]])
            .map(function(p) { return grow(p, x) }), 2)
          part.axle = x
          part.still = true
          // The flare rolls over into the lip (fine), whose inner edge shows in the arch.
          add(arc(x, 30, 40, 200.5, -20.5, 28, -88), 1)
          add(arch(x, -22.9, wheels[w].wall[0], -80))
        }

        // Body shell: the near side's whole outline; of the far side, the front corner and
        // the top edge over hood, glass and deck. Hood, glass and roof edges are soft curves.
        var face = [[-9, 15], [-9, 18], [-5, 23], [-5, 49], [-3, 52], [4, 53], [4, 69], [4, 72], [8, 76]]
        var hood = smooth([[8, 76], [80, 85], [146, 90]], 8)
        var roof = smooth([[146, 90], [178, 110], [210, 130]], 4).concat(smooth([[210, 130], [255, 134], [300, 131]], 6).slice(1))
        var glass = roof.concat(smooth([[300, 131], [333, 117], [360, 97]], 8).slice(1))
        // The deck runs flat to the tail, as the S1's: its wing's fins stand on the corners a Quattro's lip had.
        var deck = [[360, 97], [393, 98], [403, 98]]
        var tail = [[403, 90], [403, 76], [403, 72], [403, 69], [403, 50], [405, 46], [405, 22], [397, 16]]
        add(lift(face.slice(0, 6), -1), 3).underPaint = true
        add(lift(face.slice(5).concat(hood.slice(1), smooth([[146, 90], [262, 92], [360, 97]], 6).slice(1), deck.slice(1), tail), -1), 3)
        add(lift(glass, -1), 3)
        add(lift(face, 1), 3)
        // The rear glass faces away from the camera: the far C-pillar, the glass's base and the
        // far deck edge are hidden behind the near C-pillar.
        add(lift(hood.concat(roof.slice(1)), 1), 3)
        var cross = [across(8, 76, 2), across(146, 90, 2), across(210, 130, 3), across(300, 131, 3),
          across(403, 98, 1), across(4, 72, 0), across(4, 53, 0), across(-3, 52, 0), across(-5, 23, 0), across(-9, 18, 0), across(-9, 15, 0)]
        for (i = 0; i < cross.length; i++) add(cross[i])

        // Flank: bumper tops, sill, the door (one outline: down from its window frame's ends, round the corners
        // and along just above the sill), glass in its frames, hood creases.
        // The door's window frame runs up beside the A-pillar; the glass starts behind the mirror's panel.
        var doorFrame = [[154, 93], [206, 126], [262, 128], [262, 93], [154, 93]]
        var doorGlass = [[200, 93], [200, 122.2], [206, 126], [262, 128], [262, 93], [200, 93]]
        var quarterGlass = [[268, 93], [268, 128], [296, 128], [334, 96], [268, 93]]
        // The glass the interior shows through: side windows inside their frames, and the windscreen's.
        var panes = [lift(inset(doorGlass, 4), -1), lift(inset(quarterGlass, 4), -1)]
        var flank = [
          lift([[-3, 52], [lip(100, 52, -1), 52]], -1), lift([[lip(322, 50, 1), 50], [403, 50]], -1),
          lift(along(24, 142, lip(322, 24, -1)), -1),
          lift([[154, 93], [154, 28.5], [156.5, 26], [259.5, 26], [262, 28.5], [262, 93]], -1),
          lift(doorFrame, -1), panes[0], lift(quarterGlass, -1), panes[1],
          [crown(8, 76, 2, -50), crown(146, 90, 2, -50)], [crown(8, 76, 2, 50), crown(146, 90, 2, 50)]
        ]
        // The hood creases, last, are fine.
        for (i = 0; i < flank.length; i++) add(flank[i], i < flank.length - 2 ? 2 : 1)

        // Front, on the lamp panel (x 4) and the bumper face (x -5). Per side: one big headlamp, the S1's, its
        // chrome bezel round the lens; an indicator low on the bumper's corner; grille slats. Then the grille, the
        // rings, and six spotlights, rally style, each a rim round its lens: two big ones before the grille, four
        // on a bar over the bumper (face x, height, across, radius).
        var front = [], bezels = []
        var low = -8 + slope(46.5), spots = [[-3, 67.5, -33, 9], [-3, 67.5, 33, 9], [low, 46.5, -47, 8.5], [low, 46.5, -19, 8.5], [low, 46.5, 19, 8.5], [low, 46.5, 47, 8.5]]
        for (var side = -1; side <= 1; side += 2) {
          bezels.push(rrect(4, 57, 69, side * 44, side * 86, 1.5))
          front.push(bezels[bezels.length - 1], rrect(4, 58.5, 67.5, side * 46, side * 84, 2.5), rrect(-5, 38.5, 45.5, side * 70, side * 84, 1), slats(side))
        }
        var grille = rrect(4, 56, 70, -40, 40, 1.5)
        front.push(grille, disc(4, 63, -12.75, 6), disc(4, 63, -4.25, 6), disc(4, 63, 4.25, 6), disc(4, 63, 12.75, 6))
        spots.forEach(function(l) { front.push(level(disc(l[0], l[1], l[2], l[3])), level(disc(l[0], l[1], l[2], l[3] - 1.3))) })
        // Headlamp bezels glow when the engine starts. They and the grille are panels, the rest fine.
        for (i = 0; i < front.length; i++) add(front[i], bezels.indexOf(front[i]) >= 0 || front[i] === grille ? 2 : 1).lamp = bezels.indexOf(front[i]) >= 0

        // Details: the windscreen's frame; the mirror at the door glass's front corner, a rounded housing on a short arm
        // from the belt (the outline a light rim, like the silhouette, so it shows on the black trim); then, fine, two parked
        // wipers and door handle; fuel flap and taillamp (it glows too).
        var windscreen = []
        for (i = 0; i <= 12; i++) windscreen.push(crown(150.5, 92.8, 2, 72 * (i / 6 - 1)))
        for (i = 0; i <= 12; i++) windscreen.push(crown(206, 127.5, 3, 58 * (1 - i / 6)))
        panes.push(windscreen.concat([windscreen[0]]))
        // A rounded, flattened housing with a broad rear rim; no pointed cone apex.
        function mirrorRing(x, side) {
          var radius = Math.pow(Math.max(0, 1 - Math.pow(Math.abs((x - 168) / 10), 3)), 1 / 3), points = []
          function roundedAxis(v) { return Math.sign(v) * Math.pow(Math.abs(v), 2 / 3) }
          for (var j = 0; j <= 32; j++) {
            var a = j / 16 * Math.PI
            points.push([x, 103 + 5 * radius * roundedAxis(Math.sin(a)), side * (94 + 8 * radius * roundedAxis(Math.cos(a)))])
          }
          return points
        }
        var mirrors = [-1, 1].map(function(side) {
          var shell = []
          ;[158, 158.2, 158.7, 159.5, 161, 163, 166, 168, 170, 172, 174].forEach(function(x) { shell = shell.concat(mirrorRing(x, side)) })
          var rim = mirrorRing(174, side)
          return { shell: shell, rim: rim.slice(24).concat(rim.slice(1, 9)) }
        })
        var mirrorArms = [-1, 1].map(function(side) {
          return [[163, 93, 80], [170, 93, 80], [170, 99, 94], [166, 99, 94]].map(function(p) { return [p[0], p[1], side * p[2]] })
        })
        // A parked wiper, from its pivot at z toward the far side: the arm climbs gently from the foot of the glass
        // to the middle of the blade, which lies along it, 44 long.
        function wiper(z) {
          var arm = [], blade = []
          for (var i = 0; i <= 4; i++) { arm.push(screen(152.5 + i * 0.375, z + i * 10)); blade.push(screen(154, z + 18 + i * 11)) }
          return { arm: arm, blade: blade, line: blade.concat([blade[3]], flip(arm)) }
        }
        var wipers = [wiper(-50), wiper(0)]
        // The S1's wing (painted with the other surfaces), kept compact: a thin symmetric NACA section, 2 thick on a
        // 24 chord, pitched 1.5 up to its trailing edge just past the tail. wingAt gives its upper (1) or lower (-1)
        // surface at chord fraction c. From above, the plane shows along its top.
        function wingAt(c, s, z) {
          var f = 0.2969 * Math.sqrt(c) - 0.126 * c - 0.3516 * c * c + 0.2843 * c * c * c - 0.1036 * c * c * c * c
          return [384 + 24 * c, 120 + 1.5 * c + s * 10 * f, z]
        }
        var chord = [0, 0.004, 0.012, 0.03, 0.06, 0.1, 0.16, 0.24, 0.34, 0.46, 0.6, 0.75, 0.88, 1]
        function wingEdge(z) { return [0.06, 0.03, 0.012, 0.004].map(function(c) { return wingAt(c, -1, z) }).concat(chord.map(function(c) { return wingAt(c, 1, z) })) }
        var wing = wingEdge(-76).concat(flip(wingEdge(76)), [wingAt(0.06, -1, -76)])
        // It stands on the S1's white fins, flush with the deck's edges and closing over the plane's ends: from a
        // short foot on the deck, their rear edges rise from the tail's top corner and their front edges sweep
        // forward to the plane's nose, so they stay no bigger than the plane. A carbon tip on each sweeps up from
        // the nose to stand above the trailing edge.
        var fin = [[393, 98], [403, 98], [409.5, 122.1]]
          .concat(flip(chord).map(function(c) { var p = wingAt(c, 1, 0); return [p[0], p[1] + 0.3] }), [[383, 119.7], [393, 98]])
        var blade = smooth([[383, 120.4], [394, 123.6], [404, 126.6], [409, 129.6], [411.8, 129.2], [411.4, 125.6], [409.5, 122.1]], 3)
          .concat(fin.slice(3, -2), [[383, 120.4]])
        function atZ(pts, z) { return pts.map(function(p) { return [p[0], p[1], z] }) }
        // Painted edges belong to the solids; tracing behind the roof must disappear under its paint.
        add(wing, 3).underPaint = true
        add(atZ(fin, -76), 3).underPaint = true
        add(atZ(blade, -77)).underPaint = true
        var details = [
          panes[2],
          mirrors[0].rim, mirrors[1].rim,
          mirrorArms[0].concat([mirrorArms[0][0]]),
          wipers[0].line, wipers[1].line,
          plate(242, 256, 80, 84.5, -81, 2),
          plate(360, 372, 79, 89, -81, 2),
          lift([[403, 78], [387, 78], [387, 92], [403, 92]], -1)
        ]
        for (i = 0; i < details.length; i++) {
          var detail = add(details[i], i === 1 || i === 2 ? 3 : i < 4 || i > 6 ? 2 : 1)
          detail.lamp = i === details.length - 1
        }

        // Painted surfaces by tone (see paint). A tone fills even-odd, so an outline inside another is a hole:
        // windows and grille; the wheel wells have dark backing. Rubber and the dash fill by winding
        // instead, so a tread and its tyre wall merge (the rim's hole runs backwards). Surfaces on a wheel
        // carry its axle and turn with it, but for those that are still, like the treads.
        var surfaces = []
        function surface(tone, pts, axle, still) { surfaces.push({ tone: tone, pts: pts.map(function(p) { return warp(axle === undefined ? p : grow(p, axle)) }), axle: axle, still: still }) }
        function solid(tone, pts, axle, still) { surface(tone, pts, axle, still); surfaces[surfaces.length - 1].hull = true }
        function flip(pts) { return pts.slice().reverse() }

        // A seat back around centre c, leaning back 1 in 4 from y 60 to its top: front outline with
        // bolsters, centre panel, and the back's top and near edges, 5 behind, for depth; then a
        // headrest block on two posts; painted in tones for back, face and panel. Each line comes with
        // the solid it outlines, if any.
        function seat(x0, c, top, tones) {
          function at(z, y, back) { return [x0 + (y - 60) * 0.25 + back, y, c + z * 1.35] }
          function curve(pts, back) { return smooth(pts.map(function(p) { return at(p[0], p[1], back) }), 3) }
          var outline = [[-16, 62], [-17, top - 13], [-15, top - 2], [-10, top + 1], [10, top + 1], [15, top - 2], [17, top - 13], [16, 62]]
          var panel = curve([[-10, 64], [-11, top - 12], [-8, top - 5], [8, top - 5], [11, top - 12], [10, 64]], 0)
          var out = [[curve(outline, 0), "back"], [panel], [curve(outline.slice(0, 5).reverse(), 5), "back"], [[at(10, top + 1, 0), at(10, top + 1, 5)]]]
          surface(tones[0], curve(outline, 5))
          surface(tones[1], curve(outline, 0))
          surface(tones[2], panel)
          // The headrest's back shows its top and near side: from the far top corner round to the near bottom.
          var x = at(0, top + 4, 2)[0], front = rrect(x, top + 4, top + 12, c - 11, c + 11, 3)
          var behind = front.map(function(p) { return [p[0] + 3.5, p[1], p[2]] }), back = behind.slice(4, 11)
          surface(tones[0], behind)
          surface(tones[1], front)
          return out.concat([[front, "head"], [back, "head"], [[front[4], back[0]]], [[front[10], back[6]]],
            [[at(-4, top + 1, 4), [x, top + 4, c - 5.4]]], [[at(4, top + 1, 4), [x, top + 4, c + 5.4]]]])
        }
        // Inside, shown only through the panes: dashboard and instrument hood, steering wheel with
        // its hub and spokes, rear-view mirror, and the far side's window frames.
        function wheelAt(a, r) { return [188 + r * Math.sin(a) * 0.48, 95 + r * Math.sin(a) * 0.88, -38 + r * Math.cos(a)] }
        var steering = [], hub = []
        for (i = 0; i <= 36; i++) { steering.push(wheelAt(i / 36 * 2 * Math.PI, 9)); hub.push(wheelAt(i / 36 * 2 * Math.PI, 2.5)) }
        var inside = [
          smooth([[176, 95, -76], [183, 97.5, -40], [183, 97.5, 40], [176, 95, 76]], 8),
          smooth([[181, 97, -54], [184, 103, -38], [181, 97, -22]], 6),
          steering, hub, [wheelAt(0, 2.5), wheelAt(0, 9)], [wheelAt(Math.PI, 2.5), wheelAt(Math.PI, 9)], [wheelAt(-Math.PI / 2, 2.5), wheelAt(-Math.PI / 2, 9)],
          rrect(200, 118, 124, -10, 10, 2), [[200, 124, 0], crown(206, 127.5, 3, 0)],
          lift(doorFrame, 1), lift(quarterGlass, 1)
        ]
        // The dash's own lines, the first two, belong to its solid (see project), so it doesn't hide them.
        for (i = 0; i < inside.length; i++) {
          var piece = add(inside[i])
          piece.inside = true
          if (i < 2) piece.group = "dash"
        }
        // Painted, the steering wheel's rim, thick, then the dash's top from the windscreen's foot to its edge,
        // with the instrument binnacle (reversed, so the two merge): drawn over the seats and the wheel's lower
        // half, which are behind and below it.
        var dash = []
        for (i = 0; i <= 12; i++) dash.push(crown(152, 93.8, 2, 72 * (i / 6 - 1)))
        surface(26, steering)
        surface(31, dash.concat(flip(inside[0])))
        surface(31, flip(inside[1]))
        // The front seats; a race car has none behind. The far one is deeper in shadow, darker, and painted first.
        // Each seat's back and headrest are solid: their outlines hide the inside lines behind them, other than
        // the seat's own.
        var seats = [[238, -40, 106, [23, 24, 25]], [238, 40, 106, [42, 43, 44]]]
        // Behind and around them, a stripped rally cabin after a Sport quattro S1, its shell mid grey. The far
        // side from inside: below the belt, the sail, B-pillar and C-pillar trim (shaded from the belt down), and
        // the windows, showing out; the parcel shelf, and the bulkhead sloping from behind the seats up to it.
        function shell(x, y, s) { return [x, y, s * zAt(x, y)] }
        function inner(x, y, s) { return [x, y, s * (zAt(x, y) - 7)] }
        surface(55, lift(inset(doorGlass, 2.5), 1))
        surface(55, lift(inset(quarterGlass, 2.5), 1))
        surface(45, lift([[150, 50], [150, 93], [268, 93], [334, 96], [334, 50]], 1))
        surface(45, lift([[154, 93], [206, 126], [200, 122.2], [200, 93]], 1))
        surface(45, lift([[262, 93], [262, 128], [268, 128], [268, 93]], 1))
        surface(45, lift([[296, 128], [334, 96], [360, 97], [333, 117], [300, 131]], 1))
        surface(54, [shell(334, 96, -1), shell(360, 97, -1), shell(360, 97, 1), shell(334, 96, 1)])
        surface(46, [shell(270, 45, -1), shell(334, 96, -1), shell(334, 96, 1), shell(270, 45, 1)])
        // The roll cage hugs the shell, as the S1's does, so it reads as a second frame just inside the windows.
        // Per side: the front hoop's leg up the A-pillar, 5 in from the windscreen's edge, and on along the roof's
        // edge; two door bars with a gusset; the main hoop's leg just ahead of the B-pillar, 7 in from the body
        // and leaning in with it; a stay back to the rear. Across: the front hoop's top, tight under the
        // windscreen's header; the main hoop's top, following the roof's crown; a harness bar and a lower bar.
        function tubes(s) {
          var corner = inner(256, 126, s)
          return [
            [inner(152, 40, s), [156, 92, s * 67], [206, 124, s * 55], corner],
            [inner(154, 62, s), inner(256, 62, s)], [inner(154, 80, s), inner(256, 80, s)], [inner(206, 62, s), inner(206, 80, s)],
            [inner(256, 40, s), inner(256, 93, s), corner],
            [corner, [324, 88, s * 58]]
          ]
        }
        // A tube 4.5 across: per segment, a band facing the camera (square to the segment and the view), as its
        // shadow side, its lit body toward the sky, and a highlight; a disc at each bend. Bands are turned to wind
        // one way on screen, so a tone's overlaps merge.
        var depth = [0.49, -0.199, 0.849], up = [0.0993, 0.98, 0.172], rightward = [0.866, 0, -0.5]
        function vcross(a, b) { return [a[1] * b[2] - a[2] * b[1], a[2] * b[0] - a[0] * b[2], a[0] * b[1] - a[1] * b[0]] }
        function vdot(a, b) { return a[0] * b[0] + a[1] * b[1] + a[2] * b[2] }
        function move(p, v, k) { return [p[0] + v[0] * k, p[1] + v[1] * k, p[2] + v[2] * k] }
        var facing = vdot(vcross(rightward, up), depth) > 0
        function tube(pts, tones) {
          for (var i = 0; i < pts.length - 1; i++) {
            var a = pts[i], b = pts[i + 1], t = [b[0] - a[0], b[1] - a[1], b[2] - a[2]], o = vcross(t, depth)
            var k = (vdot(o, up) < 0 ? -2.25 : 2.25) / Math.hypot(o[0], o[1], o[2])
            o = o.map(function(v) { return v * k })
            var turn = (vdot(vcross(t, o), depth) > 0) !== facing
            ;[[-1, 1], [-0.15, 1], [0.35, 0.7]].forEach(function(w, n) {
              var q = [move(a, o, w[0]), move(b, o, w[0]), move(b, o, w[1]), move(a, o, w[1])]
              surface(tones[n], turn ? flip(q) : q)
            })
            // Only at a bend: on a smooth curve discs bead the tube.
            if (i === 0) continue
            var u = [a[0] - pts[i - 1][0], a[1] - pts[i - 1][1], a[2] - pts[i - 1][2]]
            if (vdot(u, t) > 0.97 * Math.hypot(u[0], u[1], u[2]) * Math.hypot(t[0], t[1], t[2])) continue
            ;[[0, 2.25], [0.96, 1.29]].forEach(function(d, n) {
              var ring = []
              for (var j = 0; j < 16; j++) ring.push(move(move(move(a, up, d[0]), rightward, d[1] * Math.cos(j * Math.PI / 8)), up, d[1] * Math.sin(j * Math.PI / 8)))
              surface(tones[n], ring)
            })
          }
        }
        tubes(1).concat([[[206, 124, -55], [206, 126.5, 0], [206, 124, 55]],
          [inner(256, 126, -1), [256, 129.5, -46], [256, 131, 0], [256, 129.5, 46], inner(256, 126, 1)],
          [inner(256, 104, -1), inner(256, 104, 1)], [inner(256, 84, -1), inner(256, 84, 1)]]).forEach(function(pts) { tube(pts, [47, 48, 50]) })
        tubes(-1).forEach(function(pts) { tube(pts, [51, 52, 53]) })
        // The driver's harness: two red straps over the seat's top and down its front, closing in.
        ;[-8, 8].forEach(function(d) { surface(49, [[251, 108, -40 + d], [249.75, 107.5, -40 + d], [242.5, 78, -40 + d * 0.5]]) })
        seats.forEach(function(spec, n) {
          seat(spec[0], spec[1], spec[2], spec[3]).forEach(function(line) {
            var part = add(line[0])
            part.inside = true
            part.group = n
            if (line[1]) part.cover = n + line[1]
          })
        })

        surface(0, lift([[4, 72]].concat(tail.slice(1)), -1).concat(flip(arch(322, 202.9, -22.9, -88)), [[284.5, 16, -88]],
          flip(lift(along(24, 142, lip(322, 24, -1)), -1)), [[142, 16, -88]], flip(arch(100, 202.9, -22.9, -88)), lift(face.slice(0, 7), -1)))
        surface(7, lift(along(24, 142, 282.5), -1).concat([[284.5, 16, -88], [282.5, 16, -78], [147.5, 16, -78]]))
        // Above the shoulder, leaning in to the sky, lit like the highlights: fender tops, flanks and pillars
        // around the window frames.
        surface(3, lift([[4, 72]].concat(hood, glass.slice(1), deck.slice(1), tail.slice(0, 2),
          [[403, 72]], flip(along(72, 4, 403))), -1))
        // The side windows' opening, B-pillar included: the S1's frames and B-pillar are black.
        var windows = lift([[154, 93], [206, 126], [262, 128], [296, 128], [334, 96], [268, 93], [154, 93]], -1)
        surface(3, windows)
        surface(5, panes[0])
        surface(5, panes[1])
        surface(56, panes[2])
        // Round the windscreen, facing forward, one ring in body colour: the cowl, both A-pillars and the roof's
        // front edge; inside it a thin black seal round the glass.
        var seal = []
        for (i = 0; i <= 12; i++) seal.push(crown(149.3, 92.06, 2, 74 * (i / 6 - 1)))
        for (i = 0; i <= 12; i++) seal.push(crown(207.2, 128.25, 3, 60 * (1 - i / 6)))
        seal.push(seal[0])
        surface(3, across(146, 90, 2).concat(flip(across(210, 130, 3))))
        surface(3, seal)
        surface(27, seal)
        surface(27, panes[2])
        // The C-pillar behind the quarter glass, in the livery's navy, painted over the decals so it hides
        // the far deck stripe where that runs behind it.
        surface(32, lift([[296, 128]].concat(glass.slice(20), [[334, 96]]), -1))
        // Black trim round the side windows: each frame with its glass cut out.
        ;[windows, panes[0], panes[1]].forEach(function(pts) { surface(27, pts) })
        surface(2, lift(hood, -1).concat(across(146, 90, 2), flip(lift(hood, 1)), flip(across(8, 76, 2))))
        surface(2, lift(roof.slice(8), -1).concat(across(300, 131, 3), flip(lift(roof.slice(8), 1)), flip(across(210, 130, 3))))
        // Behind the roof the rear glass faces away and the roof's crowned end hides it, so what shows is
        // the deck: from the roof's near corner to the tail's far top corner, across the tail and back
        // along the near side. The near C-pillar, painted later, covers the far corner.
        surface(2, flip(across(403, 98, 1)).concat(flip(lift(deck.slice(0, 2), -1)), flip(lift(glass.slice(20), -1)).slice(1)))
        // The front as two faces, each one outline so no edge is shared within a fill (the GPU renderer
        // leaves gaps and slivers along shared edges): lamp panel and hood lip round the grille; chin and
        // bumper face. Between them the bumper's ledge.
        var lip72 = across(4, 72, 0), chin18 = across(-9, 18, 0), face23 = across(-5, 23, 0)
        var nose = across(4, 53, 0).concat([[4, 69, 88], lip72[lip72.length - 1]], flip(across(8, 76, 2)), [lip72[0], [4, 69, -88]])
        surface(1, nose)
        surface(1, grille)
        // The rounded bumper shares the flank's pigment; the shader supplies its lighting.
        surface(28, across(-9, 15, 0).concat([chin18[chin18.length - 1], face23[face23.length - 1]], flip(across(-5, 49, 0)), [face23[0], chin18[0]]))
        surface(2, across(-5, 49, 0).concat(flip(across(4, 53, 0))))
        // Light catches the flares' tops, the rear one's fading out as it nears the door.
        surface(3, lift(along(69, 4, 142).concat(flip(along(72, 4, 142))), -1))
        surface(3, lift(along(69, 286, 403).concat(flip(along(72, 286, 403))), -1))
        // The lips' inner walls; tyre walls round the rims, and the treads where they show.
        wheels.forEach(function(wheel) {
          surface(27, arch(wheel.x, -22.9, 202.9, -80))
          surface(4, arch(wheel.x, -22.9, wheel.wall[1], -88).concat(flip(arch(wheel.x, -22.9, wheel.wall[0], -80))))
          surface(7, ring(wheel.x, 30, 30, 72, -84), wheel.x)
          surface(7, flip(ring(wheel.x, 30, 22, 60, -86)), wheel.x)
          // Matte rubber surrounds the gold rim lip, mesh spokes, hub and dark centre cap.
          surface(8, ring(wheel.x, 30, 22, 60, -86), wheel.x)
          surface(22, ring(wheel.x, 30, 19.5, 60, -85), wheel.x)
          surface(29, mesh(wheel.x, 0), wheel.x)
          surface(29, mesh(wheel.x, 1), wheel.x)
          surface(30, ring(wheel.x, 30, 9, 36, -76), wheel.x)
          surface(18, ring(wheel.x, 30, 5.5, 24, -77), wheel.x)
          // A complete cylinder behind the sidewall. Project both ends as one convex solid;
          // the body occludes it naturally, including when the suspension lifts on launch.
          solid(61, ring(wheel.x, 30, 30, 144, -84).concat(ring(wheel.x, 30, 30, 144, -64)), wheel.x, true)
          // A thin rubber mud flap hanging from inside the arch behind the near tyre, its lower corners rounded,
          // bending back slightly at the foot and shaded continuously up under the arch.
          var flap = wheel.x + 37
          surface(76, rrect(flap, 1, 24, -88, -64, 2).map(function(p) { return [p[0] + 2 * Math.pow(Math.max(0, 16 - p[1]) / 13, 2), p[1], p[2]] }))
        })
        // Mirror shells use one pigment and a rounded-box surface normal. The far one is painted before the
        // cabin and body, which hide its inner side. Then the wipers and aluminium fuel cap.
        ;[[18, 34, 33], [36, 37, 38]].forEach(function(tones, k) {
          surface(tones[0], mirrorArms[k])
          solid(tones[1], mirrors[k].shell)
          surface(tones[2], mirrors[k].rim)
        })
        wipers.forEach(function(w) { surface(40, w.arm); surface(41, w.blade) })
        surface(1, plate(360, 372, 79, 89, -81, 2))
        surface(19, arc(366, 84, 3.2, 0, 360, 24, -81.2))
        // Taillamp: a dark housing, the red lens with an amber band along its top, and a glint.
        surface(7, lift([[403, 77], [386, 77], [386, 93], [403, 93]], -1))
        surface(11, lift([[403, 78], [387, 78], [387, 92], [403, 92], [403, 78]], -1))
        surface(21, lift([[403, 88.5], [387, 88.5], [387, 92], [403, 92]], -1))
        surface(20, lift([[389, 86.5], [393, 86.5], [392.3, 85.3], [388.3, 85.3]], -1))
        // The wing on its fins. The Martini stripes run on over it from the roof. The far fin shows its inner face
        // over the deck and its tip above the plane; the near fin hides the plane's end, and its tip's top edge
        // catches the sky.
        surface(64, atZ(fin, 76))
        surface(65, atZ(blade, 77))
        surface(63, atZ(fin, -76))
        surface(62, wing)
        ;[[69, 46, 26], [70, 24, 17], [71, 15, 11.5]].forEach(function(band) {
          ;[-1, 1].forEach(function(side) {
            surface(band[0], chord.slice(2).map(function(c) { return wingAt(c, 1, side * band[1]) })
              .concat(flip(chord.slice(2)).map(function(c) { return wingAt(c, 1, side * band[2]) })))
          })
        })
        surface(66, atZ(blade, -77))
        // Headlamps: a chrome bezel round the glass lens, lighter along its top where it catches the sky, with a
        // glint at its upper left: a small slanted bar on the face plane x around height y, from z back toward
        // the camera's right. An amber indicator on the bumper's corner.
        function glint(x, y, z) { return [[x, y + 0.8, z], [x, y + 0.8, z - 3], [x, y - 0.8, z - 4.5], [x, y - 0.8, z - 1.5]] }
        for (side = -1; side <= 1; side += 2) {
          var lens = rrect(4, 58.5, 67.5, side * 46, side * 84, 2.5)
          surface(57, rrect(4, 57, 69, side * 44, side * 86, 1.5))
          surface(57, lens)
          surface(6, lens)
          surface(19, rrect(4, 63.5, 66.8, side * 48, side * 82, 1.5))
          surface(20, glint(4, 65.5, side < 0 ? -48.5 : 81.5))
          surface(21, rrect(-5, 38.5, 45.5, side * 70, side * 84, 1))
        }
        // The spotlights: a can, 4 deep, as a disc every unit back (they merge, winding) and the lower four's bar;
        // a chrome rim round a glass lens, and a glint.
        surface(58, [[-6, 45, -52], [-6, 45, 52], [-6, 47.5, 52], [-6, 47.5, -52], [-6, 45, -52]])
        spots.forEach(function(l) {
          ;[4, 3, 2, 1, 0].forEach(function(d) { surface(58, level(disc(l[0] + d, l[1], l[2], l[3]))) })
          surface(17, level(disc(l[0], l[1], l[2], l[3])))
          surface(17, level(disc(l[0], l[1], l[2], l[3] - 1.3)))
          surface(59, level(disc(l[0], l[1], l[2], l[3] - 1.3)))
          surface(60, level(glint(l[0], l[1] + l[3] * 0.45, l[2] + l[3] * 0.55)))
        })

        // Decals are painted on the body in 3D, so they turn with it. Lettering is a chamfered racing type
        // on a 4 by 6 grid, slanted, sampled every unit along the surface so it follows the flares.
        var glyphs = {
          A: [[[0, 0], [0, 5], [1, 6], [3, 6], [4, 5], [4, 0]], [[0, 3], [4, 3]]],
          B: [[[0, 0], [0, 6], [3, 6], [4, 5], [4, 4], [3, 3], [4, 2], [4, 1], [3, 0], [0, 0]], [[0, 3], [3, 3]]],
          C: [[[4, 1], [3, 0], [1, 0], [0, 1], [0, 5], [1, 6], [3, 6], [4, 5]]],
          D: [[[0, 0], [0, 6], [3, 6], [4, 5], [4, 1], [3, 0], [0, 0]]],
          E: [[[4, 6], [0, 6], [0, 0], [4, 0]], [[0, 3], [3, 3]]],
          F: [[[4, 6], [0, 6], [0, 0]], [[0, 3], [3, 3]]],
          G: [[[4, 5], [3, 6], [1, 6], [0, 5], [0, 1], [1, 0], [3, 0], [4, 1], [4, 3], [2, 3]]],
          H: [[[0, 0], [0, 6]], [[4, 0], [4, 6]], [[0, 3], [4, 3]]],
          I: [[[2, 0], [2, 6]]],
          K: [[[0, 0], [0, 6]], [[4, 6], [1, 3], [4, 0]], [[0, 3], [1, 3]]],
          L: [[[0, 6], [0, 0], [4, 0]]],
          M: [[[0, 0], [0, 6], [2, 3], [4, 6], [4, 0]]],
          N: [[[0, 0], [0, 6], [4, 0], [4, 6]]],
          O: [[[1, 0], [3, 0], [4, 1], [4, 5], [3, 6], [1, 6], [0, 5], [0, 1], [1, 0]]],
          Q: [[[1, 0], [3, 0], [4, 1], [4, 5], [3, 6], [1, 6], [0, 5], [0, 1], [1, 0]], [[2.5, 1.5], [4, 0]]],
          R: [[[0, 0], [0, 6], [3, 6], [4, 5], [4, 4], [3, 3], [0, 3]], [[2, 3], [4, 0]]],
          S: [[[4, 5], [3, 6], [1, 6], [0, 5], [0, 4], [1, 3], [3, 3], [4, 2], [4, 1], [3, 0], [1, 0], [0, 1]]],
          T: [[[0, 6], [4, 6]], [[2, 6], [2, 0]]],
          U: [[[0, 6], [0, 1], [1, 0], [3, 0], [4, 1], [4, 6]]],
          V: [[[0, 6], [2, 0], [4, 6]]],
          W: [[[0, 6], [0, 0], [2, 3], [4, 0], [4, 6]]],
          X: [[[0, 0], [4, 6]], [[0, 6], [4, 0]]],
          Y: [[[0, 6], [2, 3], [4, 6]], [[2, 3], [2, 0]]],
          " ": [],
          "4": [[[3, 0], [3, 6], [0, 2], [4, 2]]]
        }
        // Text s tall centred on (u, v) of a surface, where place(u, v) is the 3D point u along and v up it,
        // widened by wide where the surface is seen at a slant.
        function letter(tone, text, u, v, s, place, wide) {
          var k = s / 6, kx = k * (wide || 1), u0 = u - (text.length * 5.5 - 1.5) * kx / 2
          text.split("").forEach(function(ch, n) {
            glyphs[ch].forEach(function(stroke) {
              var pts = []
              for (var i = 1; i < stroke.length; i++) {
                var a = stroke[i - 1], b = stroke[i], steps = Math.max(1, Math.ceil(Math.hypot(b[0] - a[0], b[1] - a[1]) * k))
                for (var j = i > 1 ? 1 : 0; j <= steps; j++) {
                  var gx = a[0] + (b[0] - a[0]) * j / steps, gy = a[1] + (b[1] - a[1]) * j / steps
                  pts.push(place(u0 + (n * 5.5 + gx) * kx + gy * 0.25 * k, v - s / 2 + gy * k))
                }
              }
              surface(tone, pts)
            })
          })
        }
        // The near flank, and the windscreen, u across it from the camera's left and v up it.
        function flankAt(u, v) { return [u, v, -zAt(u, v)] }
        function glassAt(u, v) {
          var a = crown(150.5, 92.8, 2, -u), b = crown(206, 127.5, 3, -u * 58 / 72)
          return a.map(function(c, k) { return c + (b[k] - c) * v / 63.7 })
        }
        // Stripes: navy, blue and red, Martini style. A band from v0 to v1 runs across the bumper's face and round
        // its near corner onto the flank, one outline (the GPU renderer leaves slivers along an edge two share),
        // cut round the front flare's lips; behind the door it sweeps up 46 over the rear flare to run under the
        // quarter glass, ending short of the fuel flap. Over the top one runs from x0 to x1 at
        // z0 to z1 across a panel whose profile is line, crowned by rise.
        function sweep(x) { var t = Math.min(1, Math.max(0, (x - 258) / 42)); return 46 * t * t * (3 - 2 * t) }
        function band(tone, v0, v1) {
          var ends = [faceAt, function(v) { return lip(100, v, -1) }, function(v) { return lip(100, v, 1) },
            function(v) { return 348 + (v - 30) * 0.5 }]
          for (var n = 0; n < 4; n += 2) {
            var pts = along(v0, ends[n](v0), ends[n + 1](v0))
            for (var v = v0; v < v1; v++) pts.push([ends[n + 1](v), v])
            pts = pts.concat(flip(along(v1, ends[n](v1), ends[n + 1](v1))))
            if (n) for (v = v1; v > v0; v--) pts.push([ends[n](v), v])
            var side = lift(pts.map(function(p) { return [p[0], p[1] + sweep(p[0])] }), -1)
            surface(tone, n ? side : flip(across(-5, v0, 0)).concat(side, across(-5, v1, 0)))
          }
        }
        function heightAt(line, x) {
          for (var i = 1; i < line.length - 1 && line[i][0] < x; i++);
          var a = line[i - 1], b = line[i]
          return a[1] + (b[1] - a[1]) * (x - a[0]) / (b[0] - a[0])
        }
        function stripe(tone, line, rise, x0, x1, z0, z1) {
          var near = [], far = []
          for (var x = x0; x < x1 + 4; x += 4) {
            var at = Math.min(x, x1), y = heightAt(line, at)
            near.push(crown(at, y, rise, z0))
            far.unshift(crown(at, y, rise, z1))
          }
          surface(tone, near.concat(far))
        }
        band(9, 36, 44)
        band(10, 32, 35)
        band(11, 29.5, 31)
        ;[[hood, 2, 9, 146], [roof, 3, 210, 300], [deck, 1, 375, 401]].forEach(function(panel) {
          ;[-1, 1].forEach(function(side) {
            stripe(9, panel[0], panel[1], panel[2], panel[3], 46 * side, 26 * side)
            stripe(10, panel[0], panel[1], panel[2], panel[3], 24 * side, 17 * side)
            stripe(11, panel[0], panel[1], panel[2], panel[3], 15 * side, 11.5 * side)
          })
        })
        // Round the corners in the panel's own coordinates, before projecting onto the car.
        function rounded(poly, radius) {
          var out = []
          poly.forEach(function(p, i) {
            var a = poly[(i + poly.length - 1) % poly.length], b = poly[(i + 1) % poly.length]
            var da = Math.hypot(a[0] - p[0], a[1] - p[1]), db = Math.hypot(b[0] - p[0], b[1] - p[1])
            var r = Math.min(radius, da / 3, db / 3)
            var from = p.map(function(v, k) { return v + (a[k] - v) * r / da })
            var to = p.map(function(v, k) { return v + (b[k] - v) * r / db })
            for (var j = 0; j <= 6; j++) {
              var t = j / 6
              out.push(p.map(function(v, k) { return (1 - t) * (1 - t) * from[k] + 2 * t * (1 - t) * v + t * t * to[k] }))
            }
          })
          return out.concat([out[0]])
        }
        // The flank's decals sit on its lines, each of omarchy.org's lines used once: the race number roundel
        // mid-door between the navy band (y 44) and shoulder (y 72), level with the fender patch; a line reversed
        // out of the navy band under it, one under the door glass and one on the rocker (which slopes in 6 over
        // its 8 height), all centred on the door; and a sun strip across the top of the windscreen, which the
        // inside doesn't show through.
        function onFlank(pts) { return pts.map(function(p) { return flankAt(p[0], p[1]) }) }
        var door = 208
        surface(12, onFlank(arc(door, 59, 11.5, 0, 360, 48, 0)))
        surface(13, onFlank(arc(door, 59, 10, 0, 360, 48, 0)))
        letter(16, "4", door, 59, 12, flankAt)
        letter(15, "WE CAN FIX EVERYTHING", door, 40, 5, flankAt)
        letter(15, "BACKED BY THE OLIGARCHY", door, 20, 4.5, function(u, v) { return [u, v, -78 - (v - 16) * 0.75] })
        letter(14, "UNITE THE NERDS", door, 76, 4, flankAt)
        function fenderAt(u, v) { return flankAt(unwarp(u), v) }
        surface(9, plate(39, 66, 53, 65, 0, 1.5).map(function(p) { return fenderAt(p[0], p[1]) }))
        letter(15, "OMAKASE", 52.5, 59, 4, fenderAt)
        // The mouth is on the flare's front face (x=270), spanning its width, not the side panel.
        // Its painted cheek tapers back into the arch; zAt wraps the livery over that same surface.
        function intakeAt(p, sink) { return [270 + (sink || 0), 31 + p[1], -85 - p[0]] }
        var aperture = [[0, 0], [8, 0], [14, 36], [0, 36]]
        var mouth = rounded(aperture, 0.7), opening = inset(mouth, 0.45)
        var outer = mouth.map(function(p) { return intakeAt(p) }), hole = opening.map(function(p) { return intakeAt(p) })
        // Offset straight edges before rounding, so the throat's corners cannot fold inside out.
        var throat = inset(aperture.concat([aperture[0]]), 3.0)
        var intakeMesh = rounded(throat.slice(0, -1), 0.25).map(function(p) { return intakeAt(p, 1.5) })
        surface(73, hole)
        surface(74, hole)
        surface(74, intakeMesh)
        surface(72, outer)
        surface(72, hole)
        var cheek = along(31, 270, 286)
        for (i = 32; i <= 67; i++) cheek.push([286, i])
        cheek = cheek.concat(flip(along(67, 270, 286)))
        for (i = 66; i >= 31; i--) cheek.push([270, i])
        surface(75, lift(cheek, -1))
        add(outer).underPaint = true
        var edge = [], top = []
        for (i = 0; i <= 12; i++) { edge.push(glassAt(72 * (i / 6 - 1), 44)); top.unshift(glassAt(72 * (i / 6 - 1), 63.7)) }
        surface(9, edge.concat(top))
        letter(15, "OMARCHY", 0, 54, 14, glassAt)
        // Up front: QUATTRO, Omarchy 4's name, in navy across the bumper under the stripes, where the S1
        // carries its sponsor, widened, as the face is seen at a slant; and a red chin, running on round the near
        // corner to the arch, as the S1's lip does.
        letter(14, "QUATTRO", 0, 26, 4.5, function(u, v) { return [-5, v, -u] }, 1.8)
        surface(11, lift([[-9, 15], [-9, 18], [lip(100, 18, -1), 18], [lip(100, 15, -1), 15]], -1))
        surface(11, across(-9, 15, 0).concat(flip(across(-9, 18, 0))))
        // A black lamp panel round the grille, as the S1's, bevel and all: the white hood ends at a crisp edge.
        surface(18, nose)
        // Tyre lettering round each sidewall, top and bottom, turning with the wheel.
        wheels.forEach(function(wheel) {
          ;[[90, "HAVE SOME FUN"], [270, "BEAUTY IS TRUTH"]].forEach(function(side) {
            var n = surfaces.length, a0 = side[0]
            letter(15, side[1], 0, 0, 4, function(u, v) {
              var a = a0 * Math.PI / 180 - u / 26, r = 26 + v
              return grow([wheel.x + r * Math.cos(a), 30 + r * Math.sin(a), -84.5], wheel.x)
            })
            surfaces.slice(n).forEach(function(lettered) { lettered.axle = wheel.x })
          })
        })
        return { parts: list, surfaces: surfaces, panes: [panes[0], panes[1], windscreen.slice(0, 13).concat(edge, [windscreen[0]])],
          dash: dash.concat(inside[0], inside[1]) }
      }

      // Screen polylines of an outline from a to b; an outline inside the car keeps only the
      // stretches that show through the glass.
      function pieces(part, a, b, dx, dy) {
        if (!part.runs) return [slice(part, a, b, dx, dy)]
        var out = []
        part.runs.forEach(function(run) { if (Math.min(b, run[1]) > Math.max(a, run[0])) out.push(slice(part, Math.max(a, run[0]), Math.min(b, run[1]), dx, dy)) })
        return out
      }

      // Whether a screen point is inside a closed screen outline (even-odd).
      function contains(poly, q) {
        var c = false
        for (var i = 0, j = poly.length - 1; i < poly.length; j = i++)
          if ((poly[i][1] > q[1]) !== (poly[j][1] > q[1]) && q[0] < (poly[j][0] - poly[i][0]) * (q[1] - poly[i][1]) / (poly[j][1] - poly[i][1]) + poly[i][0]) c = !c
        return c
      }

      // Screen point, with its depth, at distance d along an outline.
      function pointAt(part, d) {
        var c = part.cum, s = part.screen, j = 1
        while (j < c.length - 1 && c[j] < d) j++
        var k = (d - c[j - 1]) / Math.max(1e-6, c[j] - c[j - 1])
        return [0, 1, 2].map(function(i) { return s[j - 1][i] + (s[j][i] - s[j - 1][i]) * k })
      }

      // Screen polygons of the surfaces by tone, posed by f; wheels by view, turned but for what's still, as
      // they don't pitch.
      function shade(f) {
        focusHeights = Qt.point(view([322, 62, -84])[1], f([300, 131, 64])[1])
        var out = paint.map(function() { return [] })
        model.surfaces.forEach(function(s) {
          var pts = s.pts.map(function(p) { return s.axle === undefined ? f(p) : view(s.still ? p : turn(p, s.axle)) })
          if (s.hull) pts = hull(pts)
          out[s.tone].push(pts.map(function(q) { return Qt.point(q[0], q[1]) }))
        })
        return out
      }

      // Where the paint's leading edge crosses the surfaces. A polygon meets a vertical line an even
      // number of times, so sorted down the screen the crossings pair into the stretches being cut:
      // the lit edge follows the car's own shape rather than running straight down it.
      function cuts() {
        var out = []
        fills.forEach(function(tone) { tone.forEach(function(poly) {
          var hits = []
          for (var i = 0; i < poly.length; i++) {
            var a = poly[i], b = poly[(i + 1) % poly.length]
            if ((a.x < front) !== (b.x < front)) hits.push(Qt.point(front, a.y + (b.y - a.y) * (front - a.x) / (b.x - a.x)))
          }
          hits.sort(function(a, b) { return a.y - b.y })
          for (i = 0; i + 1 < hits.length; i += 2) out.push([hits[i], hits[i + 1]])
        }) })
        return out
      }

      // A point on a wheel turned by rolled about its axle.
      function turn(p, axle) {
        var dx = p[0] - axle, dy = p[1] - 30, c = Math.cos(rolled), s = Math.sin(rolled)
        return [axle + dx * c - dy * s, 30 + dx * s + dy * c, p[2]]
      }

      // Convex hull of screen points (monotone chain): the silhouette of a solid.
      function hull(pts) {
        pts = pts.slice().sort(function(a, b) { return a[0] - b[0] || a[1] - b[1] })
        function half(list) {
          var h = []
          list.forEach(function(p) {
            while (h.length > 1 && (h[h.length - 1][0] - h[h.length - 2][0]) * (p[1] - h[h.length - 2][1]) - (h[h.length - 1][1] - h[h.length - 2][1]) * (p[0] - h[h.length - 2][0]) <= 0) h.pop()
            h.push(p)
          })
          return h.slice(0, -1)
        }
        return half(pts).concat(half(pts.slice().reverse()))
      }

      // Screen polyline of an outline from distance a to b along it, shifted by (dx, dy).
      function slice(part, a, b, dx, dy) {
        var c = part.cum, s = part.screen
        function at(d) { var p = pointAt(part, d); return Qt.point(p[0] + dx, p[1] + dy) }
        var out = [at(a)]
        for (var i = 1; i < c.length - 1; i++) if (c[i] > a && c[i] < b) out.push(Qt.point(s[i][0] + dx, s[i][1] + dy))
        out.push(at(b))
        return out
      }

      // The car never moves while it is drawn, so each outline is projected once, from the
      // front-left quarter (yaw 30deg, looking down 0.2rad), with a depth level for its shade.
      function project() {
        // About 480 units wide at this angle; roof to near wheel about 200 tall.
        var S = Math.min(width * 0.88 / 480, height * 0.8 / 200), cx = width / 2, cy = height / 2 - 4 * S, D = 1400
        var cyaw = Math.cos(Math.PI / 6), syaw = Math.sin(Math.PI / 6), cp = Math.cos(0.2), sp = Math.sin(0.2)
        view = function(p) {
          var x = p[0] - 221, y = p[1] - 60
          var x1 = x * cyaw - p[2] * syaw, z1 = x * syaw + p[2] * cyaw
          var y2 = y * cp + z1 * sp, z2 = -y * sp + z1 * cp, k = D / (D + z2)
          return [cx + x1 * k * S, cy - y2 * k * S, z2]
        }
        for (var i = 0; i < parts.length; i++) {
          var part = parts[i], z = 0
          part.screen = part.pts.map(function(p) { var q = view(p); z += q[2]; return q })
          // Brightness falls from 0.95 nearest to 0.3 farthest, in three bands; each band back takes
          // a line down a weight, to the inside's, the faintest.
          var bright = Math.max(0.3, Math.min(0.95, 0.95 - (z / part.pts.length + 120) / 240 * 0.65))
          part.level = part.underPaint ? 4 : part.inside ? 0 : Math.max(0, part.weight + Math.floor(bright * 4) - 3)
          part.whole = pieces(part, 0, part.len, 0, 0)
          // Each outline flies in from just off screen, directions spread by the golden angle and
          // offset half a step, so none is exactly horizontal or vertical (a zero component divides by 0).
          var mx = 0, my = 0, r = 0, a = (i + 0.5) * 2.39996
          part.screen.forEach(function(p) { mx += p[0] / part.screen.length; my += p[1] / part.screen.length })
          part.screen.forEach(function(p) { r = Math.max(r, Math.hypot(p[0] - mx, p[1] - my)) })
          var ux = Math.cos(a), uy = Math.sin(a)
          var out = Math.min(ux > 0 ? (width - mx) / ux : -mx / ux, uy > 0 ? (height - my) / uy : -my / uy) + r
          part.fly = [ux * out, uy * out]
        }
        // Inside outlines keep the stretches, sampled every unit, that fall within a pane and aren't
        // behind another group's solid: the hull of its outlines, at their mean depth. The dash is a solid too.
        var panes = model.panes.map(function(pane) { return pane.map(view) })
        var solids = { dash: { group: "dash", pts: model.dash.map(view) } }
        parts.forEach(function(part) {
          if (!part.cover) return
          var solid = solids[part.cover] = solids[part.cover] || { group: part.group, pts: [] }
          solid.pts = solid.pts.concat(part.screen)
        })
        solids = Object.keys(solids).map(function(key) {
          var solid = solids[key]
          return { group: solid.group, hull: hull(solid.pts), depth: solid.pts.reduce(function(sum, p) { return sum + p[2] }, 0) / solid.pts.length }
        })
        parts.forEach(function(part) {
          if (!part.inside) return
          var runs = [], from = -1
          for (var d = 0; d <= part.len; d++) {
            var q = pointAt(part, d)
            var seen = panes.some(function(pane) { return contains(pane, q) }) && !solids.some(function(solid) {
              return solid.group !== part.group && q[2] > solid.depth && contains(solid.hull, q)
            })
            if (seen && from < 0) from = d
            if (!seen && from >= 0) { runs.push([from, d - 1]); from = -1 }
          }
          if (from >= 0) runs.push([from, part.len])
          part.runs = runs
          part.whole = pieces(part, 0, part.len, 0, 0)
        })
        fills = shade(view)
        // The paint has to cross every painted point: mirrors and bumper reach past the bodywork.
        var lo = Infinity, hi = -Infinity
        fills.forEach(function(tone) { tone.forEach(function(poly) { poly.forEach(function(q) {
          if (q.x < lo) lo = q.x
          if (q.x > hi) hi = q.x
        }) }) })
        span = [lo - 1, hi + 1]
        cabin = [[290, 96, 78], [290, 50, 78]].map(function(p) { var q = view(p); return Qt.point(q[0], q[1]) })
        ground = [[100, -2, -88], [322, -2, -88]].map(function(p) { var q = view(p); return Qt.point(q[0], q[1]) })
        finished = -1
        frame()
      }

      function frame() {
        if (!parts[0].whole) return
        var done = 0, drawn = [[], [], [], [], []], heat = [[], [], [], []]
        for (var i = 0; i < parts.length; i++) {
          var part = parts[i]
          if (clock >= part.end) { done++; continue }
          if (clock <= part.start) continue
          // The comet's tail spans 12% of its outline, like the logo's, and at least 110 units.
          var k = (clock - part.start) / (part.end - part.start), d = k * part.len
          var tail = Math.min(d, Math.max(0.12 * part.len, 110))
          // The flight eases out and lands as the comet finishes the outline.
          var f = Math.pow(1 - k, 3), dx = part.fly[0] * f, dy = part.fly[1] * f
          drawn[part.level].push.apply(drawn[part.level], pieces(part, 0, d, dx, dy))
          heat[0].push.apply(heat[0], pieces(part, d - tail, d - tail * 2 / 3, dx, dy))
          heat[1].push.apply(heat[1], pieces(part, d - tail * 2 / 3, d - tail / 3, dx, dy))
          heat[2].push.apply(heat[2], pieces(part, d - tail / 3, d, dx, dy))
        }
        heat[3] = heat[2]
        if (done !== finished) {
          var still = [[], [], [], [], []]
          for (i = 0; i < parts.length; i++) if (clock >= parts[i].end) still[parts[i].level].push.apply(still[parts[i].level], parts[i].whole)
          lines = still
          finished = done
        }
        tracing = drawn
        comets = heat
      }

      onClockChanged: frame()
      onFrontChanged: wavefront = painted > 0 && painted < 1 ? cuts() : []
      // Drive-off, in ms: the engine starts (lamps flicker on, body idles) until 300, the
      // wheels spin up and the rear squats until 500, then the car launches trailing speed
      // streaks. Every frame reposes the car; the launch itself moves it as a texture.
      onDriveChanged: {
        if (!view) return
        var t = drive * driveTime, u = Math.max(0, (t - 500) / (driveTime - 500))
        launch = u * u * u
        lamps = t === 0 ? 0 : t < 50 ? 0.8 : t < 110 ? 0.1 : Math.min(1, t / 250)
        // Wheels spin at 0.14rad a frame, under half the mesh's 18deg repeat, so they never seem to turn backwards.
        rolled = t === 0 ? 0 : rolled + 0.14 * Math.min(1, Math.max(0, (t - 300) / 150))
        var shake = t < 500 ? 1.2 * Math.sin(t * 0.16) : 0
        var pitch = 0.06 * Math.min(1, Math.max(0, (t - 300) / 200))
        pose = [pitch, shake]
        var cp = Math.cos(pitch), sp = Math.sin(pitch)
        // Bodywork pitches nose-up about the rear axle and shakes; wheels only turn.
        function body(p) {
          var dx = p[0] - 322, dy = p[1] - 30
          return view([322 + dx * cp + dy * sp, 30 - dx * sp + dy * cp + shake, p[2]])
        }
        for (var i = 0; i < parts.length; i++) {
          var part = parts[i]
          part.screen = part.pts.map(part.axle === undefined ? body : part.still ? view : function(p) { return view(turn(p, part.axle)) })
          part.whole = pieces(part, 0, part.len, 0, 0)
        }
        fills = shade(body)
        finished = -1
        frame()
        glowing = parts.filter(function(part) { return part.lamp }).map(function(part) { return part.whole[0] })
        if (u === 0) return
        // Each streak reaches back as far as the car went in the last 120ms, in its scaled frame.
        var back = Math.min(width * 0.5, width * 1.2 * (launch - Math.pow(Math.max(0, u - 120 / (driveTime - 500)), 3)) / (1 + 0.3 * launch))
        var ml = Math.hypot(width * 1.2, height * 0.14), bx = width * 1.2 / ml * back, by = -height * 0.14 / ml * back
        var heat = [comets[0].slice(), comets[1].slice(), comets[2].slice()]
        streakFrom.forEach(function(p) {
          var q = body(p)
          function at(f) { return Qt.point(q[0] + bx * f, q[1] + by * f) }
          heat[2].push([at(0), at(1 / 3)])
          heat[1].push([at(1 / 3), at(2 / 3)])
          heat[0].push([at(2 / 3), at(1)])
        })
        comets = [heat[0], heat[1], heat[2], heat[2]]
      }
      onWidthChanged: project()
      onHeightChanged: project()
      Component.onCompleted: project()

      NumberAnimation on clock { id: run; from: 0; to: car.duration; duration: car.duration; running: false }
      NumberAnimation on drive { id: go; from: 0; to: 1; duration: car.driveTime; running: false }

      function play() { go.stop(); drive = 0; run.restart() }
      function hide() { go.stop(); run.stop(); drive = 0; clock = 0 }
      function driveOff() { go.restart() }
    }

    // The field is dark glass edged in neon, which glows onto the floor around it.
    Rectangle {
      id: halo
      anchors.fill: inputField
      radius: inputField.radius
      color: "transparent"
      border.width: 6
      border.color: root.neonColor
      visible: false
    }

    MultiEffect {
      anchors.fill: halo
      source: halo
      blurEnabled: true
      blur: 1
      blurMax: 40
    }

    Rectangle {
      id: inputField
      width: root.fieldWidth
      height: root.fieldHeight
      anchors.horizontalCenter: parent.horizontalCenter
      anchors.bottom: parent.bottom
      anchors.bottomMargin: parent.height * 0.08
      color: "#eb080c14"
      border.width: 1.5
      border.color: root.neonColor
      radius: 14
      clip: true

      Text {
        anchors.left: parent.left
        anchors.leftMargin: 22
        anchors.verticalCenter: parent.verticalCenter
        text: "\u{f0341}"
        color: Color.lock.placeholder
        font.family: Style.font.family
        font.pixelSize: Math.round(root.fieldFontSize * 1.6)
      }

      TextInput {
        id: passwordInput
        anchors.fill: parent
        // Reserve the fingerprint icon's width on both sides so the centered
        // dots stay symmetric and never slide under the icon as they grow.
        anchors.rightMargin: root.fieldInset + root.fingerprintReserve
        anchors.leftMargin: root.fieldInset + root.fingerprintReserve
        verticalAlignment: TextInput.AlignVCenter
        horizontalAlignment: TextInput.AlignHCenter
        activeFocusOnPress: true
        clip: true
        enabled: root.inputEnabled && !root.authenticatingPassword
        readOnly: root.authenticatingPassword
        echoMode: TextInput.Password
        passwordCharacter: "\u25CF"
        passwordMaskDelay: 0
        color: Color.lock.text
        selectionColor: Color.lock.selection
        selectedTextColor: Color.lock.text
        font.family: Style.font.family
        font.pixelSize: text.length > 0 ? Math.max(1, Math.floor(root.passwordDotFontSize * root.passwordDotScale)) : root.fieldFontSize
        font.letterSpacing: text.length > 0 ? root.passwordDotLetterSpacing * root.passwordDotScale : 0
        cursorVisible: activeFocus && root.showPasswordCursor && text.length > 0
        cursorDelegate: Rectangle {
          width: 2
          color: Color.lock.text
          visible: passwordInput.cursorVisible
        }

        onTextChanged: {
          if (!root.syncingPasswordText) root.passwordTextEdited(text)
          if (text.length > 0) {
            root.wakeRequested()
          }
          if (text.length > 0 && root.failureMessage.length > 0) root.clearFailureRequested()
        }

        onAccepted: {
          var submitted = root.passwordText
          root.passwordTextEdited("")
          if (submitted.length > 0) root.submitPassword(submitted)
        }

        Keys.onPressed: function(event) {
          root.startOnInput()
          root.wakeRequested()
          if (event.key === Qt.Key_Escape || (event.modifiers & Qt.ControlModifier && event.key === Qt.Key_U)) {
            root.passwordTextEdited("")
            event.accepted = true
          }
        }
      }

      Text {
        textFormat: Text.PlainText
        anchors.fill: passwordInput
        text: root.authenticatingPassword ? "Checking…" : (root.failureMessage.length > 0 ? root.failureMessage : root.placeholderText)
        visible: passwordInput.text.length === 0
        color: root.authenticatingPassword ? Color.lock.text : (root.failureMessage.length > 0 ? Color.lock.textError : Color.lock.placeholder)
        font.family: Style.font.family
        font.pixelSize: root.fieldFontSize
        font.italic: !root.authenticatingPassword && root.failureMessage.length > 0
        horizontalAlignment: Text.AlignHCenter
        verticalAlignment: Text.AlignVCenter
        elide: Text.ElideRight
      }

      // Fingerprint hint pinned inside the field's right edge when a sensor is
      // enrolled, so the user knows they can touch to unlock instead of typing.
      // Matches hyprlock, which draws its fingerprint icon in the same spot.
      Text {
        id: fingerprintIcon
        objectName: "fingerprintIndicator"
        anchors.right: submit.left
        anchors.rightMargin: 12
        anchors.verticalCenter: parent.verticalCenter
        visible: root.fingerprintConfigured
        text: "󰈷"
        color: Color.lock.placeholder
        font.family: Style.font.family
        font.pixelSize: Math.round(root.fieldFontSize * 1.1)
        horizontalAlignment: Text.AlignHCenter
        verticalAlignment: Text.AlignVCenter
      }

      Rectangle {
        id: submit
        anchors.right: parent.right
        anchors.rightMargin: 16
        anchors.verticalCenter: parent.verticalCenter
        width: 38
        height: 38
        radius: 19
        color: "transparent"
        border.width: 1.5
        border.color: root.neonColor

        Text {
          anchors.centerIn: parent
          text: "\u{f0054}"
          color: Color.lock.text
          font.family: Style.font.family
          font.pixelSize: root.fieldFontSize
        }

        MouseArea {
          anchors.fill: parent
          cursorShape: Qt.PointingHandCursor
          onClicked: passwordInput.accepted()
        }
      }
    }
  }
}
