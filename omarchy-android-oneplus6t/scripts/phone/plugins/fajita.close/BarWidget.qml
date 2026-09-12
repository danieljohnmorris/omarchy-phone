import QtQuick
import Quickshell
import qs.Ui

BarWidget {
  id: root
  moduleName: "fajita.close"

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: "󰅖"
    tooltipText: "Close focused window"
    onPressed: function(b) {
      // The fluent form: this Hyprland build evals dispatch args as Lua, and
      // the bare keyword form dies with a parse error (README trap).
      root.bar.run("hyprctl dispatch 'hl.dsp.window.close()'")
    }
  }
}
