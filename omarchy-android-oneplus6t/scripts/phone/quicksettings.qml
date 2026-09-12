// ~/.config/fajita/quicksettings.qml on the phone. Spawned on demand by the
// battery tap (apply-shell-patches.sh reroutes the power widget's left click
// here), toggled by `quickshell -p ~/.config/fajita/quicksettings.qml ipc
// call fajita-qs toggle`.
//
// Quick settings, concept-shell style: battery header, Wi-Fi state + radio
// toggle, brightness slider, screen off. Everything shells out to tools the
// rootfs already ships (nmcli, brightnessctl, fajita-screen-off) so the shell
// process itself is untouched. Bluetooth has no row on purpose: the fajita
// HCI never comes up (see README), a toggle that cannot work is noise.
//
// Standalone Quickshell process, same pattern as notif.qml: the first spawn
// shows itself, an existing instance answers the ipc `toggle`, and the process
// quits 15s after hiding so instances do not pile up.
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import QtQuick.Controls
ShellRoot {
  id: root

  property bool open: false
  property string battery: ""
  property string wifiState: ""
  property string ssid: ""
  property int brightness: 0 // 1..100
  property bool dragging: false
  property string lastError: ""
  property color cBg: "#f21a1b26" // QML hex is #AARRGGBB — alpha first
  property color cText: "#c0caf5"
  property color cMuted: "#7a7a8a"
  property color cAccent: "#7aa2f7"
  property color cRow: "#24283b" // tile fill (lighter_background)
  property color cError: "#f7768e"

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
      root.cRow = pick("lighter_background", "#24283b")
      root.cError = pick("red", "#f7768e")
    }
  }

  function toggle() {
    root.open = !root.open
    if (root.open) {
      rescan.running = true
      quitTimer.stop()
    }
  }
  Component.onCompleted: root.toggle() // first spawn: show + rescan immediately

  IpcHandler {
    target: "fajita-qs"

    function toggle(): void { root.toggle() }
    function show(): void { if (!root.open) root.toggle() }
  }

  // One-shot status gather, run on open and after each toggle settles.
  Process {
    id: rescan
    running: false
    command: ["bash", "-lc",
      "b=$(cat /sys/class/power_supply/battery/capacity 2>/dev/null); " +
      "bs=$(cat /sys/class/power_supply/battery/status 2>/dev/null); echo \"BAT|$b|$bs\"; " +
      "echo \"WIFI|$(nmcli radio wifi 2>/dev/null)|$(nmcli -t -f ACTIVE,SSID dev wifi list 2>/dev/null | awk -F: '$1==\"yes\"{print $2; exit}')\"; " +
      "m=$(brightnessctl -m 2>/dev/null | head -1); echo \"BRI|$(echo \"$m\" | cut -d, -f3)|$(echo \"$m\" | cut -d, -f4)\""]
    stdout: SplitParser {
      onRead: data => {
        var p = data.split("|")
        if (p[0] === "BAT" && p[1]) root.battery = p[1] + "% " + (p[2] || "")
        else if (p[0] === "WIFI" && p[1]) { root.wifiState = p[1]; root.ssid = p[2] || "" }
        else if (p[0] === "BRI" && p[2]) {
          var pct = Math.max(1, parseInt(p[2])) // -m f4 is "NN%"
          if (!root.dragging) root.brightness = pct
        }
      }
    }
  }

  // Fire-and-forget actions; stderr lands in lastError for the footer row.
  Process {
    id: act
    running: false
    stdout: SplitParser { onRead: () => rescan.running = true }
    stderr: SplitParser { onRead: d => { root.lastError = d.trim() } }
    onRunningChanged: if (!running) resetErr.restart()
  }
  Timer { id: resetErr; interval: 4000; onTriggered: root.lastError = "" }

  // Wi-Fi takes a moment to report after a radio flip.
  Timer {
    id: wifiSettle
    interval: 2500
    onTriggered: rescan.running = true
  }

  function run(cmd) { act.command = ["bash", "-lc", cmd]; act.running = true }

  Timer {
    id: quitTimer
    interval: 15000
    onTriggered: Qt.quit()
  }
  onOpenChanged: if (!root.open) quitTimer.restart()

  PanelWindow {
    id: win
    anchors { top: true; right: true }
    margins.top: 82 // clear omarchy bar (43) + waybar clock row (34)
    aboveWindows: true
    exclusiveZone: -1 // overlay: never reserve layout space
    visible: root.open
    color: "transparent"
    implicitWidth: 380
    implicitHeight: Math.min(card.height + 16, 640)

    // Tap anywhere outside the card closes the overlay; the card and its
    // controls are declared after this, so they consume their own taps.
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
      height: col.height + 44

      ColumnLayout {
        id: col

        x: 12
        y: 10
        width: parent.width - 24
        spacing: 10

        RowLayout {
          width: parent.width

          Text {
            text: "quick settings"
            color: root.cMuted
            font.family: "JetBrainsMono Nerd Font"
            font.pixelSize: 13
            Layout.fillWidth: true
          }
          Text {
            text: root.battery
            color: root.cText
            font.family: "JetBrainsMono Nerd Font"
            font.pixelSize: 13
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

        // Wi-Fi: radio state + current SSID, tap the row to flip the radio.
        Rectangle {
          Layout.fillWidth: true
          radius: 6
          implicitHeight: 46
          color: root.wifiState === "enabled" ? Qt.rgba(root.cRow.r, root.cRow.g, root.cRow.b, 0.8) : Qt.rgba(root.cRow.r, root.cRow.g, root.cRow.b, 0.33)
          RowLayout {
            x: 10
            y: 0
            width: parent.width - 20
            height: parent.height
            spacing: 8

            Text {
              text: "󰤨"
              color: root.wifiState === "enabled" ? root.cAccent : root.cMuted
              font.family: "JetBrainsMono Nerd Font"
              font.pixelSize: 18
            }
            Text {
              text: root.wifiState === "enabled" ? (root.ssid || "wi-fi on, not connected") : "wi-fi off"
              color: root.cText
              font.family: "JetBrainsMono Nerd Font"
              font.pixelSize: 14
              elide: Text.ElideRight
              Layout.fillWidth: true
            }
            Text {
              text: root.wifiState === "enabled" ? "on" : "off"
              color: root.wifiState === "enabled" ? root.cAccent : root.cMuted
              font.family: "JetBrainsMono Nerd Font"
              font.pixelSize: 13
            }
            MouseArea {
              Layout.fillWidth: true
              Layout.fillHeight: true
              onClicked: {
                root.run("nmcli radio wifi " + (root.wifiState === "enabled" ? "off" : "on"))
                wifiSettle.restart()
              }
            }
          }
        }

        // Brightness: live slider, commits per tick while dragging.
        ColumnLayout {
          Layout.fillWidth: true
          spacing: 2

          Text {
            text: "brightness " + root.brightness + "%"
            color: root.cMuted
            font.family: "JetBrainsMono Nerd Font"
            font.pixelSize: 12
          }
          Slider {
            id: bri

            Layout.fillWidth: true
            from: 1
            to: 100
            value: root.brightness
            onPressedChanged: p => { root.dragging = p }
            onMoved: {
              root.brightness = value
              root.run("brightnessctl set " + Math.round(value) + "% -q")
            }
          }
        }

        // Screen off — same path as the menu's "Screen off" row.
        Rectangle {
          Layout.fillWidth: true
          radius: 6
          implicitHeight: 46
          color: Qt.rgba(root.cRow.r, root.cRow.g, root.cRow.b, 0.8)
          RowLayout {
            x: 10
            y: 0
            width: parent.width - 20
            height: parent.height

            Text {
              text: "󰽥"
              color: root.cAccent
              font.family: "JetBrainsMono Nerd Font"
              font.pixelSize: 18
            }
            Text {
              text: "screen off"
              color: root.cText
              font.family: "JetBrainsMono Nerd Font"
              font.pixelSize: 14
              Layout.fillWidth: true
            }
            MouseArea {
              anchors.fill: parent
              onClicked: root.run("fajita-screen-off")
            }
          }
        }

        Text {
          visible: root.lastError !== ""
          text: root.lastError
          font.family: "JetBrainsMono Nerd Font"
          font.pixelSize: 11
          color: root.cError
          wrapMode: Text.WrapAnywhere
          Layout.fillWidth: true
        }
      }
    }
  }
}
