// ~/.config/fajita/notif.qml on the phone. Spawned on demand by the clock tap
// (apply-shell-patches.sh reroutes the clock's left click here), toggled by
// `quickshell -p ~/.config/fajita/notif.qml ipc call fajita-notif toggle`.
//
// A notification center: reads the Omarchy shell's own notification history
// under ~/.local/state/omarchy/notifications/history/ (one single-line JSON
// file per notification, see plugins/notifications/Service.qml) and lists it
// newest first. The shell stays the only notification daemon; this overlay is
// a pure reader, so it can run beside it with no DBus conflicts.
//
// Standalone Quickshell process (not a plugin under /usr/share/omarchy), so a
// pacman upgrade cannot overwrite it. Spawned with `quickshell -p notif.qml`
// when no instance exists yet (then it shows itself); when one is already
// running the ipc `toggle` wins. Quits 15s after hiding so instances do not
// pile up.
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io

ShellRoot {
  id: root

  property bool open: false
  property var entries: []
  property color cBg: "#f21a1b26" // QML hex is #AARRGGBB — alpha first
  property color cText: "#c0caf5"
  property color cMuted: "#7a7a8a"
  property color cAccent: "#7aa2f7"

  // Palette from the active Omarchy theme, watched so a theme switch
  // repaints a live overlay without a restart (same as empty-hint.qml).
  FileView {
    id: colors
    path: Quickshell.env("HOME") + "/.local/state/omarchy/current/theme/colors.toml"
    watchChanges: true
    onFileChanged: reload()
    onLoaded: {
      var text = colors.text()
      function pick(key, fallback) {
        var m = new RegExp("^\\s*" + key + "\\s*=\\s*\"([^\"]+)\"", "m").exec(text)
        return m ? m[1] : fallback
      }
      root.cBg = "#" + (pick("dark_background", "#1a1b26").replace("#", "f2"))
      root.cText = pick("bright_foreground", "#c0caf5")
      root.cMuted = pick("muted", "#7a7a8a")
      root.cAccent = pick("accent", "#7aa2f7")
    }
  }

  function toggle() {
    root.open = !root.open
    if (root.open) {
      rescan.running = true // restarting a running Process re-runs it
      quitTimer.stop()
    }
  }
  Component.onCompleted: root.toggle() // first spawn: show + rescan immediately

  function age(ms) {
    var s = Math.max(0, (Date.now() - ms) / 1000)
    if (s < 60) return "now"
    if (s < 3600) return Math.floor(s / 60) + "m"
    if (s < 86400) return Math.floor(s / 3600) + "h"
    return Math.floor(s / 86400) + "d"
  }

  IpcHandler {
    target: "fajita-notif"

    function toggle(): void { root.toggle() }
    function show(): void { if (!root.open) root.toggle() }
  }

  Process {
    id: rescan
    running: false
    command: ["bash", "-lc",
      "ls -t ~/.local/state/omarchy/notifications/history/*.json 2>/dev/null | head -40 | xargs -d '\\n' cat 2>/dev/null"]
    stdout: SplitParser {
      onRead: data => {
        try {
          var e = JSON.parse(data)
          e.age = age(e.timestamp || 0)
          root.entries = [e].concat(root.entries) // ls -t = newest first
        } catch (err) { /* skip malformed */ }
      }
    }
    onRunningChanged: if (running) root.entries = []
  }

  Timer {
    interval: 5000
    running: root.open
    repeat: true
    onTriggered: rescan.running = true
  }

  Timer {
    id: quitTimer
    interval: 15000
    onTriggered: Qt.quit()
  }
  onOpenChanged: if (!root.open) quitTimer.restart()

  PanelWindow {
    id: win
    anchors { top: true; left: true; right: true }
    margins.top: 82 // clear omarchy bar (43) + waybar clock row (34)
    aboveWindows: true
    exclusiveZone: -1 // overlay: never reserve layout space
    visible: root.open
    color: "transparent"
    implicitHeight: Math.min(card.height + 16, 700)
    // Tap anywhere outside the card closes the overlay (touch never
    // synthesizes clicks for MouseArea in some contexts, so use a handler).
    TapHandler {
      gesturePolicy: TapHandler.ReleaseWithinBounds
      onTapped: root.toggle()
    }

    Rectangle {
      id: card

      // Consume taps on the card itself so the window-level outside-tap
      // handler doesn't close the overlay (same pattern as the shell menu).
      MouseArea { anchors.fill: parent }
      width: parent.width - 16
      x: 8
      y: 8

      radius: 10
      color: root.cBg
      border.color: root.cAccent
      border.width: 1
      height: listCol.height + 44

      ColumnLayout {
        id: listCol

        x: 12
        y: 10
        width: parent.width - 24
        spacing: 8

        RowLayout {
          width: parent.width

          Text {
            text: "notifications"
            color: root.cMuted
            font.family: "JetBrainsMono Nerd Font"
            font.pixelSize: 13
            Layout.fillWidth: true
          }
          Text {
            text: "✕"
            color: root.cMuted
            font.pixelSize: 15
            MouseArea {
              anchors.fill: parent
              anchors.margins: -8
              onClicked: root.toggle()
            }
          }
        }

        Repeater {
          model: root.entries

          Rectangle {
            required property var modelData
            Layout.fillWidth: true
            radius: 6
            color: "#24283bcc"
            implicitHeight: cardCol.implicitHeight + 16

            ColumnLayout {
              id: cardCol

              x: 8
              y: 8
              width: parent.width - 16
              spacing: 2

              RowLayout {
                width: parent.width

                Text {
                  text: modelData.summary || ""
                  color: root.cText
                  font.family: "JetBrainsMono Nerd Font"
                  font.pixelSize: 14
                  font.bold: true
                  elide: Text.ElideRight
                  Layout.fillWidth: true
                }
                Text {
                  text: modelData.age || ""
                  color: root.cMuted
                  font.pixelSize: 11
                }
              }
              Text {
                text: modelData.body || ""
                visible: text !== ""
                color: root.cMuted
                font.pixelSize: 13
                wrapMode: Text.WrapAnywhere
                Layout.fillWidth: true
              }
              Text {
                text: modelData.app || ""
                visible: text !== "" && text !== "undefined"
                color: root.cMuted
                font.pixelSize: 10
                opacity: 0.7
              }
            }
          }
        }

        Text {
          visible: root.entries.length === 0
          text: "no notifications"
          color: root.cMuted
          font.family: "JetBrainsMono Nerd Font"
          font.pixelSize: 14
        }
      }
    }
  }
}
