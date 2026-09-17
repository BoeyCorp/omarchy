import QtQuick
import QtQuick.Effects
import qs.Commons
import qs.Ui

Item {
  id: root

  property string backgroundPath: ""
  property int backgroundVersion: 0
  property bool fingerprintConfigured: false
  property bool faceConfigured: false
  property bool faceScanning: false
  property bool faceDelayActive: false
  property bool faceMatched: false
  property bool facePaused: false
  property bool authenticatingPassword: false
  property string failureMessage: ""
  property int failedAttempts: 0
  property bool inputEnabled: true
  property bool loadBackground: true
  // A locked session blanks the displays after a few seconds. Nothing is
  // visible from then until the user wakes it, so a video must not keep
  // decoding through what is usually the longest part of a lock.
  property bool displaysBlank: false
  property bool powerSaverActive: false
  property string passwordText: ""
  property bool syncingPasswordText: false

  readonly property string placeholderText: "Enter Password"
  readonly property int fieldWidth: 381
  readonly property int fieldHeight: 67
  readonly property int outlineThickness: 3
  readonly property int fieldFontSize: Math.round(Style.font.heading * 1.125)
  readonly property int passwordDotFontSize: Math.round(Style.font.heading * 1.33)
  readonly property int passwordDotLetterSpacing: Math.round(Style.font.heading * 0.19)
  // Space to keep clear on each side of the field for the fingerprint icon
  // (icon width plus a gap) so the centered dots never run under it.
  readonly property real fingerprintReserve: (fingerprintConfigured || faceConfigured) ? Math.round(fingerprintIcon.implicitWidth + 12) : 0
  // Shrink the dots to fit once the password outgrows the field, so every
  // keystroke stays visible — otherwise long passwords clip with no feedback.
  readonly property real passwordDotScale: dotMetrics.advanceWidth > 0
    ? Math.min(1, (passwordInput.width - 4) / dotMetrics.advanceWidth)
    : 1
  readonly property bool showPasswordCursor: inputEnabled && !authenticatingPassword && failureMessage.length === 0
  readonly property bool errorState: failureMessage.length > 0
  readonly property var inputBorderSpec: errorState
    ? Border.surfaceSpec("lock", "border-error", Color.lock.borderError, root.outlineThickness, "border-alpha")
    : Border.surfaceSpec("lock", "border-active", Color.lock.borderActive, root.outlineThickness, "border-alpha")

  signal submitPassword(string password)
  signal passwordTextEdited(string password)
  signal rescanRequested()
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

    BackgroundMedia {
      id: wallpaper
      anchors.fill: parent
      path: root.loadBackground ? root.backgroundPath : ""
      version: root.backgroundVersion
      playbackEnabled: root.loadBackground && !root.displaysBlank && !root.powerSaverActive
    }

    MultiEffect {
      anchors.fill: wallpaper
      source: wallpaper.video ? null : wallpaper
      visible: !wallpaper.video
      autoPaddingEnabled: false
      blurEnabled: root.loadBackground && wallpaper.ready
      blur: 1.0
      blurMax: 128
      blurMultiplier: 1.25
      contrast: -0.08
    }

    // Qt's video output cannot be sampled by MultiEffect on every renderer.
    // Keep video wallpapers visible and darken them slightly for legibility.
    Rectangle {
      anchors.fill: wallpaper
      visible: wallpaper.video
      color: "#22000000"
    }

    MouseArea {
      anchors.fill: parent
      hoverEnabled: true
      onClicked: { root.wakeRequested(); root.forcePasswordFocus() }
      onPositionChanged: root.wakeRequested()
    }

    Item {
      id: faceIndicator
      objectName: "faceIndicator"
      width: 72
      height: 72
      anchors.bottom: inputField.top
      anchors.bottomMargin: 28
      anchors.horizontalCenter: parent.horizontalCenter
      visible: root.faceConfigured

      // Pulsing outer radar waves while scanning
      Rectangle {
        id: pulseWave1
        width: 72
        height: 72
        radius: 36
        anchors.centerIn: faceBadge
        color: "transparent"
        border.color: Color.accent
        border.width: 1.5
        opacity: 0
        scale: 1.0
        visible: root.faceScanning

        ParallelAnimation {
          id: pulseAnim1
          running: root.faceScanning
          loops: Animation.Infinite
          NumberAnimation { target: pulseWave1; property: "scale"; from: 0.95; to: 1.55; duration: 1200; easing.type: Easing.OutQuad }
          NumberAnimation { target: pulseWave1; property: "opacity"; from: 0.7; to: 0; duration: 1200; easing.type: Easing.OutQuad }
        }
      }

      Rectangle {
        id: pulseWave2
        width: 72
        height: 72
        radius: 36
        anchors.centerIn: faceBadge
        color: "transparent"
        border.color: Color.accent
        border.width: 1.5
        opacity: 0
        scale: 1.0
        visible: root.faceScanning

        SequentialAnimation {
          running: root.faceScanning
          loops: Animation.Infinite
          PauseAnimation { duration: 600 }
          ParallelAnimation {
            NumberAnimation { target: pulseWave2; property: "scale"; from: 0.95; to: 1.55; duration: 1200; easing.type: Easing.OutQuad }
            NumberAnimation { target: pulseWave2; property: "opacity"; from: 0.7; to: 0; duration: 1200; easing.type: Easing.OutQuad }
          }
        }
      }

      // Central Face Badge
      Rectangle {
        id: faceBadge
        width: 64
        height: 64
        radius: 32
        anchors.centerIn: parent
        color: Color.lock.background
        clip: true
        border.width: 2
        border.color: root.faceMatched ? "#50fa7b" : (root.faceScanning ? Color.accent : (root.errorState ? Color.lock.borderError : Color.lock.border))

        Behavior on border.color {
          ColorAnimation { duration: 250 }
        }

        // Animated laser sweep line moving up and down across the face
        Rectangle {
          id: scanLaser
          objectName: "scanLaser"
          width: parent.width
          height: 2
          color: Color.accent
          opacity: 0.8
          anchors.horizontalCenter: parent.horizontalCenter
          visible: root.faceScanning

          SequentialAnimation {
            id: scanLaserAnim
            running: root.faceScanning
            loops: Animation.Infinite
            NumberAnimation { target: scanLaser; property: "y"; from: 4; to: 58; duration: 900; easing.type: Easing.InOutQuad }
            NumberAnimation { target: scanLaser; property: "y"; from: 58; to: 4; duration: 900; easing.type: Easing.InOutQuad }
          }
        }

        Text {
          id: faceIconText
          objectName: "faceIconText"
          anchors.centerIn: parent
          text: root.faceMatched ? "󰄬" : "\uf118"
          font.family: Style.font.family
          font.pixelSize: 28
          color: root.faceMatched ? "#50fa7b" : (root.faceScanning ? Color.accent : Color.lock.placeholder)

          Behavior on color {
            ColorAnimation { duration: 200 }
          }

          SequentialAnimation {
            id: breatheAnim
            running: root.faceScanning
            loops: Animation.Infinite
            NumberAnimation { target: faceIconText; property: "scale"; from: 1.0; to: 1.12; duration: 700; easing.type: Easing.InOutQuad }
            NumberAnimation { target: faceIconText; property: "scale"; from: 1.12; to: 1.0; duration: 700; easing.type: Easing.InOutQuad }
          }
        }
      }

      // Dynamic Status Label below face badge
      Text {
        id: faceStatusLabel
        anchors.top: faceBadge.bottom
        anchors.topMargin: 8
        anchors.horizontalCenter: faceBadge.horizontalCenter
        font.family: Style.font.family
        font.pixelSize: Math.round(Style.font.body * 0.85)
        color: root.faceMatched ? "#50fa7b" : (root.faceScanning ? Color.accent : Color.lock.placeholder)
        text: {
          if (root.faceMatched) return "Face recognized"
          if (root.faceScanning) return "Looking for you" + dotString
          if (root.faceDelayActive) return "Waiting to scan…"
          if (root.facePaused) return "Face scan paused — press Enter to scan"
          return ""
        }
        visible: text.length > 0

        property string dotString: "…"
        Timer {
          interval: 400
          repeat: true
          running: root.faceScanning
          onTriggered: {
            if (faceStatusLabel.dotString === "…") faceStatusLabel.dotString = ""
            else if (faceStatusLabel.dotString === "") faceStatusLabel.dotString = "·"
            else if (faceStatusLabel.dotString === "·") faceStatusLabel.dotString = "··"
            else faceStatusLabel.dotString = "…"
          }
        }
      }
    }

    BorderSurface {
      id: inputField
      width: root.fieldWidth
      height: root.fieldHeight
      anchors.centerIn: parent
      color: Color.lock.background
      borderSpec: root.inputBorderSpec
      radius: Style.cornerRadius
      clip: true

      TextInput {
        id: passwordInput
        anchors.fill: parent
        anchors.topMargin: inputField.borderTop
        // Reserve the fingerprint icon's width on both sides so the centered
        // dots stay symmetric and never slide under the icon as they grow.
        anchors.rightMargin: inputField.borderRight + 18 + root.fingerprintReserve
        anchors.bottomMargin: inputField.borderBottom
        anchors.leftMargin: inputField.borderLeft + 18 + root.fingerprintReserve
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
          else root.rescanRequested()
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
        text: {
          if (root.authenticatingPassword) return "Checking…"
          if (root.failureMessage.length > 0) return root.failureMessage
          if (root.faceMatched) return "Face recognized"
          if (root.faceScanning) return "Looking for you…"
          if (root.facePaused) return "Press Enter to scan face"
          return root.placeholderText
        }
        visible: passwordInput.text.length === 0
        color: root.authenticatingPassword ? Color.lock.text : (root.failureMessage.length > 0 ? Color.lock.textError : (root.faceScanning ? Color.accent : Color.lock.placeholder))
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
        anchors.right: parent.right
        anchors.rightMargin: inputField.borderRight + 18
        anchors.verticalCenter: parent.verticalCenter
        visible: root.faceConfigured || root.fingerprintConfigured
        text: root.faceConfigured ? (root.faceMatched ? "󰄬" : "\uf118") : "󰈷"
        color: root.faceConfigured ? (root.faceMatched ? "#50fa7b" : (root.faceScanning ? Color.accent : Color.lock.placeholder)) : Color.lock.placeholder
        font.family: root.faceConfigured ? "JetBrainsMono Nerd Font" : Style.font.family
        font.pixelSize: Math.round(root.fieldFontSize * 1.1)
        horizontalAlignment: Text.AlignHCenter
        verticalAlignment: Text.AlignVCenter

        SequentialAnimation on opacity {
          running: root.faceScanning
          loops: Animation.Infinite
          NumberAnimation { from: 1.0; to: 0.35; duration: 750; easing.type: Easing.InOutSine }
          NumberAnimation { from: 0.35; to: 1.0; duration: 750; easing.type: Easing.InOutSine }
        }
      }
    }
  }
}
