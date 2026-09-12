// ~/.config/fajita/launcher.qml on the phone, run by launcher.service as a
// standalone Quickshell process — same pattern as empty-hint.qml: nothing in
// /usr/share/omarchy, so a pacman upgrade cannot overwrite it and it needs no
// patch.
//
// The concept shell's bottom bar: menu glyph, "type to launch or run" input,
// flip glyph. The input IS the phone's launcher — type an app name or any
// shell command, Enter runs it via bash -lc. Squeekboard rises over the
// Wayland text-input protocol when the field takes focus (input.lua already
// points Qt at that protocol).
//
// Design notes:
// * WlrLayer.Top with a bottom exclusive zone: Hyprland shrinks tiles so
//   nothing sits under the bar, the same mechanism as the top bars.
// * The bar is small and its buttons are explicit; no full-screen input mask,
//   so it cannot steal touches the way the keyboard panel's dismissal region
//   did (see apply-shell-patches.sh).
// * Empty-workspace hint pairs with this: its "launch something" tap focuses
//   this input over Quickshell IPC, falling back to the apps menu.

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Hyprland

ShellRoot {
  id: root

  // Palette from the active Omarchy theme, watched so a theme switch
  // repaints without a restart (same as empty-hint.qml).
  property color cBg: "#0d0d12"
  property color cText: "#7a7a8a"
  property color cAccent: "#8d8d8d"
  property color cBorder: "#2a2a34"

  readonly property int barHeight: 64
  readonly property int glyphSize: 26

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

  // Empty-hint (or anything else) focuses the input: quickshell -p
  // ~/.config/fajita/launcher.qml ipc call fajita-launcher focus
  IpcHandler {
    target: "fajita-launcher"
    function focus() {
      win.focusable = true
      input.forceActiveFocus()
    }
  }

  function run(cmd) {
    cmd = cmd.trim()
    if (cmd.length === 0) return
    Quickshell.execDetached(["bash", "-lc", cmd])
  }

  PanelWindow {
    id: win

    anchors { bottom: true; left: true; right: true }
    aboveWindows: true // WlrLayer.Top
    implicitHeight: root.barHeight
    exclusiveZone: root.barHeight // reserve layout space so tiles never sit under us
    color: "transparent"

    Rectangle {
      anchors.fill: parent
      color: root.cBg

      Rectangle { // hairline separating bar from tiles
        anchors { left: parent.left; right: parent.right; top: parent.top }
        height: 1
        color: root.cBorder
      }

      Row {
        anchors.fill: parent
        anchors.leftMargin: 14
        anchors.rightMargin: 14
        anchors.topMargin: 7
        anchors.bottomMargin: 7
        spacing: 10

        // Menu glyph — same target as the power key: Omarchy's system menu.
        Item {
          width: 44
          height: parent.height
          Text {
            anchors.centerIn: parent
            text: "☰"
            color: root.cAccent
            font.family: "JetBrainsMono Nerd Font"
            font.pixelSize: root.glyphSize
          }
          MouseArea {
            anchors.fill: parent
            onClicked: root.run("omarchy-menu toggle system")
          }
        }

        // The launcher itself: type an app name or a shell command.
        Rectangle {
          id: strip
          width: parent.width - 44 - 44 - 20 // menu + flip + spacing
          height: parent.height
          radius: 10
          color: input.activeFocus ? Qt.lighter(root.cBg, 1.35) : Qt.lighter(root.cBg, 1.15)
          border.width: input.activeFocus ? 1 : 0
          border.color: root.cAccent

          Row {
            anchors.fill: parent
            anchors.leftMargin: 12
            anchors.rightMargin: 12
            spacing: 8

            Text {
              anchors.verticalCenter: parent.verticalCenter
              text: input.activeFocus ? "▸" : "⌕"
              color: root.cAccent
              font.family: "JetBrainsMono Nerd Font"
              font.pixelSize: 20
            }

            TextInput {
              id: input
              width: parent.width - 28
              anchors.verticalCenter: parent.verticalCenter
              color: root.cText
              font.family: "JetBrainsMono Nerd Font"
              font.pixelSize: 19
              clip: true
              verticalAlignment: TextInput.AlignVCenter
              Text { // placeholder visible only while empty and unfocused
                anchors.verticalCenter: parent.verticalCenter
                visible: input.text === "" && !input.activeFocus
                text: "type to launch or run"
                color: root.cText
                opacity: 0.55
                font.family: "JetBrainsMono Nerd Font"
                font.pixelSize: 19
              }
              Keys.onEscapePressed: function (event) {
                input.focus = false
                win.focusable = false
                event.accepted = true
              }
              onAccepted: {
                root.run(input.text)
                input.text = ""
                input.focus = false
                win.focusable = false
              }
            }
          }

          MouseArea {
            anchors.fill: parent
            onClicked: {
              win.focusable = true
              input.forceActiveFocus()
            }
          }
        }

        // Flip: swap the focused window across the dwindle split.
        Item {
          width: 44
          height: parent.height
          Text {
            anchors.centerIn: parent
            text: "⇄"
            color: root.cAccent
            font.family: "JetBrainsMono Nerd Font"
            font.pixelSize: root.glyphSize
          }
          MouseArea {
            anchors.fill: parent
            onClicked: root.run("hyprctl dispatch layoutmsg swapsplit")
          }
        }
      }
    }
  }
}
