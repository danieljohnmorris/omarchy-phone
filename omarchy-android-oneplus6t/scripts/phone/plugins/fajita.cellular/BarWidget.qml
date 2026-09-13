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

  // The bars glyph lives in a standard icon button (same optical rendering as
  // every other bar icon); the RAT label is a plain Text beside it. The
  // button's width is hugged to the glyph — the default statusSlot (21px)
  // centers the ~9px-wide glyph with ~7px dead space each side, which reads
  // as a hole between bars and label (stock single icons spread that dead
  // space between each other, a compound icon+label cannot).
  Row {
    id: row
    anchors.verticalCenter: parent.verticalCenter
    spacing: Style.space(1)

    BarIconButton {
      id: button
      bar: root.bar
      // Horizontal bars: hug the 16px icon canvas. This instance assignment
      // permanently replaces BarIconButton's fixedWidth binding; on vertical
      // bars width falls to WidgetButton's content sizing (12px — label is
      // hidden), while height keeps the untouched slotSize binding.
      fixedWidth: root.bar && root.bar.vertical ? -1 : Style.bar.iconCanvas - 2
      slotSize: Style.bar.statusSlot
      text: root.barsGlyph(root.quality, root.usable)
      // Touch devices have no hover-unhover: a tap parks the cursor on the
      // button and the tooltip sticks over the clock row. Skip it.
      tooltipText: ""
      // Handler on the button itself: something in the WidgetButton stack
      // consumes presses inside the declared box above the sibling overlay,
      // so the overlay alone leaves the glyph area dead. Both paths toggle;
      // whichever layer wins, the click works. Log disambiguates in qs log.
      onPressed: function(b) {
        console.log("[fajita-cellular] button pressed", b)
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

    }
  }
    // One hit target across glyph + label: the button hugs a 14px box but the
    // 16px canvas (and the label) extend past it, so per-child handlers left
    // dead zones. Sibling of the Row (positioners reject fill anchors inside
    // a Row). Covers gap + label; the button's own onPressed covers its box —
    // the WidgetButton stack consumes presses above the overlay there.
    MouseArea {
      anchors.fill: row
      acceptedButtons: Qt.LeftButton | Qt.RightButton
      onClicked: function(mouse) {
        console.log("[fajita-cellular] overlay click", mouse.x, mouse.y, mouse.button)
        if (mouse.button === Qt.RightButton)
          root.bar.run("fajita-cell-toggle");
        else
          root.togglePanel();
      }
    }
}
