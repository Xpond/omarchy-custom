import QtQuick
import Quickshell
import Quickshell.Wayland
import qs.Commons

// Layer-shell popup attached to a bar widget icon, designed for
// click-driven AND keyboard-driven panels (e.g. SUPER+CTRL+W summon).
//
// Built on PanelWindow with a brief WlrKeyboardFocus.Exclusive prime followed
// by OnDemand rather than PopupWindow (xdg-popup). The prime acquires focus
// both when the surface maps and when it reopens while still mapped for its
// fade-out. xdg-popups don't get that — they only receive keys after a
// click/hover routes focus through their parent surface — so keyboard-summoned
// popups fell flat without it.
//
// Exclusive would also grant map-time focus, but it makes Hyprland route
// *every* pointer event to the exclusive surface no matter which output
// the cursor is over, which leaves clicks on any other monitor unable to
// reach the dismissal surfaces below.
//
// API is a subset of Common.PopupCard: anchorItem, owner, bar, open,
// padding, margin, contentWidth/Height, centerOnBar, default contentItem.
// Missing on purpose (for now): triggerMode ("hover"), containsMouse.
//
// Positioning: full-screen layer-shell with the card placed inside at
// `cardOrigin`. We use the bar window's height/width for the perpendicular
// axis (away-from-bar) because mapToItem on the anchor returns
// bar-content-relative coords with internal layout offsets baked in
// (e.g. ~13px from the bar's vertical centering of its widget row). The
// parallel axis (along-the-bar) uses the anchor's content x/y since the
// bar spans full screen on that axis.
//
// Outside-click dismissal: an overlay MouseArea catches clicks, with the
// QsWindow.mask subtracting the bar strip so clicks on the bar still
// reach the bar widgets (activePopout coordinator hands off to another
// popup if the user clicks a different bar icon).
PanelWindow {
  id: root

  required property Item anchorItem
  required property QtObject bar
  property var owner: null
  property int margin: Style.gapsOut
  property int padding: Style.spacing.popupPadding
  property int contentWidth: Style.space(280)
  property int contentHeight: Style.space(200)
  property var borderSpec: Border.surfaceSpec("popups", "border", Color.popups.border, Math.max(1, Style.space(2)))
  property bool centerOnBar: false
  // Center the card on the screen instead of tucking it against the bar edge
  // next to its widget. The surface is already full-screen, so this only moves
  // the card inside it.
  property bool centerOnScreen: true
  // Entry/exit motion.
  //
  // The card emerges rather than growing out of the button. Scaling a card far
  // enough to read as "coming from" a 26px bar button means scaling its text
  // and sliders with it, and stretching glyphs is what makes the movement look
  // cheap -- you watch the contents deform instead of a panel arriving. So the
  // scale change is kept below the threshold where deformation is legible, and
  // the link to the button is carried by direction instead: the card enters
  // from the button's side, travelling a short capped distance rather than the
  // full journey across the screen.
  property int openMotionDuration: 260
  property int closeMotionDuration: 150
  property int fadeDuration: 180
  property int closeFadeDuration: 130
  property real emergeScale: 0.96
  property real travelFraction: 0.12
  property real maxTravel: Style.space(56)
  property bool open: false
  property int gap: Style.gapsOut  // distance between bar edge and panel
  property bool popoutSwitching: false
  property bool popoutSwitchClosing: false
  property bool focusPrimed: false

  // Item that should take keyboard focus once the panel maps. Typically a
  // PanelKeyCatcher inside the panel content. Layer-shell grants focus to the
  // surface during the Exclusive prime, but Qt still needs an active-focus
  // target inside the surface for Keys.onPressed handlers to fire. Schedule
  // the focus through Qt.callLater so it runs after the surface is fully
  // mapped and child items have completed layout.
  property Item focusTarget: null

  default property alias contentItem: contentHolder.children

  readonly property var coordinatorKey: owner || root
  readonly property var anchorWindow: anchorItem ? anchorItem.QsWindow.window : null
  readonly property string barPos: bar ? bar.position : "top"

  function close() {
    if (owner && "close" in owner) owner.close()
    else root.open = false
  }

  function beginFocusPrime() {
    if (open && backingWindowVisible) focusPrimeTimer.restart()
  }

  // Seed the card's offset for this open, then animate it back to rest.
  // A switch slides in horizontally from the side the switch travelled;
  // a fresh open rises. `lastSwitchDirection` is single-use -- reading it
  // clears it, so a later mouse-driven switch doesn't inherit a stale
  // direction from an earlier keyboard one.
  function startEntryMotion() {
    var dir = 0
    if (bar && bar.lastSwitchDirection !== undefined) {
      dir = bar.lastSwitchDirection
      bar.lastSwitchDirection = 0
    }
    if (popoutSwitching && dir !== 0) {
      // Panel handoff: keep the flat horizontal slide, no scaling. The card is
      // already on screen and merely changing contents -- growing it out of a
      // button here would read as a second, competing open.
      card.slideX = dir * Style.space(56)
      card.slideY = 0
      card.originScale = 1
    } else {
      // Fresh open: start small, centred on the button that was clicked, and
      // grow into place -- so the panel visibly comes from that button.
      card.slideX = offsetToAnchor.x
      card.slideY = offsetToAnchor.y
      card.originScale = emergeScale
    }
    entryMotion.restart()
  }

  // Collapse back into the owning button, mirroring the open. Skipped during a
  // panel handoff, where the outgoing card is replaced rather than dismissed.
  function startExitMotion() {
    exitX.to = offsetToAnchor.x
    exitY.to = offsetToAnchor.y
    exitMotion.restart()
  }

  // --- screen + lifetime ---------------------------------------------------

  screen: anchorWindow ? anchorWindow.screen : null
  visible: open || card.opacity > 0 || popoutSwitching
  color: "transparent"
  exclusionMode: ExclusionMode.Ignore

  WlrLayershell.namespace: "omarchy-keyboard-panel"
  WlrLayershell.layer: WlrLayer.Overlay
  // Keyboard focus follows `open` (NOT `visible`). The window remains
  // mapped during the fade-out so the opacity animation has something to
  // animate, but keyboard/click ownership must release the moment the
  // logical close fires — otherwise the user is locked out for 140ms.
  //
  // Prime with Exclusive on every open, then settle on OnDemand. Hyprland
  // focuses OnDemand when a surface first maps, but not when an already-mapped
  // fade-out surface changes from None back to OnDemand. Exclusive also takes
  // focus when the previously focused application has constrained the pointer.
  // The brief prime covers both cases; OnDemand then releases compositor-wide
  // pointer hit-testing so clicks can reach the dismissal windows below.
  WlrLayershell.keyboardFocus: open
    ? (focusPrimed ? WlrKeyboardFocus.OnDemand : WlrKeyboardFocus.Exclusive)
    : WlrKeyboardFocus.None

  onBackingWindowVisibleChanged: beginFocusPrime()

  // Full-screen layer-shell. The visible card is positioned inside via
  // `cardOrigin`. The `mask` below makes the bar area click-through (so
  // the user can click another bar icon while the panel is open and the
  // activePopout coordinator swaps to that popup); everywhere else, the
  // overlay catches the click and dismisses via the MouseArea below.
  anchors {
    top: true
    bottom: true
    left: true
    right: true
  }

  // Clickable region is the whole screen. Clicks in the bar strip are
  // forwarded to registered bar buttons so switching between panel icons
  // works in one click even when the overlay surface is above the bar.
  readonly property real _barStripSize: {
    if (!bar) return 0
    var actual = (root.barPos === "top" || root.barPos === "bottom") ? root.barH : root.barW
    return Math.max(bar.barSize, actual) + root.gap
  }
  mask: Region {
    width: root.screenW
    height: root.screenH
  }

  // Track every layout change between the bar's contentItem and the
  // anchor item. `transform` updates whenever any item in that chain
  // moves/resizes, which is what makes the position binding below
  // actually reactive — mapToItem on its own is a one-shot.
  TransformWatcher {
    id: anchorWatcher
    a: anchorWindow ? anchorWindow.contentItem : null
    b: anchorItem
  }

  // Anchor item's position within the bar's content surface. For a
  // full-width top bar, the content x maps directly to screen x; the y
  // returned here has the bar's internal padding baked in (e.g. ~13px
  // from vertical centering of the widget row), which is why `cardOrigin`
  // below uses `barH` for the perpendicular axis instead of this y.
  readonly property point anchorScreenPos: {
    anchorWatcher.transform  // reactive dependency
    if (!anchorItem || !anchorWindow) return Qt.point(0, 0)
    return anchorItem.mapToItem(anchorWindow.contentItem, 0, 0)
  }
  readonly property real anchorW: anchorItem ? anchorItem.width : 0
  readonly property real anchorH: anchorItem ? anchorItem.height : 0
  readonly property real screenW: screen ? screen.width : 0
  readonly property real screenH: screen ? screen.height : 0
  readonly property real availableCardWidth: screenW > 0
    ? Math.max(120, screenW - ((barPos === "left" || barPos === "right") ? barW + gap + margin : margin * 2))
    : 0
  readonly property real availableCardHeight: screenH > 0
    ? Math.max(120, screenH - ((barPos === "top" || barPos === "bottom") ? barH + gap + margin : margin * 2))
    : 0
  readonly property real verticalContentInset: padding * 2 + Border.top(borderSpec) + Border.bottom(borderSpec)

  function fittedContentWidth(width, cap) {
    var desired = Math.max(1, Number(width) || 1)
    var maxWidth = root.availableCardWidth > 0 ? root.availableCardWidth : desired
    if (cap !== undefined && Number(cap) > 0) maxWidth = Math.min(maxWidth, Number(cap))
    return Math.round(Math.min(desired, maxWidth))
  }

  function fittedContentHeight(implicitHeight, cap) {
    var desired = Math.max(root.verticalContentInset, (Number(implicitHeight) || 0) + root.verticalContentInset)
    var maxHeight = root.availableCardHeight > 0 ? root.availableCardHeight : desired
    if (cap !== undefined && Number(cap) > 0) maxHeight = Math.min(maxHeight, Number(cap))
    return Math.round(Math.min(desired, maxHeight))
  }

  function cappedContentHeight(height) {
    var desired = Math.max(root.padding * 2, Number(height) || root.padding * 2)
    var maxHeight = root.availableCardHeight > 0 ? root.availableCardHeight : desired
    return Math.round(Math.min(desired, maxHeight))
  }

  // Desired top-left of the card in screen coordinates. For the
  // perpendicular axis (away-from-bar) we anchor to the bar window's edge
  // directly — not the anchor item's y/x — because mapToItem(barContent)
  // returns coordinates in the bar's content space, which can be offset
  // from the bar surface's screen-anchored corner by internal layout
  // (centering wrappers, padding). The bar's surface IS aligned to its
  // anchored screen edge, so using `barW`/`barH` gives the right edge
  // regardless of how the bar's internal widgets are positioned. For the
  // parallel axis (along the bar) the anchor item's reported position is
  // still consistent with the bar content origin, so it's accurate for
  // centering the card under the icon.
  readonly property real barW: anchorWindow ? anchorWindow.width : screenW
  readonly property real barH: anchorWindow ? anchorWindow.height : 0
  // Centre of the bar button that owns this panel, in surface coordinates --
  // the point the card grows out of and collapses back into. The parallel
  // axis (along the bar) uses the anchor's own position; the perpendicular
  // one uses the bar window's thickness, for the same reason cardOrigin does:
  // the anchor's reported position on that axis has the bar's internal
  // layout padding baked in.
  readonly property point anchorCenter: {
    anchorWatcher.transform  // reactive dependency
    if (barPos === "bottom") return Qt.point(anchorScreenPos.x + anchorW / 2, screenH - barH / 2)
    if (barPos === "top")    return Qt.point(anchorScreenPos.x + anchorW / 2, barH / 2)
    if (barPos === "left")   return Qt.point(barW / 2, anchorScreenPos.y + anchorH / 2)
    return Qt.point(screenW - barW / 2, anchorScreenPos.y + anchorH / 2)
  }

  // A short offset pointing at the owning button, rather than all the way to
  // it. Same direction as the full journey, a fraction of the distance and
  // capped, so the card enters from the right side without the visible trip.
  readonly property point offsetToAnchor: {
    var dx = anchorCenter.x - (cardOrigin.x + contentWidth / 2)
    var dy = anchorCenter.y - (cardOrigin.y + contentHeight / 2)
    var length = Math.sqrt(dx * dx + dy * dy)
    if (length < 1) return Qt.point(0, 0)
    var travel = Math.min(length * travelFraction, maxTravel)
    return Qt.point(dx / length * travel, dy / length * travel)
  }

  readonly property point cardOrigin: {
    if (centerOnScreen && screenW > 0 && screenH > 0) {
      return Qt.point(Math.round(screenW / 2 - contentWidth / 2),
                      Math.round(screenH / 2 - contentHeight / 2))
    }
    if (!anchorItem || !bar) return Qt.point(margin, margin)
    var x = 0, y = 0
    if (centerOnBar && (barPos === "top" || barPos === "bottom")) {
      x = screenW / 2 - contentWidth / 2
      y = barPos === "bottom" ? screenH - barH - contentHeight - gap : barH + gap
    } else if (centerOnBar) {
      x = barPos === "left" ? barW + gap : screenW - barW - contentWidth - gap
      y = screenH / 2 - contentHeight / 2
    } else if (barPos === "bottom") {
      x = anchorScreenPos.x + anchorW / 2 - contentWidth / 2
      y = screenH - barH - contentHeight - gap
    } else if (barPos === "left") {
      x = barW + gap
      y = anchorScreenPos.y + anchorH / 2 - contentHeight / 2
    } else if (barPos === "right") {
      x = screenW - barW - contentWidth - gap
      y = anchorScreenPos.y + anchorH / 2 - contentHeight / 2
    } else { // "top" (default)
      x = anchorScreenPos.x + anchorW / 2 - contentWidth / 2
      y = barH + gap
    }
    x = Math.max(margin, Math.min(x, screenW - contentWidth - margin))
    y = Math.max(margin, Math.min(y, screenH - contentHeight - margin))
    return Qt.point(Math.round(x), Math.round(y))
  }


  // --- popout coordination (same-bar single-popout model) -----------------

  // Coordinate on `open`, not `visible`. `visible` lags into the fade-out
  // animation, which made ownership transfer to a sibling popup race.
  onOpenChanged: {
    if (open) {
      focusPrimed = false
      beginFocusPrime()
      if (focusTarget) Qt.callLater(function() {
        if (root.open && root.focusTarget) root.focusTarget.forceActiveFocus()
      })
    } else {
      focusPrimeTimer.stop()
      focusPrimed = false
    }
    if (!bar) return
    if (open) {
      popoutSwitchClosing = false
      popoutSwitching = bar.activePopout && bar.activePopout !== coordinatorKey
      bar.requestPopout(coordinatorKey)
      if (popoutSwitching) popoutSwitchTimer.restart()
      startEntryMotion()
    } else {
      popoutSwitchClosing = !!(owner && owner.popoutSwitchClosing)
      popoutSwitching = false
      if (bar.activePopout === coordinatorKey) bar.releasePopout(coordinatorKey)
      if (popoutSwitchClosing) closeSwitchTimer.restart()
      else startExitMotion()
    }
  }

  Timer {
    id: focusPrimeTimer
    // Leave enough time for multiple Qt/Wayland commit cycles after the
    // backing window becomes visible while keeping the compositor-wide
    // Exclusive phase imperceptibly short. This interval is covered by the
    // immediate hide/re-summon acceptance case.
    interval: 75
    onTriggered: if (root.open) root.focusPrimed = true
  }

  // One curve across all three properties now. Splitting x and y bent the path
  // into an arc, which was worth doing when the card crossed the screen; over
  // a ~56px offset an arc is invisible and the mismatched curves only stop the
  // card moving as one rigid object.
  ParallelAnimation {
    id: entryMotion
    NumberAnimation { target: card; property: "slideX"; to: 0; duration: root.openMotionDuration; easing.type: Easing.OutQuint }
    NumberAnimation { target: card; property: "slideY"; to: 0; duration: root.openMotionDuration; easing.type: Easing.OutQuint }
    NumberAnimation { target: card; property: "originScale"; to: 1; duration: root.openMotionDuration; easing.type: Easing.OutQuint }
  }

  // Matches the card's 140ms opacity fade, so the collapse finishes rather
  // than being cut off when the surface unmaps.
  // Out curves, not the In curves that mirror the entry. A geometric mirror is
  // the wrong model for a dismissal: InQuint has covered 0.5^5 = 3% of the
  // distance at the halfway point, so the card sits still for most of the
  // animation and then jumps. Since the fade is already well underway by then,
  // what you see is a stationary card dissolving in place. Leaving promptly is
  // what makes a dismissal feel connected to the click.
  ParallelAnimation {
    id: exitMotion
    NumberAnimation { id: exitX; target: card; property: "slideX"; duration: root.closeMotionDuration; easing.type: Easing.OutCubic }
    NumberAnimation { id: exitY; target: card; property: "slideY"; duration: root.closeMotionDuration; easing.type: Easing.OutCubic }
    NumberAnimation { target: card; property: "originScale"; to: root.emergeScale; duration: root.closeMotionDuration; easing.type: Easing.OutCubic }
  }

  Timer {
    id: popoutSwitchTimer
    interval: 150
    onTriggered: root.popoutSwitching = false
  }

  Timer {
    id: closeSwitchTimer
    interval: 1
    onTriggered: root.popoutSwitchClosing = false
  }

  // --- outside-click dismissal --------------------------------------------

  // Catches clicks anywhere in the clickable region (i.e. everywhere on
  // screen except the bar strip, which is masked out). The card has its
  // own MouseArea below so clicks on it don't bubble up here. Disabled
  // during the fade-out so the dying overlay doesn't swallow clicks that
  // were meant for the apps behind it.
  MouseArea {
    id: dismissArea
    anchors.fill: parent
    enabled: root.open
    acceptedButtons: Qt.AllButtons
    hoverEnabled: true
    property bool hoveringBar: false
    cursorShape: hoveringBar ? Qt.PointingHandCursor : Qt.ArrowCursor

    function inBarRegion(px, py) {
      if (root.barPos === "bottom") return py >= root.screenH - root._barStripSize
      if (root.barPos === "left") return px <= root._barStripSize
      if (root.barPos === "right") return px >= root.screenW - root._barStripSize
      return py <= root._barStripSize
    }

    function barPoint(px, py) {
      if (root.barPos === "bottom") return Qt.point(px, py - (root.screenH - root.barH))
      if (root.barPos === "right") return Qt.point(px - (root.screenW - root.barW), py)
      return Qt.point(px, py)
    }

    function pressTargetAt(px, py) {
      if (!root.anchorWindow || !root.anchorWindow.contentItem || !root.bar || !root.bar.clickTargets) return null
      var p = barPoint(px, py)
      var targets = root.bar.clickTargets
      for (var i = targets.length - 1; i >= 0; i--) {
        var target = targets[i]
        if (!target || !target.triggerPress || target.visible === false || target.opacity === 0 || !target.mapToItem) continue
        if (root.bar.targetBelongsToWindow && !root.bar.targetBelongsToWindow(target, root.anchorWindow)) continue
        var pos = root.anchorWindow.itemPosition(target)
        if (p.x >= pos.x && p.x <= pos.x + target.width && p.y >= pos.y && p.y <= pos.y + target.height) return target
      }
      return null
    }

    function forwardBarClick(px, py, button) {
      if (button !== Qt.LeftButton && button !== Qt.RightButton && button !== Qt.MiddleButton) return false
      var target = pressTargetAt(px, py)
      if (!target) return false
      target.triggerPress(button)
      return true
    }

    onPositionChanged: function(mouse) { hoveringBar = inBarRegion(mouse.x, mouse.y) }
    onExited: hoveringBar = false
    onClicked: function(mouse) {
      // While Exclusive is priming, Hyprland may route a click from another
      // output here with translated coordinates. Never interpret that as a
      // click on this output's bar.
      if (root.focusPrimed && inBarRegion(mouse.x, mouse.y) && forwardBarClick(mouse.x, mouse.y, mouse.button)) return
      root.close()
    }
  }

  // The panel surface only spans the anchor's screen, and the compositor
  // hit-tests pointer input per output, so `dismissArea` above can never see
  // a click on another monitor. Give every other output a transparent twin
  // whose only job is to catch that click. They exist only while the panel is
  // logically open (not during the fade-out, matching `dismissArea.enabled`).
  //
  // Keyboard focus is None: these must catch the pointer without taking focus
  // from the panel when the cursor merely crosses onto their output.
  Variants {
    model: root.open ? Quickshell.screens : []

    delegate: Component {
      PanelWindow {
        required property var modelData

        screen: modelData
        // Compare by output name: the anchor screen must be known before any
        // twin maps, or a twin would cover the panel's own output.
        visible: root.open && !!root.screen && modelData.name !== root.screen.name
        color: "transparent"
        exclusionMode: ExclusionMode.Ignore

        WlrLayershell.namespace: "omarchy-keyboard-panel-dismiss"
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

        anchors {
          top: true
          bottom: true
          left: true
          right: true
        }

        MouseArea {
          anchors.fill: parent
          acceptedButtons: Qt.AllButtons
          onPressed: root.close()
        }
      }
    }
  }

  // --- card ----------------------------------------------------------------

  BorderSurface {
    id: card
    x: root.cardOrigin.x
    y: root.cardOrigin.y
    width: root.contentWidth
    height: root.contentHeight
    color: Color.popups.background
    borderSpec: root.borderSpec
    padding: root.padding
    radius: Style.cornerRadius
    opacity: root.open || root.popoutSwitching ? 1.0 : 0

    // Offset from the resting position, animated to zero on open. Kept as a
    // transform so it never fights the x/y bindings on cardOrigin.
    property real slideX: 0
    property real slideY: 0
    property real originScale: 1

    // Scale about the card's own centre first, then translate that centre onto
    // the button. Listed order is application order, so reversing these two
    // would scale the offset as well and the card would miss the button.
    transform: [
      Scale {
        origin.x: card.width / 2
        origin.y: card.height / 2
        xScale: card.originScale
        yScale: card.originScale
      },
      Translate { x: card.slideX; y: card.slideY }
    ]

    // Slightly shorter than the motion, and eased so it is essentially opaque
    // by the time the card is most of the way home. A fade that finishes long
    // before the movement does is what makes the panel look like it pops and
    // then slides.
    Behavior on opacity {
      enabled: !root.popoutSwitching && !root.popoutSwitchClosing
      // Asymmetric on purpose: `open` is already false by the time this is
      // evaluated for a close, so the shorter close duration applies there.
      NumberAnimation { duration: root.open ? root.fadeDuration : root.closeFadeDuration; easing.type: Easing.OutQuad }
    }

    // Swallow clicks on the card so they don't bubble to the dismissal
    // MouseArea behind us.
    MouseArea {
      anchors.fill: parent
      acceptedButtons: Qt.AllButtons
    }

    Item {
      id: contentHolder
      anchors.fill: parent
      anchors.topMargin: card.contentTopInset
      anchors.rightMargin: card.contentRightInset
      anchors.bottomMargin: card.contentBottomInset
      anchors.leftMargin: card.contentLeftInset
      opacity: root.popoutSwitching ? (root.open ? 1.0 : 0) : 1.0

      Behavior on opacity {
        enabled: root.popoutSwitching
        NumberAnimation { duration: 140; easing.type: Easing.OutCubic }
      }
    }
  }
}
