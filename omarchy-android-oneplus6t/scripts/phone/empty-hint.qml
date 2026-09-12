// ~/.config/fajita/empty-hint.qml on the phone, run by empty-hint.service as a
// standalone Quickshell process (not a plugin in /usr/share/omarchy, so a
// pacman upgrade cannot overwrite it and it needs no patch).
//
// An empty workspace on a tiling compositor is indistinguishable from a dead
// phone: no bar content changes, nothing is drawn, and taps do nothing. On a
// laptop you would press SUPER+RETURN; there is no keyboard here. This draws
// the mock's empty state instead -- the split glyph, "workspace N is empty",
// and a tappable "launch something" that summons Omarchy's own touch-driven
// apps menu.
//
// Two deliberate choices:
//   * WlrLayer.Bottom, so real windows always paint over it. It can never
//     cover an application even if the empty check is wrong.
//   * `mask` is the card only. The rest of the surface is input-transparent,
//     so this cannot eat a tap the way the keyboard panel's full-screen
//     dismissal region did (see the KeyboardPanel patch in
//     apply-shell-patches.sh).

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Hyprland

ShellRoot {
  id: root

  // Palette from the active Omarchy theme, so the hint re-colours with it.
  // Watched, so a theme switch repaints without a restart.
  property color cBg: "#0d0d12"
  property color cText: "#7a7a8a"
  property color cAccent: "#8d8d8d"
  property color cBorder: "#2a2a34"

  // The bars reserve the top 77px (omarchy-bar 43 + waybar 34). Anchoring
  // below them keeps the card optically centred in the area a window gets.
  readonly property int barReserve: 77

  readonly property var focusedWs: Hyprland.focusedWorkspace
  readonly property int wsId: focusedWs ? focusedWs.id : 0
  readonly property int wsWindows: {
    if (!focusedWs || !focusedWs.lastIpcObject) return 1
    var n = focusedWs.lastIpcObject.windows
    return n === undefined ? 1 : n
  }
  // Never on a special workspace (-98 is the OSK primer's): it is not a place
  // the user navigates to, and its window is deliberately hidden.
  readonly property bool isEmpty: wsId > 0 && wsWindows === 0

  function launch() {
    // Straight to the app grid: wofi is the proven launcher, and the OSK
    // types into it via the text-input protocol. (A custom bottom input bar
    // lived here once — removed: the focus/OSK/primer dance was too fragile.)
    Quickshell.execDetached(["wofi", "--show", "drun"])
  }

  // Hyprland's own events are the trigger; polling would either lag the tap
  // or burn CPU on a phone. `windows` lives on the workspace IPC object, so
  // the workspace list has to be re-read, not just the focus pointer.
  Connections {
    target: Hyprland
    function onRawEvent(event) {
      var name = event.name
      if (name === "openwindow" || name === "closewindow" || name === "movewindowv2"
          || name === "workspacev2" || name === "workspace" || name === "focusedmonv2") {
        Hyprland.refreshWorkspaces()
      }
    }
  }

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
      root.cBg = pick("dark_background", "#0d0d12")
      root.cText = pick("muted", "#7a7a8a")
      root.cAccent = pick("blue", "#8d8d8d")
      root.cBorder = pick("lighter_background", "#2a2a34")
    }
  }

  PanelWindow {
    id: win

    anchors { top: true; bottom: true; left: true; right: true }
    margins.top: root.barReserve
    color: "transparent"
    surfaceFormat.opaque: false
    exclusionMode: ExclusionMode.Ignore
    visible: root.isEmpty

    WlrLayershell.namespace: "fajita-empty-hint"
    WlrLayershell.layer: WlrLayer.Bottom
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

    // Only the button is interactive; everywhere else stays pass-through.
    mask: Region { item: card }

    Column {
      anchors.centerIn: parent
      spacing: 22


      Text {
        anchors.horizontalCenter: parent.horizontalCenter
        text: "workspace " + root.wsId + " is empty"
        color: root.cText
        font.family: "JetBrainsMono Nerd Font"
        font.pixelSize: 17
      }

      Rectangle {
        id: card
        anchors.horizontalCenter: parent.horizontalCenter
        width: label.implicitWidth + 56
        // 48px is the smallest comfortable thumb target; the mock's button is
        // wider than its text for exactly this reason.
        height: 56
        radius: 4
        color: tap.pressed ? root.cBorder : "transparent"
        border.width: 1
        border.color: root.cBorder

        Row {
          anchors.centerIn: parent
          spacing: 10

          Text {
            text: "\u25b8"
            color: root.cAccent
            font.family: "JetBrainsMono Nerd Font"
            font.pixelSize: 15
            anchors.verticalCenter: parent.verticalCenter
          }

          Text {
            id: label
            text: "launch something"
            color: root.cAccent
            font.family: "JetBrainsMono Nerd Font"
            font.pixelSize: 19
            anchors.verticalCenter: parent.verticalCenter
          }
        }

        MouseArea {
          id: tap
          anchors.fill: parent
          onClicked: root.launch()
        }
      }
    }
  }
}
