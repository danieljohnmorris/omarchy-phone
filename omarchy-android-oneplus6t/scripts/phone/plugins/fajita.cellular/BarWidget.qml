import QtQuick
import Quickshell
import Quickshell.Io
import qs.Ui

// Cellular status in the bar: signal-strength glyph (bars), RAT label
// (2G/3G/4G/5G), tooltip with details, tap toggles the data connection.
// Data source: scripts/phone/fajita-cell-status (mmcli + ip, one line).
BarWidget {
  id: root
  moduleName: "fajita.cellular"

  property int quality: 0      // 0-100
  property string rat: ""      // "4G" etc.
  property string modemState: ""
  property string dataState: "down"

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  // nerd-font md-signal_cellular_1..3 (f08bc-f08be) + _outline (f08bf).
  // Classic MDI has exactly three filled tiers. Codepoints per upstream
  // nerd-fonts glyphnames.json. NOTE: \u{...} brace form — "\uF08BC" would
  // parse as \uF08B + "C".
  property bool usable: modemState === "registered" || modemState === "connected"

  function barsGlyph(q, up) {
    if (!up || q <= 0)
      return "\u{F08BF}"           // signal_cellular_outline
    if (q < 34) return "\u{F08BC}" // 1 bar
    if (q < 67) return "\u{F08BD}" // 2 bars
    return "\u{F08BE}"             // 3 bars
  }

  function refresh(line) {
    const parts = line.trim().split("|");
    if (parts.length < 4)
      return;
    quality = parseInt(parts[0]) || 0;
    rat = parts[1];
    modemState = parts[2];
    dataState = parts[3];
  }

  Process {
    id: probe
    command: ["fajita-cell-status"]
    stdout: SplitParser {
      onRead: line => root.refresh(line)
    }
  }

  Timer {
    interval: 5000
    running: true
    repeat: true
    triggeredOnStart: true
    onTriggered: probe.running = true
  }

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: root.barsGlyph(root.quality, root.usable)
          + (root.rat !== "" ? " " + root.rat : "")
    tooltipText: "Cellular: " + (root.modemState || "no modem")
                 + (root.rat !== "" ? " " + root.rat : "")
                 + " · " + root.quality + "%"
                 + " · data " + root.dataState
    onPressed: function(b) {
      root.bar.run("fajita-cell-toggle")
    }
  }
}
