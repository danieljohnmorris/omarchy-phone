// ~/.config/fajita/calls.qml on the phone. Spawned on demand from the menu
// ("Calls" row) or by fajita-call-watch on call events; toggled by
// `quickshell -p ~/.config/fajita/calls.qml ipc call fajita-calls toggle`.
//
// A normal Hyprland window (xdg-toplevel), not a layer-shell overlay: it
// tiles like any other app. Keypad dialer when idle, live call rows
// (accept/decline/hang up) when ModemManager has calls. Everything shells
// out to fajita-call (mmcli); audio's FE/profile plumbing is q6voiced +
// fajita-call-watch; the output picker switches routes at runtime via
// fajita-call-route.
//
// Standalone Quickshell process, same pattern as notif.qml: first spawn
// shows itself, an existing instance answers ipc `toggle`, quits 15s after
// hiding so instances do not pile up.
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io

ShellRoot {
  id: root

  property bool open: false
  property var calls: []          // [{path,state,dir,number}]
  property string dial: ""        // number being typed
  property var callStart: ({})    // path -> epoch ms when first seen active
  property double now: 0          // bumped per second; re-evaluates duration bindings
  property string tab: "recents"  // idle view: "recents" | "keypad"
  property var log: []            // call log [{ts,dir,number,answered,dur}] oldest first
  property string callRoute: "earpiece" // live-call output: earpiece|speaker|headset
  property bool levelOn: true // mic strip on by default (asked-for feature); tap "level" to disable for a capture-free call
  property bool micMuted: false // uplink gated at the AFE capture mixers; seeded from kernel truth
  property var micHist: []    // "you": mic RMS 0..100 (dB-scaled), newest last
  property var sessHist: []   // "them": 1 = voice FE RUNNING (network sending media), 0.08 = silent
  readonly property int graphPoints: 60
  property string lastError: ""

  // Pre-load fallbacks only; every colour below is replaced from the active
  // Omarchy theme in the FileView. QML hex is #AARRGGBB — alpha first.
  property color cBg: "#ff111c18"
  property color cText: "#F7E8B2"
  property color cMuted: "#53685B"
  property color cAccent: "#509475"
  property color cRow: "#23372B"
  property color cGreen: "#549e6a"
  property color cRed: "#FF5345"

  // Palette from the active Omarchy theme, watched so a theme switch
  // repaints a live window without a restart (same as notif.qml).
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
      // Light themes: `muted` is near-invisible on their pale background
      // (rose-pine: #cecacd on #faf4ed), so secondary text switches to the
      // theme's dim-but-dark foreground there. Dark themes keep `muted`.
      var light = /^\s*mode\s*=\s*"light"/m.test(text)
      root.cBg = "#ff" + pick("dark_background", "#111c18").replace("#", "")
      root.cText = pick("bright_foreground", "#F7E8B2")
      root.cMuted = pick(light ? "dark_foreground" : "muted", "#53685B")
      root.cAccent = pick("accent", "#509475")
      root.cRow = pick("lighter_background", "#23372B")
      root.cGreen = pick("green", "#549e6a")
      root.cRed = pick("red", "#FF5345")
    }
  }

  function toggle() {
    root.open = !root.open
    if (root.open) {
      colors.reload() // stale palette if a theme switched while we ran hidden
      rescan.running = true // restarting a running Process re-runs it
      logLoad.running = true

      micQuery.running = true // seed the mute button from kernel state
      quitTimer.stop()
    }
  }
  Component.onCompleted: root.toggle() // first spawn: show + rescan immediately

  function run(cmd) { // fire-and-forget; errors surface via lastError
    root.lastError = ""
    proc.command = ["bash", "-lc", cmd]
    proc.running = true
  }

  // Call audio destination. fajita-call-route flips the hostless voice
  // FE's AFE mixers (no profile change, safe mid-call); optimistic set,
  // the csets are deterministic.
  function setRoute(r) {
    root.callRoute = r
    root.run("fajita-call-route " + r)
  }

  // Panel-style history painter (same shape as fajita.cellular Panel.qml):
  // baseline plus a right-aligned line, one series per canvas.
  function paintSeries(cv, data, fixedPeak, color) {
    var ctx = cv.getContext("2d")
    ctx.clearRect(0, 0, cv.width, cv.height)
    ctx.strokeStyle = String(root.cMuted)
    ctx.globalAlpha = 0.35
    ctx.lineWidth = 1
    ctx.beginPath()
    ctx.moveTo(0, cv.height - 0.5)
    ctx.lineTo(cv.width, cv.height - 0.5)
    ctx.stroke()
    ctx.globalAlpha = 1
    if (data.length < 2) return
    ctx.strokeStyle = color
    ctx.lineWidth = 1.5
    ctx.beginPath()
    for (var j = 0; j < data.length; j++) {
      var x = cv.width - (data.length - 1 - j) * (cv.width / (root.graphPoints - 1))
      var y = cv.height - 2 - (data[j] / fixedPeak) * (cv.height - 6)
      if (j === 0) ctx.moveTo(x, y)
      else ctx.lineTo(x, y)
    }
    ctx.stroke()
  }

  function stateText(state, path) {
    switch (state) {
      case "dialing": return "calling…"
      case "ringing-out": return "ringing…"
      case "incoming":
      case "ringing-in": return "incoming call"
      case "active":
        var s = Math.max(0, (root.now - (root.callStart[path] || root.now)) / 1000)
        return Math.floor(s / 60) + ":" + ("0" + Math.floor(s % 60)).slice(-2)
      case "held": return "on hold"
      case "terminated": return "ended"
      case "failed": return "call failed"
      default: return state
    }
  }

  function incoming(state) {
    return state === "incoming" || state === "ringing-in"
  }

  // Call-log formatting: "14/9 07:17" and "m:ss".
  function stamp(ts) {
    var d = new Date(ts * 1000)
    var hm = ("0" + d.getHours()).slice(-2) + ":" + ("0" + d.getMinutes()).slice(-2)
    return (d.getMonth() + 1) + "/" + d.getDate() + " " + hm
  }
  function durText(s) {
    return Math.floor(s / 60) + ":" + ("0" + Math.floor(s % 60)).slice(-2)
  }

  IpcHandler {
    target: "fajita-calls"

    function toggle(): void { root.toggle() }
    function show(): void { if (!root.open) root.toggle() }
    // theme-set.d hook pokes this on a theme switch: the FileView watches the
    // resolved colors.toml inode, which theme-set replaces, so a live window
    // repaints via IPC rather than waiting for the file watcher that never fires.
    function retint(): void { colors.reload() }
  }

  // Common runner for actions (start/accept/hangup).
  Process {
    id: proc
    running: false
    command: ["true"]

    stderr: SplitParser {
      onRead: data => { if (data.trim()) root.lastError = data.trim() }
    }
    onExited: rescan.running = true // reflect the new call state immediately
  }

  // Long-press dial paste: pull a dialable string off the clipboard. The
  // pipeline keeps only the first run of phone characters; non-dialable
  // clipboards produce nothing and the dial is untouched.
  Process {
    id: clipProc
    running: false
    command: ["bash", "-lc",
      "wl-paste --no-newline 2>/dev/null | grep -oE '[+0-9][0-9 ()-]*' | head -1"]
    stdout: SplitParser {
      onRead: line => {
        var s = line.trim()
        if ((s.replace(/[^0-9]/g, "").length >= 3) && root.dial.indexOf(s) < 0)
          root.dial += s
      }
    }
  }

  // fajita-call list poll. Lines accumulate into `out`; the swap happens in
  // one go on exit. Clearing root.calls per tick (the old shape) made the
  // keypad flash for the ~100ms each rescan takes while a call was live —
  // the dialer's visibility keys on list length.
  Process {
    id: rescan
    running: false
    command: ["bash", "-lc",
      "fajita-call list; echo __ACTIVE__; cat ~/.local/state/fajita/call-active 2>/dev/null; " +
      "echo __FE__; grep -m1 '^state' /proc/asound/card0/pcm6p/sub0/status 2>/dev/null"]
    property var out: []
    property bool inActive: false
    property bool inFe: false
    onRunningChanged: { out = []; inActive = false; inFe = false }
    stdout: SplitParser {
      onRead: data => {
        if (data.trim() === "__ACTIVE__") { rescan.inActive = true; return }
        if (data.trim() === "__FE__") { rescan.inActive = false; rescan.inFe = true; return }
        if (rescan.inFe) {
          // "Them": the hostless voice FE only enters RUNNING when the
          // network actually sends media — the one downlink observable
          // Linux has on this SoC (amplitude never becomes host PCM).
          var m = /^state:\s*(\S+)/.exec(data)
          if (m) {
            var t = root.sessHist.concat([m[1] === "RUNNING" ? 1 : 0.08])
            if (t.length > root.graphPoints) t = t.slice(t.length - root.graphPoints)
            root.sessHist = t
            sessGraph.requestPaint()
          }
          return
        }
        if (rescan.inActive) {
          // path|epoch from the watcher. Overwrites unconditionally: the
          // list lines above run first in this same stream and stamp
          // Date.now(), so a guarded seed would never win — a respawned
          // instance must take the watcher's first-active epoch instead,
          // every tick, or live-call durations restart at 0:00.
          var a = data.split("|")
          if (a.length === 2)
            root.callStart[a[0]] = parseInt(a[1], 10) * 1000
          return
        }
        var p = data.split("|")
        if (p.length < 4 || p[0].indexOf("/Call/") < 0) return
        var c = { path: p[0], state: p[1], dir: p[2], number: p[3] || "unknown" }
        if (c.state === "active" && !root.callStart[c.path]) root.callStart[c.path] = Date.now()
        rescan.out = rescan.out.filter(x => x.path !== c.path).concat(c)
      }
    }
    onExited: {
      var prev = root.calls
      root.calls = out
      if (out.length === 0 && prev.length > 0) {
        // A call ended. Incoming and never answered (caller gave up before
        // accept): the app was raised for it, close it instead of dropping
        // to the keypad. Anything else: land on recents with the new entry.
        var unanswered = prev.some(c => c.dir === "incoming" && !root.callStart[c.path])
        var connected = prev.some(c => root.callStart[c.path])
        if (unanswered && !connected) root.open = false
        else { root.tab = "recents"; logLoad.running = true }
      }
    }
  }

  // Recents: the watcher appends one JSON object per ended call to
  // ~/.local/state/fajita/calls.jsonl; this reads the tail.
  Process {
    id: logLoad
    running: false
    command: ["bash", "-lc", "tail -n 200 ~/.local/state/fajita/calls.jsonl 2>/dev/null"]
    onRunningChanged: if (running) root.log = []
    stdout: SplitParser {
      onRead: data => {
        try {
          var o = JSON.parse(data)
          if (o && o.ts) root.log = root.log.concat(o)
        } catch (e) { /* partial or non-JSON line: skip */ }
      }
    }
  }

  // Poll while open: far-end answers/hangups arrive as state changes we do
  // not otherwise observe, and the active-call timer needs a tick.
  Timer {
    interval: 1000
    repeat: true
    running: root.open
    onTriggered: if (!rescan.running) rescan.running = true
  }

  // Mic level over time, opt-in via the strip's chip: fajita-call-level
  // holds a persistent hw:0,1 capture (MultiMedia2, the bottom-mic path)
  // and prints one dB-scaled 0-100 value per 0.5s, which becomes one bar.
  // The voice FE itself is hostless and unreadable, and the earpiece leg
  // has no host tap at all, so the mic is the only measurable direction.
  // The capture shares SLIM TX7 with the voice uplink — it both contaminates
  // clean-call testing and keeps that port powered — which is exactly why it
  // runs only while enabled. The helper owns arecord and reaps it on
  // SIGTERM, so hw:0,1 is never left held by a dead replayer.
  Process {
    id: levelProbe
    running: root.open && root.calls.length > 0 && root.levelOn
    command: ["bash", "-lc", "exec fajita-call-level"]
    onRunningChanged: if (running) root.micHist = []
    stdout: SplitParser {
      onRead: data => {
        var n = parseInt(data.trim(), 10)
        if (isNaN(n)) return
        var t = root.micHist.concat([n])
        if (t.length > root.graphPoints) t = t.slice(t.length - root.graphPoints)
        root.micHist = t
        micGraph.requestPaint()
      }
    }
  }

  // Seed the mute button from kernel truth: the AFE gate outlives this
  // process, so a fresh instance must not assume "unmuted" — the uplink may
  // still be gated from an earlier call.
  Process {
    id: micQuery
    running: false
    command: ["bash", "-lc", "fajita-call-route mic-query"]
    stdout: SplitParser {
      onRead: data => { root.micMuted = data.trim() === "off" }
    }
  }
  // Duration clock: callStart is a plain object, so mutating it never
  // re-evaluates the duration binding above — a stuck "0:00". Bumping this
  // property every second does.
  Timer {
    id: clockTimer
    interval: 1000
    repeat: true
    running: root.open && root.calls.length > 0
    onTriggered: root.now = Date.now()
  }

  Timer {
    id: quitTimer
    interval: 15000
    onTriggered: Qt.quit()
  }
  onOpenChanged: if (!root.open) quitTimer.restart()

  // Closing the window must not orphan a live call: nothing else owns hang-up
  // once the app is gone (the watcher only raises UI, it never hangs up).
  // The hangup child must launch before the engine stops: run() only spawns
  // the Process child when the event loop pumps, so a same-turn Qt.quit()
  // can exit first and silently drop the hangup. closeAndHangup therefore
  // defers the quit by one timer tick instead of quitting inline.
  function closeAndHangup() {
    if (root.calls.length > 0)
      root.run("setsid -f fajita-call hangup-all >/dev/null 2>&1")
    root.open = false
    // One event-loop turn for the child to spawn, then quit (comment above).
    quitTimer0.restart()
  }

  Timer {
    id: quitTimer0
    interval: 50
    onTriggered: Qt.quit()
  }

  // A normal Hyprland window (xdg-toplevel), not a layer-shell overlay: it
  // tiles like any other app, so calls and messages sit side by side 50/50
  // and the bar keeps its reserved space.
  FloatingWindow {
    id: win
    title: "calls"
    color: root.cBg
    visible: root.open
    implicitWidth: 540
    implicitHeight: 1080
    // Any close path that hides the window (compositor close, menu Close
    // app) must not orphan a live call either — the ✕ button cannot be the
    // only one that hangs up. Idempotent with closeAndHangup. Clearing open
    // lets the quit timer reap the process instead of leaving a hidden one.
    onVisibleChanged: if (!visible) {
      if (root.calls.length > 0)
        root.run("setsid -f fajita-call hangup-all >/dev/null 2>&1")
      root.open = false
    }

    Rectangle {
      id: card
      anchors.fill: parent
      color: root.cBg

      ColumnLayout {
        id: col
        anchors.fill: parent
        anchors.margins: 16
        spacing: 12

        // Header
        RowLayout {
          Layout.fillWidth: true

          Text {
            text: root.calls.length > 0 ? "call" : "dial"
            color: root.cAccent
            font.family: "JetBrainsMono Nerd Font"
            font.pixelSize: 15
            Layout.fillWidth: true
          }

          Text {
            text: "✕"
            color: root.cMuted
            font.family: "JetBrainsMono Nerd Font"
            font.pixelSize: 18
            MouseArea {
              anchors.fill: parent
              anchors.margins: -14
              // A window, not an overlay: closing it closes the app — and
              // hangs up first if a call is live (see closeAndHangup).
              onClicked: root.closeAndHangup()
            }
          }
        }

        // Two live graphs, same shape as the cellular panel's:
        //   "you"  — mic level over time (fajita-call-level capture, dB-scaled
        //            0..100). Moves while you are audible into the call.
        //   "them" — the ADSP voice session. The hostless FE only enters
        //            RUNNING when the network actually sends media, so the
        //            line sits near zero until real call audio flows (its
        //            amplitude is not tappable on this SoC — state is the
        //            one honest downlink observable).
        // The chip toggles only the mic capture ("you"); "them" is read-only.
        ColumnLayout {
          visible: root.calls.length > 0
          Layout.fillWidth: true
          spacing: 4

          // "you" label + capture toggle sit directly above the mic graph.
          RowLayout {
            Layout.fillWidth: true
            spacing: 6
            Text {
              text: "you"
              color: root.levelOn ? root.cGreen : root.cMuted
              font.family: "JetBrainsMono Nerd Font"
              font.pixelSize: 10
            }
            Rectangle {
              id: levelChip
              Layout.preferredWidth: levelLbl.implicitWidth + 20
              Layout.preferredHeight: 22
              radius: 6
              color: root.levelOn ? root.cAccent : root.cRow
              Text {
                id: levelLbl
                anchors.centerIn: parent
                text: root.levelOn ? "mic on" : "mic off"
                color: root.levelOn ? root.cBg : root.cMuted
                font.family: "JetBrainsMono Nerd Font"
                font.pixelSize: 10
              }
              MouseArea {
                anchors.fill: parent
                onClicked: root.levelOn = !root.levelOn
              }
            }
            Item { Layout.fillWidth: true }
          }

          Canvas {
            id: micGraph
            Layout.fillWidth: true
            Layout.preferredHeight: 34
            onWidthChanged: requestPaint()
            onHeightChanged: requestPaint()
            onPaint: root.paintSeries(this, root.micHist, 100,
              root.levelOn ? String(root.cGreen) : String(root.cMuted))
          }

          // "them" label above its own graph, then the verdict caption: a
          // flat line is the honest result (no media) and must not read as a
          // broken graph.
          Text {
            Layout.fillWidth: true
            text: "them"
            color: root.cMuted
            font.family: "JetBrainsMono Nerd Font"
            font.pixelSize: 10
          }
          Canvas {
            id: sessGraph
            Layout.fillWidth: true
            Layout.preferredHeight: 34
            onWidthChanged: requestPaint()
            onHeightChanged: requestPaint()
            onPaint: root.paintSeries(this, root.sessHist, 1, String(root.cAccent))
          }
          Text {
            Layout.fillWidth: true
            horizontalAlignment: Text.AlignHCenter
            text: (root.sessHist.length && root.sessHist[root.sessHist.length - 1] > 0.5)
              ? "call audio flowing" : "no audio from network"
            color: (root.sessHist.length && root.sessHist[root.sessHist.length - 1] > 0.5)
              ? root.cGreen : root.cMuted
            font.family: "JetBrainsMono Nerd Font"
            font.pixelSize: 10
          }

        }


        // Live calls
        Repeater {
          model: root.calls

          ColumnLayout {
            required property var modelData
            Layout.fillWidth: true
            spacing: 10

            Text {
              text: modelData.number
              color: root.cText
              font.family: "JetBrainsMono Nerd Font"
              font.pixelSize: 24
              font.bold: true
              Layout.alignment: Qt.AlignHCenter
            }

            Text {
              text: root.stateText(modelData.state, modelData.path)
              color: modelData.state === "active" ? root.cGreen : root.cMuted
              font.family: "JetBrainsMono Nerd Font"
              font.pixelSize: 14
              Layout.alignment: Qt.AlignHCenter
            }

            // Incoming: accept / decline. Everything else: hang up.
            RowLayout {
              Layout.fillWidth: true
              spacing: 12

              Rectangle {
                visible: root.incoming(modelData.state)
                Layout.fillWidth: true
                height: 64
                radius: 10
                color: root.cGreen

                Text {
                  anchors.centerIn: parent
                  text: "accept"
                  color: root.cBg
                  font.family: "JetBrainsMono Nerd Font"
                  font.pixelSize: 16
                }
                MouseArea {
                  anchors.fill: parent
                  onClicked: root.run("fajita-call accept '" + modelData.path + "'")
                }
              }

              Rectangle {
                Layout.fillWidth: true
                height: 64
                radius: 10
                color: root.cRed

                Text {
                  anchors.centerIn: parent
                  text: root.incoming(modelData.state) ? "decline" : "hang up"
                  color: root.cBg
                  font.family: "JetBrainsMono Nerd Font"
                  font.pixelSize: 16
                }
                MouseArea {
                  anchors.fill: parent
                  onClicked: root.run("fajita-call hangup '" + modelData.path + "'")
                }
            }
            }

            // Output picker: earpiece / speaker / wired headset. Pure AFE
            // mixer switching (fajita-call-route), applies mid-call.
            RowLayout {
              Layout.fillWidth: true
              spacing: 8

              Repeater {
                model: ["earpiece", "speaker", "headset"]

                Rectangle {
                  required property string modelData
                  Layout.fillWidth: true
                  Layout.preferredHeight: 44
                  radius: 8
                  color: root.callRoute === modelData ? root.cAccent : root.cRow

                  Text {
                    anchors.centerIn: parent
                    text: modelData
                    color: root.callRoute === modelData ? root.cBg : root.cMuted
                    font.family: "JetBrainsMono Nerd Font"
                    font.pixelSize: 13
                  }
                  MouseArea {
                    anchors.fill: parent
                    onClicked: root.setRoute(modelData)
                  }
                }
              }
            }

            // Mic mute: gates the hostless uplink at the AFE capture mixers.
            Rectangle {
              Layout.fillWidth: true
              Layout.preferredHeight: 44
              radius: 8
              color: root.micMuted ? root.cRed : root.cRow

              Text {
                anchors.centerIn: parent
                text: root.micMuted ? "unmute mic" : "mute mic"
                color: root.micMuted ? root.cBg : root.cMuted
                font.family: "JetBrainsMono Nerd Font"
                font.pixelSize: 13
              }
              MouseArea {
                anchors.fill: parent
                onClicked: {
                  root.micMuted = !root.micMuted
                  root.run("fajita-call-route mic " + (root.micMuted ? "off" : "on"))
                }
              }
            }
          }
        }

        Text {
          visible: root.lastError !== ""
          text: root.lastError
          color: root.cRed
          font.family: "JetBrainsMono Nerd Font"
          font.pixelSize: 11
          wrapMode: Text.WrapAnywhere
          Layout.fillWidth: true
        }

        // Idle views: Recents (default) and Keypad, one visible at a time.
        // Both hide while any call is live.
        RowLayout {
          visible: root.calls.length === 0
          Layout.fillWidth: true
          spacing: 8

          Repeater {
            model: ["recents", "keypad"]

            Rectangle {
              required property string modelData
              Layout.fillWidth: true
              Layout.preferredHeight: 36
              radius: 8
              color: root.tab === modelData ? root.cRow : root.cBg
              border.width: 1
              border.color: root.tab === modelData ? root.cAccent : root.cBg

              Text {
                anchors.centerIn: parent
                text: modelData
                color: root.tab === modelData ? root.cText : root.cMuted
                font.family: "JetBrainsMono Nerd Font"
                font.pixelSize: 13
              }
              MouseArea {
                anchors.fill: parent
                onClicked: root.tab = modelData
              }
            }
          }
        }

        // Recents, newest first: direction glyph, number, answered/missed,
        // duration and date. Tap a row to call back.
        Flickable {
          visible: root.calls.length === 0 && root.tab === "recents"
          Layout.fillWidth: true
          Layout.fillHeight: true
          contentHeight: recentsCol.height
          clip: true

          ColumnLayout {
            id: recentsCol
            width: parent.width
            spacing: 6

            Text {
              visible: root.log.length === 0
              text: "no calls yet"
              color: root.cMuted
              font.family: "JetBrainsMono Nerd Font"
              font.pixelSize: 14
              Layout.fillWidth: true
              horizontalAlignment: Text.AlignHCenter
            }

            Repeater {
              model: root.log.slice().reverse()

              Rectangle {
                required property var modelData
                Layout.fillWidth: true
                Layout.preferredHeight: 58
                radius: 10
                color: root.cRow

                RowLayout {
                  anchors.fill: parent
                  anchors.margins: 10
                  spacing: 10

                  Text {
                    text: modelData.dir === "in" ? "↙" : "↗"
                    color: modelData.answered ? root.cGreen : root.cRed
                    font.family: "JetBrainsMono Nerd Font"
                    font.pixelSize: 18
                  }
                  ColumnLayout {
                    spacing: 2
                    Layout.fillWidth: true

                    Text {
                      text: modelData.number
                      color: modelData.answered ? root.cText : root.cRed
                      font.family: "JetBrainsMono Nerd Font"
                      font.pixelSize: 16
                      elide: Text.ElideRight
                      Layout.fillWidth: true
                    }
                    Text {
                      text: (!modelData.answered
                             ? (modelData.dir === "in" ? "missed" : "no answer")
                             : root.durText(modelData.dur)) + "  " + root.stamp(modelData.ts)
                      color: root.cMuted
                      font.family: "JetBrainsMono Nerd Font"
                      font.pixelSize: 11
                    }
                  }
                }
                MouseArea {
                  anchors.fill: parent
                  // Tap to call back. Short codes and alphanumerics excluded
                  // the same way the keypad's call button does.
                  onClicked: if (/^[+0-9][0-9 +()-]*$/.test(modelData.number)) {
                    root.run("fajita-call start '" + modelData.number + "'")
                  }
                }
              }
            }
          }
        }

        // Keypad (hidden while any call is live, or on the recents tab)
        ColumnLayout {
          visible: root.calls.length === 0 && root.tab === "keypad"
          Layout.fillWidth: true
          Layout.fillHeight: true
          spacing: 8

          Item {
            Layout.fillWidth: true
            Layout.bottomMargin: 4
            implicitHeight: dialText.implicitHeight

            Text {
              id: dialText
              anchors { left: parent.left; right: parent.right; verticalCenter: parent.verticalCenter }
              text: root.dial || "number"
              color: root.dial ? root.cText : root.cMuted
              font.family: "JetBrainsMono Nerd Font"
              font.pixelSize: 30
              elide: Text.ElideLeft
              horizontalAlignment: Text.AlignHCenter
            }
            MouseArea {
              anchors.fill: parent
              // Long-press pastes a dialable clipboard string into the dial
              // (filtered; anything else is a no-op).
              onPressAndHold: clipProc.running = true
            }
          }

          // Keypad: the five rows share whatever height the tile gives us, so
          // the app is usable full-screen and at half height in a 50/50 split.
          Repeater {
            model: [["1", "2", "3"], ["4", "5", "6"], ["7", "8", "9"], ["*", "0", "#"]]

            RowLayout {
              id: keyRow
              required property var modelData
              Layout.fillWidth: true
              Layout.fillHeight: true
              Layout.preferredHeight: 72
              Layout.maximumHeight: 110
              spacing: 8

              Repeater {
                model: keyRow.modelData

                Rectangle {
                  id: keyCell
                  required property string modelData
                  Layout.fillWidth: true
                  Layout.fillHeight: true
                  radius: 10
                  color: root.cRow

                  Text {
                    anchors.centerIn: parent
                    text: keyCell.modelData
                    color: root.cText
                    font.family: "JetBrainsMono Nerd Font"
                    font.pixelSize: Math.max(14, Math.min(26, keyCell.height * 0.4))
                  }
                  MouseArea {
                    anchors.fill: parent
                    onClicked: root.dial += keyCell.modelData
                  }
                }
              }
            }
          }

          // + (international prefix), backspace, call
          RowLayout {
            id: actionRow
            Layout.fillWidth: true
            Layout.fillHeight: true
            Layout.preferredHeight: 72
            Layout.maximumHeight: 110
            spacing: 8

            Rectangle {
              Layout.fillWidth: true
              Layout.fillHeight: true
              radius: 10
              color: root.cRow

              Text {
                anchors.centerIn: parent
                text: "+"
                color: root.cText
                font.family: "JetBrainsMono Nerd Font"
                font.pixelSize: Math.max(14, Math.min(26, actionRow.height * 0.4))
              }
              MouseArea {
                anchors.fill: parent
                onClicked: root.dial += "+"
              }
            }

            Rectangle {
              Layout.fillWidth: true
              Layout.fillHeight: true
              radius: 10
              color: root.cRow

              Text {
                anchors.centerIn: parent
                text: "⌫"
                color: root.cText
                font.family: "JetBrainsMono Nerd Font"
                font.pixelSize: Math.max(13, Math.min(24, actionRow.height * 0.36))
              }
              MouseArea {
                anchors.fill: parent
                onClicked: root.dial = root.dial.slice(0, -1)
              }
            }

            Rectangle {
              Layout.fillWidth: true
              Layout.fillHeight: true
              radius: 10
              color: root.dial.length >= 3 ? root.cGreen : root.cRow

              Text {
                anchors.centerIn: parent
                text: "call"
                color: root.dial.length >= 3 ? root.cBg : root.cMuted
                font.family: "JetBrainsMono Nerd Font"
                font.pixelSize: Math.max(12, Math.min(18, actionRow.height * 0.26))
              }
              MouseArea {
                anchors.fill: parent
                // Allow short service codes (e.g. voicemail) from 3 digits up.
                onClicked: if (root.dial.length >= 3) {
                  root.run("fajita-call start '" + root.dial.replace(/ /g, "") + "'")
                }
              }
            }
          }
        }
      }
    }
  }
}
