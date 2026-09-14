// ~/.config/fajita/messages.qml on the phone. Spawned on demand from the menu
// ("Messages" row) or by fajita-call-watch on an incoming SMS; toggled by
// `quickshell -p ~/.config/fajita/messages.qml ipc call fajita-messages toggle`,
// and `... ipc call fajita-messages open +44…` opens one conversation.
//
// A normal Hyprland window (xdg-toplevel), not a layer-shell overlay, so it
// tiles 50/50 beside calls.qml and focused text inputs raise squeekboard --
// the app draws no keys of its own.
//
// Three screens, one back path: list -> conversation -> new message.
// Reads ~/.local/state/fajita/messages.jsonl (written only by fajita-sms) and
// sends through `fajita-sms send`. Quits 15s after hiding so instances do not
// pile up; the watcher respawns it on the next SMS.
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io

ShellRoot {
  id: root

  property bool open: false
  property var messages: []        // [{ts,dir,number,text}] oldest first
  property string screen: "list"   // "list" | "thread" | "new"
  property string thread: ""       // conversation's number while screen=="thread"
  property string draft: ""
  property string toField: ""
  property string lastError: ""
  property bool sending: false     // a submit is in flight (can take ~25s)
  property string pendingNumber: "" // tel: target the action sheet is about

  // Same canonicalisation as fajita-sms' canon(): the helper files every
  // message under E.164, so a composer addressed "07700900123" must resolve to
  // "+447700900123" or the sent message lands in a thread this screen is not
  // filtering for and appears to vanish.
  function canon(s) {
    if (/[^0-9+ ()-]/.test(s)) return s          // alphanumeric sender: verbatim
    const n = s.replace(/[ ()-]/g, "")
    if (n.charAt(0) === "+") return n
    if (n.slice(0, 2) === "00") return "+" + n.slice(2)
    if (/^0[1-9]/.test(n)) return "+" + root.cc + n.slice(1)
    if (/^[0-9]/.test(n)) return n.length >= 9 ? "+" + n : n   // short code
    return n
  }
  // "#aarrggbb" -> "#rrggbb" for rich-text <font color=...> (Qt rich text
  // rejects the 8-digit form).
  function hex(c) {
    var s = c.toString()
    return "#" + s.substr(s.length - 6, 6)
  }

  // Phone numbers in bubble text become tel: links. A run of digits joined
  // by (). - separators links whole when its digit count is a plausible
  // E.164 (9-15); longer runs are a number glued to a date/count by spaces
  // ("447700900123 (1) 2026-09-13 23") and only their contiguous digit
  // strings of phone length link, so the date stays plain text.
  function linkify(s, isOut) {
    var esc = s.replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;")
    var lc = hex(isOut ? root.cBg : root.cAccent)
    return esc.replace(/\+?[0-9][0-9 ().-]*[0-9]/g, function (run) {
      var digits = run.replace(/[^0-9]/g, "")
      if (digits.length >= 9 && digits.length <= 15)
        return '<u><a href="tel:' + run.replace(/[^0-9+]/g, "") + '">' +
          '<font color="' + lc + '">' + run + '</font></a></u>'
      return run.replace(/\+?[0-9]{9,15}/g, function (n) {
        return '<u><a href="tel:' + n + '"><font color="' + lc + '">' + n + '</font></a></u>'
      })
    })
  }
  readonly property string cc: "44"

  // The number the composer sends to: the open conversation, or whatever the
  // new-message screen has been addressed to.
  readonly property string target: root.screen === "new"
    ? root.canon(root.toField)
    : root.thread

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
  // repaints a live surface without a restart (same as calls.qml).
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

  // The store. fajita-sms appends; watchChanges makes an incoming SMS appear
  // while the app is open without any polling.
  FileView {
    id: store
    path: Quickshell.env("HOME") + "/.local/state/fajita/messages.jsonl"
    watchChanges: true
    onFileChanged: reload()
    onLoaded: {
      var out = []
      var lines = store.text().split("\n")
      for (var i = 0; i < lines.length; i++) {
        if (!lines[i].trim()) continue
        try { out.push(JSON.parse(lines[i])) } catch (e) { /* partial write */ }
      }
      out.sort(function (a, b) { return a.ts - b.ts })
      root.messages = out
    }
  }

  function toggle() {
    root.open = !root.open
    if (root.open) {
      colors.reload() // stale palette if a theme switched while we ran hidden
      store.reload()
      quitTimer.stop()
    } else {
      quitTimer.restart()
    }
  }
  Component.onCompleted: root.toggle() // first spawn: show immediately

  // Quit a while after being hidden: the watcher respawns us on the next SMS,
  // so a resident process would only hold memory (same as notif.qml).
  Timer {
    id: quitTimer
    interval: 15000
    onTriggered: if (!root.open) Qt.quit()
  }

  function sq(s) { // single-quote for bash -lc
    return "'" + String(s).replace(/'/g, "'\\''") + "'"
  }

  function run(cmd) { // fire-and-forget; errors surface via lastError
    root.lastError = ""
    proc.command = ["bash", "-lc", cmd]
    proc.running = true
  }

  // Focus a text input AND raise the OSK. Text-input activation alone does
  // not flip squeekboard's Visible once its relay has gone stale (layout
  // reloads on tap, panel never maps), so set it over the bus explicitly.
  function focusInput(item) {
    item.forceActiveFocus()
    root.run("fajita-osk-show")
  }

  // Long-press paste: probe the clipboard, and if it holds anything offer a
  // chip above the composer. Insertion happens at the held field's cursor.
  property var pasteTarget: null
  property string clipText: ""
  function probePaste(field) {
    root.pasteTarget = field
    root.clipLines = []
    clipProc.running = true
  }
  property var clipLines: []
  function doPaste() {
    if (root.pasteTarget && root.clipText)
      root.pasteTarget.insert(root.pasteTarget.cursorPosition, root.clipText)
    root.clipText = ""
    root.pasteTarget = null
  }

  // Navigation. Every screen except the list has a back path, and back always
  // lands on the list -- there is no deeper stack to unwind.
  function openThread(number, focus) {
    // Canon here too: the IPC entry point (`fajita-app messages open 07…`,
    // used by the watcher and the dialer hand-off) may pass a raw dialled form.
    root.thread = root.canon(number)
    root.screen = "thread"
    bodyInput.clear()
    // Focus is opt-in: the watcher opens a thread on every incoming SMS, and
    // an arriving text must not pop the keyboard over whatever is on screen.
    if (focus !== false) focusInput(bodyInput)
    root.lastError = ""
  }

  function compose() {
    root.screen = "new"
    root.thread = ""
    toInput.clear()
    bodyInput.clear()
    root.lastError = ""
    focusInput(toInput)
  }


  function back() {
    root.screen = "list"
    root.thread = ""
    bodyInput.clear()
    toInput.clear()
    root.lastError = ""
    store.reload()
  }

  // Thread list: one row per number, newest first, with its last message.
  function threads() {
    var seen = {}
    var out = []
    for (var i = root.messages.length - 1; i >= 0; i--) {
      var m = root.messages[i]
      if (seen[m.number]) continue
      seen[m.number] = true
      out.push({ number: m.number, text: m.text, ts: m.ts, dir: m.dir })
    }
    return out
  }

  // Conversation for whatever number is in play: addressing a new message to
  // someone you have history with shows that history straight away.
  function conversation() {
    var out = []
    if (!root.target) return out
    for (var i = 0; i < root.messages.length; i++)
      if (root.messages[i].number === root.target) out.push(root.messages[i])
    return out
  }

  function stamp(ts) {
    var d = new Date(ts * 1000)
    var now = new Date()
    var hm = ("0" + d.getHours()).slice(-2) + ":" + ("0" + d.getMinutes()).slice(-2)
    if (d.toDateString() === now.toDateString()) return hm
    return (d.getMonth() + 1) + "/" + d.getDate() + " " + hm
  }

  // A submit can take ~25s and can fail (this SIM's network refuses it), so
  // never destroy what the user typed until the helper has exited 0. Clearing
  // optimistically made a rejected send look like the message just vanished.
  function send() {
    if (!root.target || !root.draft || root.sending) return
    root.lastError = ""
    root.sending = true
    // Wire form is what the user typed (only whitespace/punctuation stripped);
    // every send that this network has accepted used the dialled national
    // form, so canon() is kept off the mmcli argument. The store is still
    // canonical: fajita-sms' append() canonicalises on the way in.
    var wire = root.screen === "new"
      ? root.toField.replace(/[ ()-]/g, "")
      : root.thread
    root.thread = root.target
    root.screen = "thread"
    sendProc.command = ["bash", "-lc",
      "fajita-sms send " + root.sq(wire) + " " + root.sq(root.draft)]
    sendProc.running = true
  }

  Process {
    id: sendProc
    running: false
    command: ["true"]
    stderr: SplitParser {
      onRead: data => { if (data.trim()) root.lastError = data.trim() }
    }
    onExited: code => {
      root.sending = false
      if (code === 0) {
        bodyInput.clear() // the text is in the store now; safe to drop
        store.reload()
      } else if (root.lastError === "") {
        root.lastError = "send failed (exit " + code + ")"
      }
    }
  }

  // wl-paste for the long-press chip. Lines accumulate and join on exit; an
  // empty clipboard yields an empty string and the chip simply never shows.
  Process {
    id: clipProc
    running: false
    command: ["bash", "-lc", "wl-paste --no-newline 2>/dev/null; true"]
    stdout: SplitParser {
      onRead: data => { root.clipLines.push(data) }
    }
    onExited: {
      root.clipText = root.clipLines.join("\n")
      if (root.clipText.trim() === "") root.clipText = ""
    }
  }

  IpcHandler {
    target: "fajita-messages"

    function toggle(): void { root.toggle() }
    function show(): void { if (!root.open) root.toggle() }
    // Poked by the theme-set.d hook (see calls.qml for the inode story).
    function retint(): void { colors.reload() }
    // The watcher raises a specific conversation on an incoming SMS. No
    // focus: see openThread — an arriving text must not raise the keyboard.
    function open(number: string): void {
      root.openThread(number, false)
      if (!root.open) root.toggle()
    }
  }

  Process {
    id: proc
    running: false
    command: ["true"]
    stderr: SplitParser {
      onRead: data => { if (data.trim()) root.lastError = data.trim() }
    }
  }

  FloatingWindow {
    id: win
    title: "messages"
    color: root.cBg
    visible: root.open
    implicitWidth: 540
    implicitHeight: 1080

    Rectangle {
      id: card
      anchors.fill: parent
      color: root.cBg

      // Escape backs out of a screen, closes the app from the list.
      Item {
        anchors.fill: parent
        focus: true
        Keys.onEscapePressed: root.screen === "list" ? Qt.quit() : root.back()
      }

      ColumnLayout {
        id: col
        anchors.fill: parent
        anchors.margins: 16
        spacing: 10

        // Header: back chip on every screen but the list, title, new, close.
        RowLayout {
          Layout.fillWidth: true
          spacing: 10

          Rectangle {
            visible: root.screen !== "list"
            Layout.preferredWidth: 64
            Layout.preferredHeight: 36
            radius: 8
            color: root.cRow

            Text {
              anchors.centerIn: parent
              text: "← all"
              color: root.cText
              font.family: "JetBrainsMono Nerd Font"
              font.pixelSize: 13
            }
            MouseArea {
              anchors.fill: parent
              onClicked: root.back()
            }
          }

          Text {
            text: root.screen === "new"
              ? (root.target || "new message")
              : (root.screen === "thread" ? root.thread : "messages")
            color: root.screen === "list" ? root.cMuted : root.cText
            font.family: "JetBrainsMono Nerd Font"
            font.pixelSize: root.screen === "list" ? 13 : 16
            elide: Text.ElideRight
            Layout.fillWidth: true
          }

          Rectangle {
            visible: root.screen === "list"
            Layout.preferredWidth: 64
            Layout.preferredHeight: 36
            radius: 8
            color: root.cRow

            Text {
              anchors.centerIn: parent
              text: "new"
              color: root.cAccent
              font.family: "JetBrainsMono Nerd Font"
              font.pixelSize: 13
            }
            MouseArea {
              anchors.fill: parent
              onClicked: root.compose()
            }
          }

          Text {
            text: "✕"
            color: root.cMuted
            font.family: "JetBrainsMono Nerd Font"
            font.pixelSize: 18
            MouseArea {
              anchors.fill: parent
              anchors.margins: -14
              // A window, not an overlay: closing it closes the app.
              onClicked: Qt.quit()
            }
          }
        }

        // Screen 1: thread list
        Flickable {
          visible: root.screen === "list"
          Layout.fillWidth: true
          Layout.fillHeight: true
          clip: true
          contentWidth: width
          contentHeight: listCol.implicitHeight
          boundsBehavior: Flickable.StopAtBounds

          ColumnLayout {
            id: listCol
            width: parent.width
            spacing: 6

          Repeater {
            model: root.threads()

            Rectangle {
              id: threadRow
              required property var modelData
              Layout.fillWidth: true
              height: 66
              radius: 8
              color: root.cRow

              ColumnLayout {
                anchors.fill: parent
                anchors.margins: 10
                spacing: 2

                RowLayout {
                  Layout.fillWidth: true

                  Text {
                    text: threadRow.modelData.number
                    color: root.cText
                    font.family: "JetBrainsMono Nerd Font"
                    font.pixelSize: 14
                    Layout.fillWidth: true
                    elide: Text.ElideRight
                  }

                  Text {
                    text: root.stamp(threadRow.modelData.ts)
                    color: root.cMuted
                    font.family: "JetBrainsMono Nerd Font"
                    font.pixelSize: 11
                  }
                }

                Text {
                  text: (threadRow.modelData.dir === "out" ? "› " : "") +
                        threadRow.modelData.text.replace(/\n/g, " ")
                  color: root.cMuted
                  font.family: "JetBrainsMono Nerd Font"
                  font.pixelSize: 12
                  elide: Text.ElideRight
                  Layout.fillWidth: true
                }
              }

              MouseArea {
                anchors.fill: parent
                onClicked: root.openThread(threadRow.modelData.number)
              }
            }
          }

            // Empty state sits with the (absent) rows, not pinned to the floor.
            Text {
              visible: root.messages.length === 0
              text: "no messages"
              color: root.cMuted
              font.family: "JetBrainsMono Nerd Font"
              font.pixelSize: 14
              Layout.alignment: Qt.AlignHCenter
              Layout.topMargin: 24
            }
          }
        }

        // Screens 2 and 3 share the conversation view: an open thread, or the
        // history with whoever a new message is being addressed to.
        Flickable {
          id: convFlick
          visible: root.screen !== "list"
          Layout.fillWidth: true
          Layout.fillHeight: true
          clip: true
          contentWidth: width
          contentHeight: convCol.implicitHeight
          boundsBehavior: Flickable.StopAtBounds
          // The newest message is the one that matters: stay on the floor as
          // the thread grows, instead of stranding the user at the top.
          onContentHeightChanged: contentY = Math.max(0, contentHeight - height)

          ColumnLayout {
            id: convCol
            width: parent.width
            spacing: 6

          Text {
            visible: root.conversation().length === 0
            text: root.screen === "new" && !root.target
              ? "address it below, then type"
              : "no messages yet"
            color: root.cMuted
            font.family: "JetBrainsMono Nerd Font"
            font.pixelSize: 13
            Layout.alignment: Qt.AlignHCenter
          }

          Repeater {
            model: root.conversation()

            RowLayout {
              id: msgRow
              required property var modelData
              Layout.fillWidth: true

              Item { Layout.fillWidth: msgRow.modelData.dir === "out"; Layout.preferredWidth: 1 }

              // A layout decides this item's geometry, so the bubble must
              // publish implicit sizes: a plain `height` is overridden and the
              // rows collapse into each other with the text spilling out.
              // Size against the flickable's column, the actual parent — the
              // outer card is wider once its margins are in play. The cap is
              // the layout's job; implicitWidth is the unwrapped text width,
              // which the layout then clamps and the Text wraps into.
              Rectangle {
                Layout.maximumWidth: convCol.width * 0.78
                implicitWidth: bubble.implicitWidth + 20
                implicitHeight: bubble.implicitHeight + stampText.implicitHeight + 18
                radius: 8
                color: msgRow.modelData.dir === "out" ? root.cAccent : root.cRow
                Text {
                  id: bubble
                  anchors { left: parent.left; right: parent.right; top: parent.top; margins: 10 }
                  textFormat: Text.RichText
                  text: root.linkify(msgRow.modelData.text, msgRow.modelData.dir === "out")
                  color: msgRow.modelData.dir === "out" ? root.cBg : root.cText
                  font.family: "JetBrainsMono Nerd Font"
                  font.pixelSize: 14
                  wrapMode: Text.Wrap

                  MouseArea {
                    anchors.fill: parent
                    // Tap a tel: link -> action sheet (call / message / copy).
                    // Taps on plain text fall through to nothing; drags still
                    // scroll the Flickable.
                    onClicked: {
                      var l = bubble.linkAt(mouse.x, mouse.y)
                      if (String(l).indexOf("tel:") === 0)
                        root.pendingNumber = l.substring(4)
                    }
                  }
                }

                Text {
                  id: stampText
                  anchors { right: parent.right; bottom: parent.bottom; margins: 6 }
                  text: root.stamp(msgRow.modelData.ts)
                  color: msgRow.modelData.dir === "out" ? root.cBg : root.cMuted
                  opacity: 0.7
                  font.family: "JetBrainsMono Nerd Font"
                  font.pixelSize: 10
                }
              }

              Item { Layout.fillWidth: msgRow.modelData.dir === "in"; Layout.preferredWidth: 1 }
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

        // Recipient field (new message only). A real TextInput: this is an
        // xdg-toplevel, so focusing it activates text-input-v3 and squeekboard
        // raises itself -- an in-app key grid would be a second keyboard.
        Rectangle {
          visible: root.screen === "new"
          Layout.fillWidth: true
          height: 44
          radius: 8
          color: root.cRow
          border.width: toInput.activeFocus ? 1 : 0
          border.color: root.cAccent

          TextInput {
            id: toInput
            anchors { left: parent.left; right: parent.right; verticalCenter: parent.verticalCenter; margins: 10 }
            // The input owns its text: binding `text:` to a property would be
            // destroyed by the first keystroke, and clear() would stop working.
            onTextChanged: root.toField = text
            color: root.cText
            font.family: "JetBrainsMono Nerd Font"
            font.pixelSize: 14
            inputMethodHints: Qt.ImhDialableCharactersOnly
            clip: true
            onAccepted: focusInput(bodyInput)
            Text {
              anchors.fill: parent
              visible: toInput.text === ""
              text: "to: number"
              color: root.cMuted
              font: toInput.font
              verticalAlignment: Text.AlignVCenter
            }
          }
          MouseArea {
            anchors.fill: parent
            onClicked: focusInput(toInput)
            // Long-press offers the clipboard (chip above the composer).
            onPressAndHold: probePaste(toInput)
          }
        }

        // Clipboard chip: long-pressing either field sets it; tap inserts at
        // the held field's cursor, ✕ dismisses.
        Rectangle {
          visible: root.clipText !== "" && root.screen !== "list"
          Layout.fillWidth: true
          Layout.preferredHeight: 40
          radius: 8
          color: root.cAccent

          RowLayout {
            anchors.fill: parent
            anchors.margins: 8
            spacing: 8

            Text {
              Layout.fillWidth: true
              text: "paste  " + root.clipText.replace(/\s+/g, " ").slice(0, 48)
              color: root.cBg
              elide: Text.ElideRight
              font.family: "JetBrainsMono Nerd Font"
              font.pixelSize: 13
            }
            Text {
              text: "✕"
              color: root.cBg
              font.pixelSize: 15
              MouseArea {
                anchors.fill: parent
                anchors.margins: -10
                onClicked: { root.clipText = ""; root.pasteTarget = null }
              }
            }
          }
          MouseArea {
            anchors.fill: parent
            // The ✕ has its own area; only bare chip taps paste.
            z: -1
            onClicked: root.doPaste()
          }
        }

        // Draft + send
        RowLayout {
          visible: root.screen !== "list"
          Layout.fillWidth: true
          spacing: 8

          Rectangle {
            Layout.fillWidth: true
            height: 44
            radius: 8
            color: root.cRow
            border.width: bodyInput.activeFocus ? 1 : 0
            border.color: root.cAccent

            TextInput {
              id: bodyInput
              anchors { left: parent.left; right: parent.right; verticalCenter: parent.verticalCenter; margins: 10 }
              onTextChanged: root.draft = text
              color: root.cText
              font.family: "JetBrainsMono Nerd Font"
              font.pixelSize: 14
              clip: true
              // Enter on the OSK sends, like every other messaging app.
              onAccepted: root.send()

              Text {
                anchors.fill: parent
                visible: bodyInput.text === ""
                text: "message"
                color: root.cMuted
                font: bodyInput.font
                verticalAlignment: Text.AlignVCenter
              }
            }
            MouseArea {
              anchors.fill: parent
              onClicked: focusInput(bodyInput)
              onPressAndHold: probePaste(bodyInput)
            }
          }

          Rectangle {
            Layout.preferredWidth: 86
            Layout.preferredHeight: 44
            radius: 8
            // Idle-looking for 25s reads as a dead button, so the in-flight
            // state is explicit.
            color: root.sending ? root.cRow
                 : (root.draft && root.target) ? root.cGreen : root.cRow

            Text {
              anchors.centerIn: parent
              text: root.sending ? "…" : "send"
              color: root.sending ? root.cAccent
                   : (root.draft && root.target) ? root.cBg : root.cMuted
              font.family: "JetBrainsMono Nerd Font"
              font.pixelSize: 14
            }
            MouseArea {
              anchors.fill: parent
              onClicked: root.send()
            }
          }
        }
      }

      // Phone-number action sheet: tapping a tel: link in a bubble sets
      // pendingNumber; the sheet offers the three useful actions. Tap the
      // scrim to dismiss.
      Rectangle {
        anchors.fill: parent
        visible: root.pendingNumber !== ""
        z: 5
        color: "#99000000" // theme-agnostic: dim whatever is behind

        MouseArea {
          anchors.fill: parent
          onClicked: root.pendingNumber = ""
        }

        Rectangle {
          anchors.centerIn: parent
          width: 340
          height: sheetCol.implicitHeight + 20
          radius: 12
          color: root.cBg
          border.width: 1
          border.color: root.cRow

          ColumnLayout {
            id: sheetCol
            anchors { top: parent.top; left: parent.left; right: parent.right; margins: 10 }
            spacing: 8

            Text {
              Layout.fillWidth: true
              Layout.topMargin: 4
              text: root.pendingNumber
              color: root.cMuted
              horizontalAlignment: Text.AlignHCenter
              font.family: "JetBrainsMono Nerd Font"
              font.pixelSize: 12
            }
            Repeater {
              model: [
                { verb: "call",    hint: "start a call to this number" },
                { verb: "message", hint: "send a message to this number" },
                { verb: "copy",    hint: "copy the number" }
              ]

              Rectangle {
                id: sheetBtn
                required property var modelData
                Layout.fillWidth: true
                Layout.preferredHeight: 48
                radius: 8
                color: root.cRow

                RowLayout {
                  anchors.fill: parent
                  anchors.margins: 12
                  spacing: 10

                  Text {
                    text: sheetBtn.modelData.verb
                    color: root.cAccent
                    font.family: "JetBrainsMono Nerd Font"
                    font.pixelSize: 14
                  }
                  Text {
                    Layout.fillWidth: true
                    text: sheetBtn.modelData.hint
                    color: root.cText
                    opacity: 0.8
                    font.family: "JetBrainsMono Nerd Font"
                    font.pixelSize: 12
                    elide: Text.ElideRight
                  }
                }
                MouseArea {
                  anchors.fill: parent
                  onClicked: {
                    var n = root.pendingNumber
                    root.pendingNumber = ""
                    if (sheetBtn.modelData.verb === "call")
                      root.run("fajita-call start " + root.sq(n) + "; fajita-app calls")
                    else if (sheetBtn.modelData.verb === "message")
                      root.openThread(n)
                    else
                      root.run("wl-copy " + root.sq(n))
                  }
                }
              }
            }
          }
        }
      }
    }
  }
}
