// ~/.config/fajita/lock.qml on the phone. Spawned from the power menu (system
// lock row) or the idle timer; dismissed by swiping up (concept-shell lock).
//
// Why not Omarchy's session lock: it uses ext-session-lock, which covers every
// layer-shell surface — including squeekboard. The password field would need a
// hardware keyboard the phone does not have, so the session lock is a pocket
// brick. This is the phone lock instead: fullscreen top-layer overlay that
// shows the OMARCHY wordmark, a big clock and the latest notifications, and
// unlocks on swipe-up. It is a pocket guard, not PAM: see README "Lock screen".
//
// Run: quickshell -p ~/.config/fajita/lock.qml  ·  toggle:
// quickshell -p ~/.config/fajita/lock.qml ipc call fajita-lock toggle

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland

ShellRoot {
  id: root

  readonly property string home: Quickshell.env("HOME")
  readonly property string stateDir: home + "/.local/state/omarchy/"
  readonly property string backgroundPath: stateDir + "current/background"
  property bool open: true
  property var entries: [] // latest notifications, newest first
  property string clockText: ""
  property string dateText: ""

  IpcHandler {
    target: "fajita-lock"
    function toggle() { root.open = !root.open; if (!root.open) Qt.quit() }
  }

  Process {
    id: scan
    command: ["bash", "-lc",
      "ls -1t ~/.local/state/omarchy/notifications/history 2>/dev/null | head -3 | while read -r f; do " +
      "python3 -c 'import json,sys; d=json.load(open(sys.argv[1])); print((d.get(\"summary\") or d.get(\"body\") or \"\")[:60])' " +
      "\"$HOME/.local/state/omarchy/notifications/history/$f\" 2>/dev/null; done"]
    stdout: SplitParser {
      onRead: data => root.entries = root.entries.concat([data])
    }
    onExited: root.entries = root.entries.slice(0, 3)
  }

  Process {
    id: clocker
    command: ["bash", "-lc", "date '+%H:%M%n%a %e %b'"]
    stdout: StdioCollector {
      onStreamFinished: {
        var lines = text.trim().split("\n")
        root.clockText = lines[0] || ""
        root.dateText = lines[1] || ""
      }
    }
  }

  Timer {
    interval: 10000
    running: root.open
    repeat: true
    triggeredOnStart: true
    onTriggered: { clocker.running = true }
  }

  function rescan() {
    root.entries = []
    scan.running = true
  }

  Component.onCompleted: { rescan(); clocker.running = true }

  PanelWindow {
    id: win
    anchors { top: true; bottom: true; left: true; right: true }
    // A plain Top-layer surface loses to the bar/launcher/OSK (all later Top
    // surfaces) — they render above it AND take its touches, so the "lock"
    // would not lock. Overlay + exclusive keyboard sits over every layer-shell
    // surface and takes all input until the swipe releases it.
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.namespace: "fajita-lock"
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive
    exclusiveZone: -1 // cover the whole screen — the bars' reserved strips too
    color: "transparent"

    Rectangle {
      id: shade
      anchors.fill: parent
      color: "#000000"
      opacity: 0.86

      // Nudge the whole screen up with the swipe so unlock feels physical.
      // Transform, not y: a manual y would fight the anchors.fill binding.
      property real dragOffset: 0
      transform: Translate { y: -shade.dragOffset * 0.4 }

      Image {
        anchors.fill: parent
        source: root.backgroundPath ? "file://" + root.backgroundPath : ""
        fillMode: Image.PreserveAspectCrop
        opacity: 0.25
        visible: status === Image.Ready
      }

      Column {
        anchors.centerIn: parent
        spacing: 26

        Text {
          anchors.horizontalCenter: parent.horizontalCenter
          text: "OMARCHY"
          color: "#ffffff"
          opacity: 0.55
          font.family: "JetBrainsMono Nerd Font"
          font.pixelSize: 17
          font.letterSpacing: 9
        }

        Text {
          anchors.horizontalCenter: parent.horizontalCenter
          text: root.clockText
          color: "#ffffff"
          font.family: "JetBrainsMono Nerd Font"
          font.pixelSize: 88
          font.weight: Font.Light
        }

        Text {
          anchors.horizontalCenter: parent.horizontalCenter
          text: root.dateText
          color: "#ffffff"
          opacity: 0.7
          font.family: "JetBrainsMono Nerd Font"
          font.pixelSize: 19
        }
      }

      Column {
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: parent.bottom
        anchors.bottomMargin: 150
        spacing: 12

        Repeater {
          model: root.entries

          Rectangle {
            width: 470
            height: 46
            radius: 10
            color: "#20ffffff"

            Text {
              anchors.verticalCenter: parent.verticalCenter
              anchors.left: parent.left
              anchors.leftMargin: 14
              anchors.right: parent.right
              anchors.rightMargin: 14
              text: modelData
              color: "#ffffff"
              opacity: 0.9
              font.family: "JetBrainsMono Nerd Font"
              font.pixelSize: 14
              elide: Text.ElideRight
            }
          }
        }
      }

      Text {
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: parent.bottom
        anchors.bottomMargin: 64
        text: "swipe up to unlock"
        color: "#ffffff"
        opacity: 0.45 + shade.dragOffset / 400
        font.family: "JetBrainsMono Nerd Font"
        font.pixelSize: 15
      }

      // Unlock gesture: drag up anywhere; commit past 120px.
      MouseArea {
        anchors.fill: parent
        property real startY: 0
        onPressed: b => { if (b.button === Qt.LeftButton) startY = b.y }
        onPositionChanged: m => {
          shade.dragOffset = Math.max(0, startY - m.y)
        }
        onReleased: {
          if (shade.dragOffset > 120) {
            root.open = false
            Qt.quit()
          }
          shade.dragOffset = 0
        }
      }
    }
  }
}
