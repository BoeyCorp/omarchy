import QtQuick
import Quickshell
import qs.Commons

ShellRoot {
  id: root

  readonly property string resultPath: Quickshell.env("OMARCHY_QML_TEST_RESULT")
  readonly property string rootPath: Quickshell.env("OMARCHY_PATH")
  property var failures: []

  function fail(message) {
    failures.push(String(message))
  }

  function assertTrue(condition, message) {
    if (!condition) fail(message)
  }

  function shellQuote(value) {
    return "'" + String(value).replace(/'/g, "'\\''") + "'"
  }

  function writeResult() {
    var payload = JSON.stringify({
      ok: failures.length === 0,
      failures: failures
    })

    if (resultPath) {
      Quickshell.execDetached(["bash", "-lc", "printf '%s' " + shellQuote(payload) + " > " + shellQuote(resultPath)])
    }
  }

  Item { id: host; width: 800; height: 600 }

  Timer {
    interval: 1
    running: true
    repeat: false
    onTriggered: {
      try {
        var component = Qt.createComponent("file://" + root.rootPath + "/shell/plugins/lock/LockView.qml", Component.PreferSynchronous)
        if (component.status !== Component.Ready) {
          root.fail("LockView failed to load: " + component.errorString())
          return
        }

        var view = component.createObject(host, { width: 800, height: 600, loadBackground: false })
        if (!view) {
          root.fail("LockView failed to instantiate: " + component.errorString())
          return
        }

        var faceIndicator = view.children ? findByObjectName(view, "faceIndicator") : null
        root.assertTrue(faceIndicator !== null, "face indicator exists in the lock view")

        if (faceIndicator) {
          view.faceConfigured = false
          root.assertTrue(!faceIndicator.visible, "face indicator is hidden when face is not configured")

          view.faceConfigured = true
          root.assertTrue(faceIndicator.visible, "face indicator is shown when face is configured")

          view.faceScanning = false
          var laser = findByObjectName(faceIndicator, "scanLaser")
          root.assertTrue(laser !== null, "scan laser exists in face badge")
          if (laser) {
            root.assertTrue(!laser.visible, "scan laser is hidden when not scanning")
            view.faceScanning = true
            root.assertTrue(laser.visible, "scan laser is visible during face scanning")
          }

          view.faceMatched = true
          var faceIcon = findByObjectName(faceIndicator, "faceIconText")
          root.assertTrue(faceIcon !== null, "face icon text exists")
          if (faceIcon) {
            root.assertTrue(faceIcon.text === "󰄬", "face icon switches to checkmark on match")
          }
        }

        view.destroy()
      } catch (error) {
        root.fail("lock face indicator fixture threw: " + error)
      } finally {
        root.writeResult()
      }
    }
  }

  function findByObjectName(node, name) {
    if (!node) return null
    if (node.objectName === name) return node
    var kids = node.children || []
    for (var i = 0; i < kids.length; i++) {
      var found = findByObjectName(kids[i], name)
      if (found) return found
    }
    return null
  }
}
