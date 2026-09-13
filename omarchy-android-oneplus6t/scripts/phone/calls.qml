// ~/.config/fajita/calls.qml on the phone. Spawned on demand from the menu
// ("Calls" row) or by fajita-call-watch on call events; toggled by
// `quickshell -p ~/.config/fajita/calls.qml ipc call fajita-calls toggle`.
//
// Calls panel, same overlay shape as notif.qml/quicksettings.qml: a themed
// card under the bar, tap outside to dismiss — not a full-screen surface.
// Keypad dialer when idle, live call rows (accept/decline/hang up) when
// ModemManager has calls. Everything shells out to fajita-call (mmcli);
// audio routing is q6voiced + fajita-call-watch, not this UI.
//
// Standalone Quickshell process, same pattern as notif.qml: first spawn
// shows itself, an existing instance answers ipc `toggle`, quits 15s after
// hiding so instances do not pile up.
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io

ShellRoot {
  id: root

  property bool open: false
  property var calls: []          // [{path,state,dir,number}]
  property string dial: ""        // number being typed
  property var callStart: ({})    // path -> epoch ms when first seen active
  property string lastError: ""

  // Pre-load fallbacks only; every colour below is replaced from the active
  // Omarchy theme in the FileView. QML hex is #AARRGGBB — alpha first.
  property color cBg: "#ff111c18"
  property color cText: "#F7E8B2"
  property color cMuted: "#53685B"
  property color cAccent: "#509475"
  property color cRow: "#23372B"
  property color cGreen: "#549e6a"
  property color cRed: "#FF5345"

  // Palette from the active Omarchy theme, watched so a theme switch
  // repaints a live window without a restart (same as notif.qml).
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
      root.cBg = "#ff" + pick("dark_background", "#111c18").replace("#", "")
      root.cText = pick("bright_foreground", "#F7E8B2")
      root.cMuted = pick("muted", "#53685B")
      root.cAccent = pick("accent", "#509475")
      root.cRow = pick("lighter_background", "#23372B")
      root.cGreen = pick("green", "#549e6a")
      root.cRed = pick("red", "#FF5345")
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

  function run(cmd) { // fire-and-forget; errors surface via lastError
    root.lastError = ""
    proc.command = ["bash", "-lc", cmd]
    proc.running = true
  }

  function stateText(state, path) {
    switch (state) {
      case "dialing": return "calling…"
      case "ringing-out": return "ringing…"
      case "incoming":
      case "ringing-in": return "incoming call"
      case "active":
        var s = Math.max(0, (Date.now() - (root.callStart[path] || Date.now())) / 1000)
        return Math.floor(s / 60) + ":" + ("0" + Math.floor(s % 60)).slice(-2)
      case "held": return "on hold"
      case "terminated": return "ended"
      case "failed": return "call failed"
      default: return state
    }
  }

  function incoming(state) {
    return state === "incoming" || state === "ringing-in"
  }

  IpcHandler {
    target: "fajita-calls"

    function toggle(): void { root.toggle() }
    function show(): void { if (!root.open) root.toggle() }
  }

  // Common runner for actions (start/accept/hangup).
  Process {
    id: proc
    running: false
    command: ["true"]
    stderr: SplitParser {
      onRead: data => { if (data.trim()) root.lastError = data.trim() }
    }
    onExited: rescan.running = true // reflect the new call state immediately
  }

  Process {
    id: rescan
    running: false
    command: ["bash", "-lc", "fajita-call list"]
    stdout: SplitParser {
      onRead: data => {
        var p = data.split("|")
        if (p.length < 4 || p[0].indexOf("/Call/") < 0) return
        var c = { path: p[0], state: p[1], dir: p[2], number: p[3] || "unknown" }
        if (c.state === "active" && !root.callStart[c.path]) root.callStart[c.path] = Date.now()
        var out = root.calls.filter(x => x.path !== c.path)
        out.push(c)
        root.calls = out
      }
    }
    onRunningChanged: if (running) root.calls = []
  }

  // Poll while open: far-end answers/hangups arrive as state changes we do
  // not otherwise observe, and the active-call timer needs a tick.
  Timer {
    interval: 1000
    repeat: true
    running: root.open
    onTriggered: if (!rescan.running) rescan.running = true
  }

  Timer {
    id: quitTimer
    interval: 15000
    onTriggered: Qt.quit()
  }
  onOpenChanged: if (!root.open) quitTimer.restart()

  // A normal Hyprland window (xdg-toplevel), not a layer-shell overlay: it
  // tiles like any other app, so calls and messages sit side by side 50/50
  // and the bar keeps its reserved space.
  FloatingWindow {
    id: win
    title: "calls"
    color: root.cBg
    visible: root.open
    implicitWidth: 540
    implicitHeight: 1080

    Rectangle {
      id: card
      anchors.fill: parent
      color: root.cBg

      ColumnLayout {
        id: col
        anchors.fill: parent
        anchors.margins: 16
        spacing: 12

        // Header
        RowLayout {
          Layout.fillWidth: true

          Text {
            text: root.calls.length > 0 ? "call" : "dial"
            color: root.cAccent
            font.family: "JetBrainsMono Nerd Font"
            font.pixelSize: 15
            Layout.fillWidth: true
          }

          Text {
            text: "✕"
            color: root.cMuted
            font.family: "JetBrainsMono Nerd Font"
            font.pixelSize: 18
            MouseArea {
              anchors.fill: parent
              anchors.margins: -14
              // A window, not an overlay: closing it closes the app.
              onClicked: Qt.quit()
            }
          }
        }

        // Live calls
        Repeater {
          model: root.calls

          ColumnLayout {
            required property var modelData
            Layout.fillWidth: true
            spacing: 10

            Text {
              text: modelData.number
              color: root.cText
              font.family: "JetBrainsMono Nerd Font"
              font.pixelSize: 24
              font.bold: true
              Layout.alignment: Qt.AlignHCenter
            }

            Text {
              text: root.stateText(modelData.state, modelData.path)
              color: modelData.state === "active" ? root.cGreen : root.cMuted
              font.family: "JetBrainsMono Nerd Font"
              font.pixelSize: 14
              Layout.alignment: Qt.AlignHCenter
            }

            // Incoming: accept / decline. Everything else: hang up.
            RowLayout {
              Layout.fillWidth: true
              spacing: 12

              Rectangle {
                visible: root.incoming(modelData.state)
                Layout.fillWidth: true
                height: 64
                radius: 10
                color: root.cGreen

                Text {
                  anchors.centerIn: parent
                  text: "accept"
                  color: root.cBg
                  font.family: "JetBrainsMono Nerd Font"
                  font.pixelSize: 16
                }
                MouseArea {
                  anchors.fill: parent
                  onClicked: root.run("fajita-call accept '" + modelData.path + "'")
                }
              }

              Rectangle {
                Layout.fillWidth: true
                height: 64
                radius: 10
                color: root.cRed

                Text {
                  anchors.centerIn: parent
                  text: root.incoming(modelData.state) ? "decline" : "hang up"
                  color: root.cBg
                  font.family: "JetBrainsMono Nerd Font"
                  font.pixelSize: 16
                }
                MouseArea {
                  anchors.fill: parent
                  onClicked: root.run("fajita-call hangup '" + modelData.path + "'")
                }
              }
            }
          }
        }

        Text {
          visible: root.lastError !== ""
          text: root.lastError
          color: root.cRed
          font.family: "JetBrainsMono Nerd Font"
          font.pixelSize: 11
          wrapMode: Text.WrapAnywhere
          Layout.fillWidth: true
        }

        // Dialer (hidden while any call is live)
        ColumnLayout {
          visible: root.calls.length === 0
          Layout.fillWidth: true
          Layout.fillHeight: true
          spacing: 8

          Text {
            text: root.dial || "number"
            color: root.dial ? root.cText : root.cMuted
            font.family: "JetBrainsMono Nerd Font"
            font.pixelSize: 30
            elide: Text.ElideLeft
            horizontalAlignment: Text.AlignHCenter
            Layout.fillWidth: true
            Layout.bottomMargin: 4
          }

          // Keypad: the five rows share whatever height the tile gives us, so
          // the app is usable full-screen and at half height in a 50/50 split.
          Repeater {
            model: [["1", "2", "3"], ["4", "5", "6"], ["7", "8", "9"], ["*", "0", "#"]]

            RowLayout {
              id: keyRow
              required property var modelData
              Layout.fillWidth: true
              Layout.fillHeight: true
              Layout.preferredHeight: 72
              Layout.maximumHeight: 110
              spacing: 8

              Repeater {
                model: keyRow.modelData

                Rectangle {
                  id: keyCell
                  required property string modelData
                  Layout.fillWidth: true
                  Layout.fillHeight: true
                  radius: 10
                  color: root.cRow

                  Text {
                    anchors.centerIn: parent
                    text: keyCell.modelData
                    color: root.cText
                    font.family: "JetBrainsMono Nerd Font"
                    font.pixelSize: Math.max(14, Math.min(26, keyCell.height * 0.4))
                  }
                  MouseArea {
                    anchors.fill: parent
                    onClicked: root.dial += keyCell.modelData
                  }
                }
              }
            }
          }

          // + (international prefix), backspace, call
          RowLayout {
            id: actionRow
            Layout.fillWidth: true
            Layout.fillHeight: true
            Layout.preferredHeight: 72
            Layout.maximumHeight: 110
            spacing: 8

            Rectangle {
              Layout.fillWidth: true
              Layout.fillHeight: true
              radius: 10
              color: root.cRow

              Text {
                anchors.centerIn: parent
                text: "+"
                color: root.cText
                font.family: "JetBrainsMono Nerd Font"
                font.pixelSize: Math.max(14, Math.min(26, actionRow.height * 0.4))
              }
              MouseArea {
                anchors.fill: parent
                onClicked: root.dial += "+"
              }
            }

            Rectangle {
              Layout.fillWidth: true
              Layout.fillHeight: true
              radius: 10
              color: root.cRow

              Text {
                anchors.centerIn: parent
                text: "⌫"
                color: root.cText
                font.family: "JetBrainsMono Nerd Font"
                font.pixelSize: Math.max(13, Math.min(24, actionRow.height * 0.36))
              }
              MouseArea {
                anchors.fill: parent
                onClicked: root.dial = root.dial.slice(0, -1)
              }
            }

            Rectangle {
              Layout.fillWidth: true
              Layout.fillHeight: true
              radius: 10
              color: root.dial.length >= 3 ? root.cGreen : root.cRow

              Text {
                anchors.centerIn: parent
                text: "call"
                color: root.dial.length >= 3 ? root.cBg : root.cMuted
                font.family: "JetBrainsMono Nerd Font"
                font.pixelSize: Math.max(12, Math.min(18, actionRow.height * 0.26))
              }
              MouseArea {
                anchors.fill: parent
                // Allow short service codes (e.g. voicemail) from 3 digits up.
                onClicked: if (root.dial.length >= 3) {
                  root.run("fajita-call start '" + root.dial.replace(/ /g, "") + "'")
                }
              }
            }
          }
        }
      }
    }
  }
}
