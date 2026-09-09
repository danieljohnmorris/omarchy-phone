import QtQuick
import Quickshell
import qs.Ui

BarWidget {
  id: root
  moduleName: "fajita.keyboard"

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: "󰌌"
    tooltipText: "On-screen keyboard"
    onPressed: function(b) {
      root.bar.run("fajita-osk-toggle")
    }
  }
}
