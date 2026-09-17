import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.Pam
import Quickshell.Wayland
import qs.Commons

Item {
  id: root

  property var shell: null
  property string omarchyPath: ""

  readonly property string home: Quickshell.env("HOME")
  readonly property string stateHome: home + "/.local/state"
  readonly property string userName: Quickshell.env("USER") || Quickshell.env("LOGNAME")
  readonly property string currentBackgroundLink: stateHome + "/omarchy/current/background"

  property bool lockRequested: false
  property bool pendingSessionLock: false
  property bool authenticatingPassword: false
  property bool fingerprintAuthenticating: false
  property bool passwordPamConfigured: false
  property bool fingerprintConfigured: false
  property bool previewVisible: false
  property string enteredPassword: ""
  property string pendingPassword: ""
  property string failureMessage: ""
  property int failedAttempts: 0
  property string backgroundPath: ""
  property int backgroundVersion: 0
  property string lastEvent: "init"
  property string lastEventAt: ""
  property bool displaysBlank: false
  // displaysBlank tracks what the lock asked for; Hyprland reports what each
  // panel actually did. While a video is on show the two are reconciled, so a
  // blank that failed keeps playing and a panel woken behind the lock's back
  // (a resume that kept the same outputs) resumes instead of freezing.
  property var monitorDpms: ({})
  property bool monitorDpmsKnown: false
  readonly property bool videoBackground: Util.isVideoPath(backgroundPath)
  property bool strandedLock: false
  property bool strandedLockResolved: false

  property bool faceScanning: fingerprintAuthenticating && fingerprintPam.active && faceConfigured && !lockdownMode
  property bool faceDelayActive: false
  property bool faceMatched: false
  property bool faceRejected: false
  property bool faceConfigured: false
  property bool lockdownMode: false
  property int totalFailedAttempts: 0
  property int intruderSnapshotsCaptured: 0
  property int faceUnlockDelayMs: 4000
  property bool laptopClosed: false
  property int faceAttemptCount: 0
  readonly property int faceMaxAttempts: 2
  property bool facePaused: faceAttemptCount >= faceMaxAttempts

  readonly property bool locked: lockRequested || sessionLock.locked || sessionLock.secure
  readonly property bool authenticating: authenticatingPassword || fingerprintAuthenticating
  readonly property var batteryService: shell && shell.services ? shell.firstPartyServiceFor("omarchy.battery") : null
  readonly property bool powerSaverActive: batteryService ? batteryService.powerSaverOnBattery : false

  function realScreenCount() {
    var screens = Quickshell.screens || []
    var count = 0

    for (var i = 0; i < screens.length; i++) {
      var screen = screens[i]
      if (screen && screen.name && screen.width > 0 && screen.height > 0) count += 1
    }

    return count
  }

  function hasRealScreen() {
    return realScreenCount() > 0
  }

  function queueSessionLock() {
    pendingSessionLock = true
    if (!sessionLockStabilizeTimer.running) logEvent("lock-pending: screen-stabilizing")
    sessionLockStabilizeTimer.restart()
    if (!pendingSessionLockTimer.running) pendingSessionLockTimer.start()
  }

  function requestSessionLock() {
    if (!lockRequested || sessionLock.locked || sessionLock.secure) return
    if (sessionLockStabilizeTimer.running) return

    if (!hasRealScreen()) {
      if (!pendingSessionLock || lastEvent !== "lock-pending: no-real-screen") logEvent("lock-pending: no-real-screen")
      pendingSessionLock = true
      if (!pendingSessionLockTimer.running) pendingSessionLockTimer.start()
      return
    }

    pendingSessionLock = false
    pendingSessionLockTimer.stop()
    sessionLock.locked = true
  }

  // ext-session-lock outlives its client, and a restart carries no lock over, so
  // a session locked this early is an orphan behind Hyprland's failsafe. Outputs
  // are often still absent here, so ask until the answer means something.
  function checkStrandedLock() {
    if (strandedLockResolved || strandedLockCheckProc.running) return

    // A lock this shell took is nobody's orphan.
    if (locked || lockRequested) {
      strandedLockResolved = true
      return
    }

    strandedLockCheckProc.running = true
  }

  function recoverStrandedLock() {
    if (!strandedLock || locked || !passwordPamConfigured) return

    strandedLock = false
    logEvent("lock-stranded: recovering")
    beginLock()
  }

  function refreshBackground() {
    if (!readlinkProc.running) readlinkProc.running = true
  }

  function refreshFingerprintStatus() {
    if (!fingerprintCheckProc.running) fingerprintCheckProc.running = true
  }

  function logEvent(event) {
    lastEvent = event
    lastEventAt = new Date().toISOString()
    console.log("omarchy lock " + lastEventAt + " " + event)
  }

  function resetAuthenticationState() {
    enteredPassword = ""
    pendingPassword = ""
    failureMessage = ""
    failedAttempts = 0
    authenticatingPassword = false
    fingerprintAuthenticating = false
    fingerprintRetryTimer.stop()
    initialFaceDelayTimer.stop()
    faceSuccessTimer.stop()
    faceDelayActive = false
    faceMatched = false
    faceRejected = false
    faceRejectTimer.stop()
    faceAttemptCount = 0
    if (passwordPam.active) passwordPam.abort()
    if (fingerprintPam.active) fingerprintPam.abort()
  }

  function beginLock() {
    if (!passwordPamConfigured) {
      logEvent("lock-denied: missing-pam")
      return false
    }

    if (!delayReadProc.running) delayReadProc.running = true
    if (!laptopClosedProc.running) laptopClosedProc.running = true
    resetAuthenticationState()
    lockRequested = true
    armBlankTimer()
    logEvent("lock-requested")
    queueSessionLock()

    Qt.callLater(function() {
      root.refreshBackground()
      root.refreshFingerprintStatus()
    })

    return true
  }

  function finishUnlock() {
    if (!root.locked && !lockRequested) return

    if (intruderSnapshotsCaptured > 0) {
      if (!intruderAlertProc.running) intruderAlertProc.running = true
    }

    lockRequested = false
    pendingSessionLock = false
    sessionLockStabilizeTimer.stop()
    pendingSessionLockTimer.stop()
    resetAuthenticationState()
    idleBlankTimer.stop()
    sessionLock.locked = false
    totalFailedAttempts = 0
    intruderSnapshotsCaptured = 0
    lockdownMode = false
    faceRejected = false
    logEvent("unlocked")
    runWake()
  }

  function armBlankTimer() {
    idleBlankTimer.armedAt = Date.now()
    idleBlankTimer.restart()
  }

  function runWake() {
    root.displaysBlank = false
    root.monitorDpmsKnown = false
    if (!wakeProcess.running) wakeProcess.running = true
    if (lockRequested) armBlankTimer()
  }

  function runBlank() {
    root.displaysBlank = true
    root.monitorDpmsKnown = false
    if (!blankProcess.running) blankProcess.running = true
  }

  function screenBlank(screenName) {
    var name = String(screenName || "")
    if (!monitorDpmsKnown || !(name in monitorDpms)) return displaysBlank
    return !monitorDpms[name]
  }

  function applyMonitorDpms(text) {
    var monitors
    try {
      monitors = JSON.parse(String(text || ""))
    } catch (error) {
      return
    }
    if (!Array.isArray(monitors)) return

    var dpms = {}
    for (var i = 0; i < monitors.length; i++) {
      var monitor = monitors[i]
      if (monitor && monitor.name && !monitor.disabled) dpms[String(monitor.name)] = !!monitor.dpmsStatus
    }
    monitorDpms = dpms
    monitorDpmsKnown = true
  }

  function submitPassword(value) {
    var password = String(value || "")
    if (!lockRequested || authenticatingPassword || password.length === 0) return

    runWake()
    pendingPassword = password
    failureMessage = ""
    authenticatingPassword = true

    if (!passwordPam.start()) {
      handlePasswordFailure()
      return
    }

    Qt.callLater(respondToPasswordPrompt)
  }

  function respondToPasswordPrompt() {
    if (!authenticatingPassword || !passwordPam.active || !passwordPam.responseRequired) return
    passwordPam.respond(pendingPassword)
  }

  function handlePasswordFailure() {
    if (!lockRequested) return

    authenticatingPassword = false
    enteredPassword = ""
    pendingPassword = ""
    failedAttempts += 1
    totalFailedAttempts += 1
    if (totalFailedAttempts >= 3) {
      if (!intruderSnapshotProc.running) {
        intruderSnapshotProc.running = true
        intruderSnapshotsCaptured += 1
      }
    }
    failureMessage = "Authentication failed (" + failedAttempts + ")"
    runWake()
  }

  function startFingerprint() {
    if (!lockRequested || !sessionLock.secure || (!fingerprintConfigured && !faceConfigured) || laptopClosed || lockdownMode) return
    if (fingerprintPam.active || fingerprintAuthenticating) return

    fingerprintAuthenticating = true
    if (!fingerprintPam.start()) {
      fingerprintAuthenticating = false
    }
  }

  function handleFingerprintFinished(result) {
    fingerprintAuthenticating = false

    if (!lockRequested) return
    if (result === PamResult.Success) {
      faceMatched = true
      faceRejected = false
      faceAttemptCount = 0
      if (faceConfigured && !chimeProc.running) chimeProc.running = true
      faceSuccessTimer.restart()
    } else if (fingerprintConfigured || faceConfigured) {
      faceRejected = true
      faceRejectTimer.restart()
      if (faceConfigured) {
        lockView.triggerHeadShake()
        if (!rejectChimeProc.running) rejectChimeProc.running = true
      }
      faceAttemptCount += 1
      totalFailedAttempts += 1
      if (totalFailedAttempts >= 3) {
        if (!intruderSnapshotProc.running) {
          intruderSnapshotProc.running = true
          intruderSnapshotsCaptured += 1
        }
      }
      if (faceAttemptCount < faceMaxAttempts && !laptopClosed) {
        fingerprintRetryTimer.restart()
      } else {
        fingerprintRetryTimer.stop()
      }
    }
  }

  function requestFaceRescan() {
    if (!lockRequested || !sessionLock.secure || (!fingerprintConfigured && !faceConfigured) || laptopClosed || lockdownMode) return
    faceAttemptCount = 0
    faceDelayActive = false
    faceRejected = false
    faceRejectTimer.stop()
    if (!laptopClosedProc.running) laptopClosedProc.running = true
    startFingerprint()
  }

  WlSessionLock {
    id: sessionLock

    locked: false

    onSecureStateChanged: {
      root.logEvent("secure=" + secure)
      if (secure) {
        root.pendingSessionLock = false
        sessionLockStabilizeTimer.stop()
        pendingSessionLockTimer.stop()
        if (root.lockdownMode) {
          root.faceDelayActive = false
        } else if (root.faceConfigured && root.faceUnlockDelayMs > 0) {
          root.faceDelayActive = true
          initialFaceDelayTimer.interval = root.faceUnlockDelayMs
          initialFaceDelayTimer.restart()
        } else {
          root.faceDelayActive = false
          root.startFingerprint()
        }
      }
    }

    onLockStateChanged: {
      root.logEvent("session-locked=" + locked)

      if (locked) {
        root.pendingSessionLock = false
        sessionLockStabilizeTimer.stop()
        pendingSessionLockTimer.stop()
      }

      if (!locked && root.lockRequested) {
        root.lockRequested = false
        root.pendingSessionLock = false
        sessionLockStabilizeTimer.stop()
        pendingSessionLockTimer.stop()
        root.resetAuthenticationState()
        root.runWake()
      }
    }

    WlSessionLockSurface {
      id: lockSurface
      color: Color.background

      LockView {
        id: lockView
        anchors.fill: parent
        backgroundPath: root.backgroundPath
        backgroundVersion: root.backgroundVersion
        fingerprintConfigured: root.fingerprintConfigured
        faceConfigured: root.faceConfigured
        faceScanning: root.faceScanning
        faceDelayActive: root.faceDelayActive
        faceMatched: root.faceMatched
        faceRejected: root.faceRejected
        facePaused: root.facePaused
        lockdownMode: root.lockdownMode
        authenticatingPassword: root.authenticatingPassword
        failureMessage: root.failureMessage
        failedAttempts: root.failedAttempts
        inputEnabled: root.lockRequested
        loadBackground: root.locked
        displaysBlank: root.screenBlank(lockSurface.screen ? lockSurface.screen.name : "")
        powerSaverActive: root.powerSaverActive
        passwordText: root.enteredPassword
        onPasswordTextEdited: function(password) { root.enteredPassword = password }
        onSubmitPassword: function(password) { root.submitPassword(password) }
        onRescanRequested: root.requestFaceRescan()
        onClearFailureRequested: root.failureMessage = ""
        onWakeRequested: root.runWake()
      }

    }
  }

  PanelWindow {
    id: previewWindow
    visible: root.previewVisible
    anchors { top: true; bottom: true; left: true; right: true }
    color: "transparent"
    WlrLayershell.namespace: "omarchy-lock-preview"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive
    exclusionMode: ExclusionMode.Ignore

    LockView {
      anchors.fill: parent
      backgroundPath: root.backgroundPath
      backgroundVersion: root.backgroundVersion
      fingerprintConfigured: root.fingerprintConfigured
      faceConfigured: root.faceConfigured
      faceScanning: false
      faceDelayActive: false
      faceMatched: false
      faceRejected: false
      facePaused: false
      lockdownMode: false
      authenticatingPassword: false
      failureMessage: ""
      failedAttempts: 0
      inputEnabled: false
      loadBackground: root.previewVisible
      powerSaverActive: root.powerSaverActive
      passwordText: ""
    }

    MouseArea {
      anchors.fill: parent
      acceptedButtons: Qt.LeftButton | Qt.RightButton
      onClicked: root.previewVisible = false
    }
  }

  PamContext {
    id: passwordPam
    config: "omarchy-lock-password"
    user: root.userName

    onResponseRequiredChanged: root.respondToPasswordPrompt()
    onPamMessage: root.respondToPasswordPrompt()

    onCompleted: function(result) {
      root.authenticatingPassword = false
      root.pendingPassword = ""

      if (!root.lockRequested) return
      if (result === PamResult.Success) root.finishUnlock()
      else root.handlePasswordFailure()
    }

    onError: function(error) {
      root.handlePasswordFailure()
    }
  }

  PamContext {
    id: fingerprintPam
    config: "omarchy-lock-fingerprint"
    user: root.userName

    onCompleted: function(result) {
      root.handleFingerprintFinished(result)
    }

    onError: function(error) {
      root.fingerprintAuthenticating = false
      if (root.lockRequested && root.fingerprintConfigured) fingerprintRetryTimer.restart()
    }
  }

  Timer {
    id: fingerprintRetryTimer
    interval: 250
    repeat: false
    onTriggered: root.startFingerprint()
  }

  Process {
    id: readlinkProc
    command: ["readlink", "-f", root.currentBackgroundLink]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var next = String(text || "").trim()
        if (next !== root.backgroundPath) {
          root.backgroundPath = next
          root.backgroundVersion += 1
        }
      }
    }
  }

  Timer {
    id: initialFaceDelayTimer
    interval: root.faceUnlockDelayMs
    repeat: false
    onTriggered: {
      root.faceDelayActive = false
      root.startFingerprint()
    }
  }

  Timer {
    id: faceSuccessTimer
    interval: 350
    repeat: false
    onTriggered: root.finishUnlock()
  }

  Process {
    id: laptopClosedProc
    command: ["bash", "-c", "omarchy-hw-laptop-closed && echo closed || echo open"]
    stdout: StdioCollector {
      id: laptopClosedStdout
      waitForEnd: true
    }
    onExited: {
      root.laptopClosed = String(laptopClosedStdout.text || "").trim() === "closed"
    }
  }

  Process {
    id: chimeProc
    command: ["bash", "-c", "if [[ -f \"$HOME/.config/omarchy/sounds/face-match.wav\" && \"$(cat \"$HOME/.config/omarchy/face-unlock-sound\" 2>/dev/null)\" != \"off\" ]]; then pw-play \"$HOME/.config/omarchy/sounds/face-match.wav\" >/dev/null 2>&1; fi"]
  }

  Timer {
    id: faceRejectTimer
    interval: 2000
    repeat: false
    onTriggered: root.faceRejected = false
  }

  Process {
    id: rejectChimeProc
    command: ["bash", "-c", "if [[ -f \"$HOME/.config/omarchy/sounds/face-reject.wav\" && \"$(cat \"$HOME/.config/omarchy/face-unlock-sound\" 2>/dev/null)\" != \"off\" ]]; then pw-play \"$HOME/.config/omarchy/sounds/face-reject.wav\" >/dev/null 2>&1; fi"]
  }

  Process {
    id: intruderSnapshotProc
    command: ["bash", "-c", "mkdir -p \"$HOME/.local/state/omarchy/intruder-snapshots\"; ffmpeg -y -f v4l2 -i /dev/video0 -frames:v 1 -update 1 \"$HOME/.local/state/omarchy/intruder-snapshots/intruder-$(date +%Y%m%d-%H%M%S).jpg\" >/dev/null 2>&1 || true"]
  }

  Process {
    id: intruderAlertProc
    command: ["bash", "-c", "LATEST=$(ls -t \"$HOME/.local/state/omarchy/intruder-snapshots/\"*.jpg 2>/dev/null | head -n 1); COUNT=$(ls \"$HOME/.local/state/omarchy/intruder-snapshots/\"*.jpg 2>/dev/null | wc -l); notify-send -u critical -i \"${LATEST:-security-high}\" \"Security Alert\" \"$COUNT failed unlock attempt(s) detected while locked.\nSnapshots saved to ~/.local/state/omarchy/intruder-snapshots/\""]
  }

  Process {
    id: delayReadProc
    command: ["bash", "-c", "cat \"$HOME/.config/omarchy/face-unlock-delay\" 2>/dev/null || echo 4"]
    stdout: StdioCollector {
      id: delayReadStdout
      waitForEnd: true
    }
    onExited: {
      var n = parseInt(String(delayReadStdout.text || "").trim())
      if (!isNaN(n) && n >= 0) {
        root.faceUnlockDelayMs = n * 1000
      }
    }
  }

  Process {
    id: fingerprintCheckProc
    command: ["bash", "-c", "has_fp=no; has_face=no; if [[ -f /etc/pam.d/omarchy-lock-fingerprint ]]; then if command -v fprintd-list >/dev/null 2>&1 && fprintd-list \"$USER\" 2>/dev/null | grep -qi finger; then has_fp=yes; fi; if grep -q pam_howdy /etc/pam.d/omarchy-lock-fingerprint 2>/dev/null || (command -v howdy >/dev/null 2>&1 && howdy list 2>/dev/null | grep -q '^[0-9]'); then has_face=yes; fi; fi; echo \"$has_fp $has_face\""]
    stdout: StdioCollector { id: fingerprintCheckStdout; waitForEnd: true }
    onExited: {
      var parts = String(fingerprintCheckStdout.text || "").trim().split(/\s+/)
      root.fingerprintConfigured = parts[0] === "yes"
      root.faceConfigured = parts[1] === "yes"
      var biometricsActive = root.fingerprintConfigured || root.faceConfigured
      if (root.lockRequested && biometricsActive && !root.faceDelayActive) root.startFingerprint()
      else if (!biometricsActive && fingerprintPam.active) fingerprintPam.abort()
    }
  }

  Process {
    id: strandedLockCheckProc
    command: ["bash", "-c", "omarchy-hyprland-session-locked"]
    onExited: function(exitCode) {
      // No output to read the lock off yet.
      if (exitCode === 2) return

      root.strandedLockResolved = true

      // A lock taken while this was in flight is this shell's own.
      root.strandedLock = exitCode === 0 && !root.locked && !root.lockRequested
      root.recoverStrandedLock()
    }
  }

  Process {
    id: wakeProcess
    command: ["bash", "-c", "omarchy-system-wake"]
  }

  Process {
    id: blankProcess
    command: ["bash", "-c", "omarchy-brightness-keyboard off; omarchy-brightness-display off"]
  }

  // Quickshell exposes no DPMS signal, so the panel state is polled while a
  // video is the locked wallpaper. A wake or blank request drops the last
  // answer, so its optimistic state applies until the next poll confirms it.
  Process {
    id: monitorDpmsProcess
    command: ["hyprctl", "monitors", "-j"]
    stdout: StdioCollector {
      onStreamFinished: root.applyMonitorDpms(text)
    }
  }

  Timer {
    id: monitorDpmsTimer
    interval: 3000
    repeat: true
    triggeredOnStart: true
    running: root.locked && root.videoBackground
    onTriggered: {
      if (!monitorDpmsProcess.running) monitorDpmsProcess.running = true
    }
    onRunningChanged: {
      if (!running) root.monitorDpmsKnown = false
    }
  }

  Timer {
    id: idleBlankTimer
    interval: 5000
    repeat: false
    property double armedAt: 0
    onTriggered: {
      // A countdown frozen by suspend fires right after resume, which would
      // blank the freshly woken unlock screen under the user. Wall-clock time
      // exposes the gap: take a fresh run-up instead of blanking.
      if (Date.now() - armedAt > interval + 2000) {
        root.armBlankTimer()
        return
      }
      // Only a password check in flight should hold the display up. The
      // fingerprint PAM stays armed for the whole lock, so gating on
      // `authenticating` here would keep the panel lit until unlock.
      if (root.lockRequested && !root.authenticatingPassword) root.runBlank()
    }
  }

  Timer {
    id: sessionLockStabilizeTimer
    interval: 500
    repeat: false
    onTriggered: root.requestSessionLock()
  }

  Timer {
    id: pendingSessionLockTimer
    interval: 100
    repeat: true
    onTriggered: root.requestSessionLock()
  }

  Timer {
    id: strandedLockRetryTimer
    interval: 500
    repeat: true
    // Covers the compositor settling; screens coming back re-arm it.
    readonly property int budget: 20
    property int remaining: 20
    running: !root.strandedLockResolved && remaining > 0

    function rearm() {
      if (!root.strandedLockResolved) remaining = budget
    }

    onTriggered: {
      remaining -= 1
      root.checkStrandedLock()
    }
  }

  Connections {
    target: Quickshell
    function onScreensChanged() {
      // A panel coming back is a display turning on that runWake did not ask
      // for, so the blank state has to be given up here or a visible lock
      // wallpaper stays frozen until the next keypress.
      root.displaysBlank = false
      root.requestSessionLock()

      // A monitor still coming up has no workspace, so cannot answer yet.
      strandedLockRetryTimer.rearm()
      root.checkStrandedLock()
    }
  }

  onAuthenticatingPasswordChanged: {
    if (!lockRequested) return
    if (authenticatingPassword) idleBlankTimer.stop()
    else armBlankTimer()
  }

  FileView {
    path: "/etc/pam.d/omarchy-lock-password"
    watchChanges: true
    printErrors: false
    onLoaded: root.passwordPamConfigured = true
    onLoadFailed: root.passwordPamConfigured = false
    onFileChanged: reload()
  }

  // No lock before PAM is known good. An answer from before then may be stale --
  // the failsafe can be cleared from a TTY -- so re-ask rather than act on it.
  onPasswordPamConfiguredChanged: {
    if (!passwordPamConfigured) return

    strandedLock = false
    strandedLockResolved = false
    strandedLockRetryTimer.rearm()
    checkStrandedLock()
  }

  Component.onCompleted: {
    refreshBackground()
    refreshFingerprintStatus()
    checkStrandedLock()
  }

  IpcHandler {
    target: "lock"

    function lock(): string {
      if (!root.passwordPamConfigured) return "missing-pam"
      if (!root.locked && !root.beginLock()) return "failed"
      return "ok"
    }

    function lockdown(): string {
      if (!root.passwordPamConfigured) return "missing-pam"
      root.lockdownMode = true
      if (!root.locked && !root.beginLock()) return "failed"
      return "ok"
    }

    function isLocked(): string {
      return root.locked ? "true" : "false"
    }

    function status(): string {
      return JSON.stringify({
        locked: root.locked,
        requested: root.lockRequested,
        pending: root.pendingSessionLock,
        sessionLocked: sessionLock.locked,
        secure: sessionLock.secure,
        realScreens: root.realScreenCount(),
        passwordPam: root.passwordPamConfigured,
        fingerprint: root.fingerprintConfigured,
        authenticating: root.authenticating,
        lastEvent: root.lastEvent,
        lastEventAt: root.lastEventAt
      })
    }

    function preview(): string {
      root.refreshBackground()
      root.refreshFingerprintStatus()
      root.previewVisible = true
      return "ok"
    }

    function hidePreview(): string {
      root.previewVisible = false
      return "ok"
    }
  }
}
