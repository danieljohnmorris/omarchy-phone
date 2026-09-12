// ~/.config/fajita/close-chip.qml on the phone, run by close-chip.service.
//
// A small ✕ button pinned to the top-right corner of the focused window —
// the touch close affordance a tiling compositor has no titlebars for. Tap
// closes the focused client (hl.dsp.window.close(), verified against a live
// focused window on this build). Works for tiled and floating windows alike;
// hides when nothing focusable is present. Theme palette from colors.toml,
// watched; #AARRGGBB (alpha first).

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Hyprland

ShellRoot {
  id: root

  readonly property int chip: 34
  property int winX: 0
  property int winY: 0
  property int winW: 0
  property bool hasTarget: false

  property color cBg: "#f21a1b26"
  property color cFg: "#c0caf5"
  property color cBorder: "#24283b"

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
      root.cBg = "#f2" + pick("dark_background", "#1a1b26").replace("#", "")
      root.cFg = pick("bright_foreground", "#c0caf5")
      root.cBorder = pick("lighter_background", "#24283b")
    }
  }

  function rescan() {
    addr.running = true
  }

  // hyprctl activewindow -j gives address/at/size of the focus.
  Process {
    id: addr
    command: ["bash", "-lc",
      "export XDG_RUNTIME_DIR=/run/user/$(id -u); " +
      "export HYPRLAND_INSTANCE_SIGNATURE=$(hyprctl instances -j | python3 -c 'import sys,json;print(json.load(sys.stdin)[0][\"instance\"])'); " +
      "hyprctl -j activewindow | python3 -c 'import sys,json;d=json.load(sys.stdin);print(d.get(\"address\",\"\"),d.get(\"at\",[0,0])[0],d.get(\"at\",[0,0])[1],d.get(\"size\",[0,0])[0])'"]
    stdout: StdioCollector {
      onStreamFinished: {
        var p = text.trim().split(/\s+/)
        if (p.length >= 4 && p[0] !== "" && p[0] !== "invalid") {
          root.hasTarget = true
          root.winX = parseInt(p[1]); root.winY = parseInt(p[2])
          root.winW = parseInt(p[3])
        } else {
          root.hasTarget = false
        }
      }
    }
  }

  Connections {
    target: Hyprland
    function onRawEvent(event) {
      var n = event.name
      if (n === "activewindow" || n === "activewindowv2" || n === "openwindow"
          || n === "closewindow" || n === "movewindow" || n === "movewindowv2"
          || n === "resizewindow" || n === "resizewindowv2"
          || n === "changefloatingmode" || n === "workspace")
        rescan()
    }
  }
  Component.onCompleted: rescan()

  Timer {
    interval: 200
    running: true
    triggeredOnStart: true
    repeat: true
    onTriggered: rescan() // geometry drifts during interactive drags; cheap poll
  }

  PanelWindow {
    id: win
    anchors { top: true; left: true }
    aboveWindows: true
    exclusiveZone: -1
    color: "transparent"
    visible: root.hasTarget
    implicitWidth: root.chip
    implicitHeight: root.chip
    margins.left: Math.max(0, root.winX + root.winW - root.chip - 6)
    margins.top: Math.max(0, root.winY + 6)

    WlrLayershell.namespace: "fajita-close-chip"
    WlrLayershell.layer: WlrLayer.Top
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

    Rectangle {
      anchors.fill: parent
      radius: 8
      color: chipArea.pressed ? root.cBorder : root.cBg
      border.width: 1
      border.color: root.cBorder

      Text {
        anchors.centerIn: parent
        text: "✕"
        color: root.cFg
        font.family: "JetBrainsMono Nerd Font"
        font.pixelSize: 16
      }

      MouseArea {
        id: chipArea
        anchors.fill: parent
        onClicked: closer.running = true
      }
    }
  }

  Process {
    id: closer
    command: ["bash", "-lc",
      "export XDG_RUNTIME_DIR=/run/user/$(id -u); " +
      "export HYPRLAND_INSTANCE_SIGNATURE=$(hyprctl instances -j | python3 -c 'import sys,json;print(json.load(sys.stdin)[0][\"instance\"])'); " +
      "hyprctl dispatch 'hl.dsp.window.close()' >/dev/null 2>&1"]
  }
}
