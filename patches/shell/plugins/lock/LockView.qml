import QtQuick
import Quickshell
import Quickshell.Io
import QtQuick.Effects
import qs.Commons

Item {
  id: root

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
  // Set once authentication succeeds: the design plays its exit before the lock releases.
  property bool driving: false
  // True while the display is off.
  property bool blanked: false
  // Designs live outside the shell, a folder each; lock-design names the one shown.
  property string designs: Quickshell.env("HOME") + "/.local/share/omarchy-custom/lock/"
  property string design: chosen.text().trim() || "rally"

  readonly property string placeholderText: "Enter Password"
  readonly property int fieldWidth: 380
  readonly property int fieldHeight: 56
  // Room each side of the text, clear of the rounded ends.
  readonly property int fieldInset: 28
  readonly property int fieldFontSize: Style.font.heading
  readonly property int passwordDotFontSize: Math.round(Style.font.heading * 1.125)
  readonly property int passwordDotLetterSpacing: Math.round(Style.font.heading * 0.25)
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
  // The design's own light edges the field, white for designs without one.
  readonly property color edgeColor: errorState ? Color.lock.borderError : scene.item && scene.item.accent || "white"
  // Once the password is accepted the field clears quickly, ahead of the design's exit.
  property real fieldOpacity: driving ? 0 : 1
  Behavior on fieldOpacity { NumberAnimation { duration: 300; easing.type: Easing.OutQuad } }

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

  // A design is a Scene.qml given this view as its host; it may offer play(), hide() and leave().
  function showDesign() {
    scene.setSource("file://" + designs + design + "/Scene.qml", { host: root })
  }

  function tell(name) {
    if (scene.item && scene.item[name]) scene.item[name]()
  }

  onPasswordTextChanged: syncPasswordText()
  onInputEnabledChanged: {
    if (inputEnabled) Qt.callLater(forcePasswordFocus)
  }
  Component.onCompleted: {
    syncPasswordText()
    if (inputEnabled) Qt.callLater(forcePasswordFocus)
    showDesign()
  }
  // The first design loads on completion, once every property has its final value.
  onDesignChanged: if (scene.status !== Loader.Null) showDesign()
  onLoadBackgroundChanged: if (loadBackground) tell("play")
  onDrivingChanged: if (driving) tell("leave")
  onBlankedChanged: if (loadBackground && !driving) tell(blanked ? "hide" : "play")

  FileView {
    id: chosen
    path: Quickshell.env("HOME") + "/.config/omarchy-custom/lock-design"
    // Read at once, so the first design shown is the chosen one.
    blockLoading: true
    printErrors: false
    watchChanges: true
    onFileChanged: reload()
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

    // A design that fails to load leaves this plain background, and the field still unlocks.
    Loader {
      id: scene
      anchors.fill: parent
      onLoaded: if (root.loadBackground) root.tell("play")
    }

    MouseArea {
      anchors.fill: parent
      hoverEnabled: true
      onClicked: { root.wakeRequested(); root.forcePasswordFocus() }
      onPositionChanged: root.wakeRequested()
    }

    // The field is frosted glass over the design, edged in its light, which glows faintly around it.
    Rectangle {
      id: halo
      anchors.fill: inputField
      radius: inputField.radius
      color: "transparent"
      border.width: 3
      border.color: root.edgeColor
      visible: false
    }

    MultiEffect {
      anchors.fill: halo
      source: halo
      blurEnabled: true
      blur: 1
      blurMax: 24
      opacity: 0.55 * root.fieldOpacity
    }

    // The design behind the field, with a margin so the blur reaches past its edge.
    ShaderEffectSource {
      id: backdrop
      anchors.fill: inputField
      anchors.margins: -40
      sourceItem: scene
      sourceRect: Qt.rect(x, y, width, height)
      visible: false
    }

    Item {
      id: glassShape
      anchors.fill: backdrop
      visible: false
      layer.enabled: true
      Rectangle { anchors.fill: parent; anchors.margins: 40; radius: inputField.radius }
    }

    MultiEffect {
      anchors.fill: backdrop
      source: backdrop
      autoPaddingEnabled: false
      blurEnabled: true
      blur: 1
      blurMax: 40
      maskEnabled: true
      maskSource: glassShape
      opacity: root.fieldOpacity
    }

    Rectangle {
      id: inputField
      width: root.fieldWidth
      height: root.fieldHeight
      anchors.horizontalCenter: parent.horizontalCenter
      anchors.bottom: parent.bottom
      // Whole pixels keep the edge a sharp hairline.
      anchors.bottomMargin: Math.round(parent.height * 0.08)
      color: Qt.rgba(0.02, 0.03, 0.05, 0.5)
      border.width: 1
      border.color: root.edgeColor
      radius: height / 2
      clip: true
      opacity: root.fieldOpacity

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
        color: "white"
        selectionColor: Color.lock.selection
        selectedTextColor: Color.lock.text
        font.family: Style.font.family
        font.pixelSize: text.length > 0 ? Math.max(1, Math.floor(root.passwordDotFontSize * root.passwordDotScale)) : root.fieldFontSize
        font.letterSpacing: text.length > 0 ? root.passwordDotLetterSpacing * root.passwordDotScale : 0
        cursorVisible: activeFocus && root.showPasswordCursor && text.length > 0
        cursorDelegate: Rectangle {
          width: 2
          color: "white"
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
        text: root.authenticatingPassword || root.driving ? "Checking…" : (root.failureMessage.length > 0 ? root.failureMessage : root.placeholderText)
        visible: passwordInput.text.length === 0
        color: root.authenticatingPassword || root.driving ? "white" : (root.failureMessage.length > 0 ? Color.lock.textError : Qt.rgba(1, 1, 1, 0.62))
        font.family: Style.font.family
        font.pixelSize: root.fieldFontSize
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
        anchors.right: parent.right
        anchors.rightMargin: 22
        anchors.verticalCenter: parent.verticalCenter
        visible: root.fingerprintConfigured
        text: "󰈷"
        color: Qt.rgba(1, 1, 1, 0.62)
        font.family: Style.font.family
        font.pixelSize: Math.round(root.fieldFontSize * 1.1)
        horizontalAlignment: Text.AlignHCenter
        verticalAlignment: Text.AlignVCenter
      }
    }
  }
}
