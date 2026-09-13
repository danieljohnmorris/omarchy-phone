import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui

// Cellular menu: hero (signal glyph + RAT, operator + quality), status rows
// (modem / data / IP / ping / totals), live down/up rates with a bandwidth
// graph, actions (toggle data, reconnect). Opens from the bar icon like every
// other panel; also reachable over IPC for remote testing:
//   qs ipc call fajita.cellular toggle
// Data source: scripts/phone/fajita-cell-info, one line per sample:
//   OPERATOR|RAT|SIGNAL|MODEM|DATA|IP|RXBYTES|TXBYTES|PINGMS
Panel {
  id: root

  moduleName: "fajita.cellular"
  ipcTarget: "fajita.cellular"
  manageIpc: true
  property var anchorItem: null
  // The bar tracks the widget mounted in its slot (BarWidget.qml), not this
  // nested panel — popout coordination compares against that identity.
  property var hostWidget: null
  readonly property var barIdentity: hostWidget || root

  property string operatorName: ""
  property string rat: ""
  property int quality: 0
  property string modemState: ""
  property string dataState: "down"
  property string ipAddr: ""
  property real rxBytes: 0
  property real txBytes: 0
  property string pingMs: "-"
  // False until the first fajita-cell-info line parses. Before that the
  // defaults above are guesses; showing "No operator" / "Data: off" for the
  // ~1s script window reads as an outage, so the UI shows "…" instead.
  property bool sampled: false

  // Rates (bytes/s) and the graph history (last GRAPH_POINTS samples).
  property real rxRate: 0
  property real txRate: 0
  property var rxHist: []
  property var txHist: []
  property var sigHist: []
  property real lastRx: -1
  property real lastTx: -1
  property real lastStamp: 0
  readonly property int graphPoints: 60

  property bool usable: modemState === "registered" || modemState === "connected"
  property color fg: bar ? bar.foreground : Color.foreground
  property string fontFamily: bar ? bar.fontFamily : Style.font.family

  function fmtBytes(raw) {
    var n = Math.round(raw)
    if (!n || n < 0) return "—"
    var units = ["B", "KB", "MB", "GB", "TB"]
    var i = 0
    var v = n
    while (v >= 1000 && i < units.length - 1) { v /= 1000; i++ }
    return (i === 0 ? v : v.toFixed(1)) + " " + units[i]
  }

  function fmtRate(bps) {
    if (dataState !== "up") return "0 B/s"
    var units = ["B/s", "KB/s", "MB/s", "GB/s"]
    var i = 0
    var v = bps
    while (v >= 1000 && i < units.length - 1) { v /= 1000; i++ }
    return (i === 0 ? Math.round(v) : v.toFixed(1)) + " " + units[i]
  }

  // Same three-tier glyphs as the bar widget (nerd-font md-signal_cellular_*).
  function barsGlyph(q, up) {
    if (!up || q <= 0) return "\u{F08BF}"
    if (q < 34) return "\u{F08BC}"
    if (q < 67) return "\u{F08BD}"
    return "\u{F08BE}"
  }

  // Shared painter: one series per canvas, right-aligned history.
  // fixedPeak > 0 pins the scale (percentages); 0 autoscales (bytes/s).
  function paintSeries(cv, data, fixedPeak, color) {
    var ctx = cv.getContext("2d")
    ctx.clearRect(0, 0, cv.width, cv.height)
    ctx.strokeStyle = String(Color.muted)
    ctx.globalAlpha = 0.35
    ctx.lineWidth = 1
    ctx.beginPath()
    ctx.moveTo(0, cv.height - 0.5)
    ctx.lineTo(cv.width, cv.height - 0.5)
    ctx.stroke()
    ctx.globalAlpha = 1
    if (data.length < 2) return
    var peak = fixedPeak
    if (!peak || peak <= 0) {
      peak = 1024
      for (var i = 0; i < data.length; i++)
        if (data[i] > peak) peak = data[i]
    }
    ctx.strokeStyle = color
    ctx.lineWidth = 1.5
    ctx.beginPath()
    for (var j = 0; j < data.length; j++) {
      var x = cv.width - (data.length - 1 - j) * (cv.width / (root.graphPoints - 1))
      var y = cv.height - 2 - (data[j] / peak) * (cv.height - 6)
      if (j === 0) ctx.moveTo(x, y)
      else ctx.lineTo(x, y)
    }
    ctx.stroke()
  }

  function refresh() {
    // Force a restart even if a previous run is still draining; the info
    // script takes ~1s (ping) and the poll is 2s, so overlap is possible.
    proc.running = false
    proc.running = true
  }

  function sample(now, rx, tx) {
    // Signal is sampled on every read: it has no monotonic dependency, and
    // gating it behind the rate guard would freeze it across modem
    // reconnects (counter resets are exactly when you want the graph).
    sigHist.push(quality)
    while (sigHist.length > graphPoints) sigHist.shift()
    if (lastStamp > 0 && lastRx >= 0 && rx >= lastRx && tx >= lastTx) {
      var dt = (now - lastStamp) / 1000
      if (dt > 0.2) {
        rxRate = Math.max(0, (rx - lastRx) / dt)
        txRate = Math.max(0, (tx - lastTx) / dt)
        rxHist.push(rxRate)
        txHist.push(txRate)
        while (rxHist.length > graphPoints) rxHist.shift()
        while (txHist.length > graphPoints) txHist.shift()
      }
    }
    lastStamp = now
    lastRx = rx
    lastTx = tx
    sigGraph.requestPaint()
    downGraph.requestPaint()
    upGraph.requestPaint()
  }

  function open() {
    refresh()
    controller.show()
  }

  function close() {
    controller.hide()
  }

  function toggle() {
    opened ? close() : open()
  }

  Process {
    id: proc
    command: ["fajita-cell-info"]
    stdout: SplitParser {
      onRead: line => {
        var f = line.trim().split("|")
        if (f.length < 9) return
        root.sampled = true
        root.operatorName = f[0]
        root.rat = f[1]
        root.quality = parseInt(f[2]) || 0
        root.modemState = f[3]
        root.dataState = f[4]
        root.ipAddr = f[5]
        var rx = parseFloat(f[6]) || 0
        var tx = parseFloat(f[7]) || 0
        root.sample(Date.now(), rx, tx)
        root.rxBytes = rx
        root.txBytes = tx
        root.pingMs = f[8]
      }
    }
  }

  // Keep the open menu live: mmcli + ping take ~1s per sample, poll at 2s
  // while the panel is visible so rates, ping and the graph move.
  Timer {
    interval: 2000
    running: root.opened === true
    repeat: true
    triggeredOnStart: true
    onTriggered: root.refresh()
  }
  Timer {
    id: settle
    interval: 2500
    onTriggered: root.refresh()
  }

  KeyboardPanel {
    id: panel
    anchorItem: root.anchorItem
    owner: root.barIdentity
    bar: root.bar
    open: root.opened
    centerOnBar: true
    // Gap clears BOTH bar rows: Omarchy's bar plus the waybar clock row
    // (34 px) beneath it, so the open panel never covers the clock.
    gap: Style.gapsOut + 34
    contentWidth: panel.fittedContentWidth(Style.space(320))
    contentHeight: panel.fittedContentHeight(column.implicitHeight)

    PanelKeyCatcher {
      anchors.fill: parent
      onCloseRequested: root.close()
      onTabRequested: function(direction) { root.switchPanel(direction) }

      Column {
        id: column
        anchors.fill: parent
        spacing: Style.space(10)

        // ---- Hero: glyph + RAT on the left, operator + quality on the right.
        Item {
          width: parent.width
          height: Math.max(heroLeft.implicitHeight, heroRight.implicitHeight)

          Row {
            id: heroLeft
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            spacing: Style.space(10)

            Text {
              anchors.verticalCenter: parent.verticalCenter
              textFormat: Text.PlainText
              text: root.barsGlyph(root.quality, root.usable)
              color: root.fg
              font.family: root.fontFamily
              font.pixelSize: Style.font.icon * 1.6
            }
            Text {
              anchors.verticalCenter: parent.verticalCenter
              text: root.rat || "—"
              color: root.fg
              font.family: root.fontFamily
              font.pixelSize: Style.font.body
              font.weight: Font.Bold
            }
          }

          Column {
            id: heroRight
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            spacing: Style.space(2)

            Text {
              anchors.right: parent.right
              text: root.sampled ? (root.operatorName || "No operator") : "…"
              color: root.fg
              font.family: root.fontFamily
              font.pixelSize: Style.font.body
            }
            Text {
              anchors.right: parent.right
              text: root.modemState !== "" ? root.quality + "% signal" : "—"
              color: Color.muted
              font.family: root.fontFamily
              font.pixelSize: Style.font.bodySmall
            }
          }
        }

        PanelSeparator {}

        // ---- Status rows: label left, value right.
        Item {
          width: parent.width
          height: modemLabel.implicitHeight
          Text {
            id: modemLabel
            anchors.left: parent.left
            text: "Modem"
            color: Color.muted
            font.family: root.fontFamily
            font.pixelSize: Style.font.bodySmall
          }
          Text {
            anchors.right: parent.right
            text: root.sampled ? (root.modemState || "unknown") : "…"
            color: root.fg
            font.family: root.fontFamily
            font.pixelSize: Style.font.bodySmall
          }
        }
        Item {
          width: parent.width
          height: ipLabel.implicitHeight
          Text {
            id: ipLabel
            anchors.left: parent.left
            text: "IP"
            color: Color.muted
            font.family: root.fontFamily
            font.pixelSize: Style.font.bodySmall
          }
          Text {
            anchors.right: parent.right
            text: root.ipAddr || "—"
            color: root.fg
            font.family: root.fontFamily
            font.pixelSize: Style.font.bodySmall
          }
        }
        Item {
          width: parent.width
          height: pingLabel.implicitHeight
          Text {
            id: pingLabel
            anchors.left: parent.left
            text: "Ping"
            color: Color.muted
            font.family: root.fontFamily
            font.pixelSize: Style.font.bodySmall
          }
          Text {
            anchors.right: parent.right
            text: root.pingMs === "-" ? "—" : root.pingMs + " ms"
            color: root.fg
            font.family: root.fontFamily
            font.pixelSize: Style.font.bodySmall
          }
        }

        // ---- Signal / Down / Up: three graphs, one per line.
        Item {
          width: parent.width
          height: sigLabel.implicitHeight
          Text {
            id: sigLabel
            anchors.left: parent.left
            text: "Signal"
            color: Color.muted
            font.family: root.fontFamily
            font.pixelSize: Style.font.bodySmall
          }
          Text {
            anchors.right: parent.right
            text: root.modemState !== "" ? root.quality + "%" : "—"
            color: root.fg
            font.family: root.fontFamily
            font.pixelSize: Style.font.bodySmall
          }
        }
        Canvas {
          id: sigGraph
          width: parent.width
          height: Style.space(40)
          antialiasing: true
          onWidthChanged: requestPaint()
          onPaint: root.paintSeries(this, root.sigHist, 100, String(root.fg))
        }
        Item {
          width: parent.width
          height: downRateLabel.implicitHeight
          Text {
            id: downRateLabel
            anchors.left: parent.left
            text: "Down"
            color: Color.muted
            font.family: root.fontFamily
            font.pixelSize: Style.font.bodySmall
          }
          Text {
            anchors.right: parent.right
            text: root.fmtRate(root.rxRate)
            color: root.fg
            font.family: root.fontFamily
            font.pixelSize: Style.font.bodySmall
          }
        }
        Canvas {
          id: downGraph
          width: parent.width
          height: Style.space(40)
          antialiasing: true
          onWidthChanged: requestPaint()
          onPaint: root.paintSeries(this, root.rxHist, 0, String(root.fg))
        }
        Item {
          width: parent.width
          height: upRateLabel.implicitHeight
          Text {
            id: upRateLabel
            anchors.left: parent.left
            text: "Up"
            color: Color.muted
            font.family: root.fontFamily
            font.pixelSize: Style.font.bodySmall
          }
          Text {
            anchors.right: parent.right
            text: root.fmtRate(root.txRate)
            color: root.fg
            font.family: root.fontFamily
            font.pixelSize: Style.font.bodySmall
          }
        }
        Canvas {
          id: upGraph
          width: parent.width
          height: Style.space(40)
          antialiasing: true
          onWidthChanged: requestPaint()
          onPaint: root.paintSeries(this, root.txHist, 0, String(Color.muted))
        }
        PanelSeparator {}

        // ---- Totals.
        Item {
          width: parent.width
          height: rxLabel.implicitHeight
          Text {
            id: rxLabel
            anchors.left: parent.left
            text: "Downloaded"
            color: Color.muted
            font.family: root.fontFamily
            font.pixelSize: Style.font.bodySmall
          }
          Text {
            anchors.right: parent.right
            text: root.fmtBytes(root.rxBytes)
            color: root.fg
            font.family: root.fontFamily
            font.pixelSize: Style.font.bodySmall
          }
        }
        Item {
          width: parent.width
          height: txLabel.implicitHeight
          Text {
            id: txLabel
            anchors.left: parent.left
            text: "Uploaded"
            color: Color.muted
            font.family: root.fontFamily
            font.pixelSize: Style.font.bodySmall
          }
          Text {
            anchors.right: parent.right
            text: root.fmtBytes(root.txBytes)
            color: root.fg
            font.family: root.fontFamily
            font.pixelSize: Style.font.bodySmall
          }
        }

        // ---- Actions: toggle the data connection, or force a reconnect.
        Row {
          width: parent.width
          spacing: Style.space(8)

          Button {
            width: (parent.width - Style.space(8)) / 2
            text: "Data: " + (root.sampled ? (root.dataState === "up" ? "on" : "off") : "…")
            onClicked: {
              root.bar.run("fajita-cell-toggle")
              settle.restart()
            }
          }
          Button {
            width: (parent.width - Style.space(8)) / 2
            text: "Reconnect"
            onClicked: {
              root.bar.run("fajita-cell-reconnect")
              settle.restart()
            }
          }
        }
      }
    }
  }
}
