import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui

// Cellular status in the bar: signal-strength glyph (bars), RAT label
// (2G/3G/4G/5G), tooltip, left-click opens the cellular menu (Panel.qml,
// same popout pattern as the clock/weather panels), right-click toggles
// the data connection. Data source: scripts/phone/fajita-cell-status.
BarWidget {
  id: root
  moduleName: "fajita.cellular"

  property int quality: 0      // 0-100
  property string rat: ""      // "4G" etc.
  property string modemState: ""
  property string dataState: "down"

  implicitWidth: row.implicitWidth
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

  // ---- Panel plumbing. The shell's popout coordination (Bar.findPanelWidget)
  Loader {
    id: panelLoader
    active: true
    source: Qt.resolvedUrl("Panel.qml")
    visible: false
    onLoaded: Qt.callLater(root.injectPanel)
  }

  // root.bar attaches after construction; re-inject when it (or the bar
  // layout settings) arrive, or the panel keeps bar=null and its card
  // falls back to the top-left screen corner (over both bars).
  onBarChanged: injectPanel()
  onSettingsChanged: injectPanel()

  function injectPanel() {
    const t = panelLoader.item;
    if (!t)
      return;
    if ("bar" in t)
      t.bar = root.bar;
    if ("settings" in t)
      t.settings = root.settings;
    if ("anchorItem" in t)
      t.anchorItem = button;
    if ("hostWidget" in t)
      t.hostWidget = root;
  }

  readonly property bool opened: panelLoader.item ? panelLoader.item.opened === true : false
  readonly property bool popoutSwitchClosing: panelLoader.item ? panelLoader.item.popoutSwitchClosing === true : false

  function open() {
    if (panelLoader.item && panelLoader.item.open)
      panelLoader.item.open();
  }
  function close() {
    if (panelLoader.item && panelLoader.item.close)
      panelLoader.item.close();
  }
  function togglePanel() {
    if (panelLoader.item && panelLoader.item.toggle)
      panelLoader.item.toggle();
  }
  function closeForPopoutSwitch() {
    if (panelLoader.item && panelLoader.item.closeForPopoutSwitch)
      panelLoader.item.closeForPopoutSwitch();
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

  // The bars glyph lives in a standard icon slot (same optical centering as
  // every other bar icon); the RAT label is a plain Text beside it. Stuffing
  // both into one BarIconButton overflows the fixed icon slot and makes the
  // bar's spacing look uneven.
  Row {
    id: row
    anchors.verticalCenter: parent.verticalCenter
    spacing: Style.space(4)

    BarIconButton {
      id: button
      bar: root.bar
      text: root.barsGlyph(root.quality, root.usable)
      tooltipText: "Cellular: " + (root.modemState || "no modem")
                   + (root.rat !== "" ? " " + root.rat : "")
                   + " · " + root.quality + "%"
                   + " · data " + root.dataState
      onPressed: function(b) {
        if (b === Qt.RightButton)
          root.bar.run("fajita-cell-toggle");
        else
          root.togglePanel();
      }
    }

    Text {
      anchors.verticalCenter: parent.verticalCenter
      text: root.rat
      visible: root.rat !== ""
      color: root.bar ? root.bar.foreground : Color.foreground
      font.family: root.bar ? root.bar.fontFamily : Style.font.family
      font.pixelSize: Style.font.bodySmall

      TapHandler {
        onTapped: root.togglePanel()
      }
    }
  }
}
