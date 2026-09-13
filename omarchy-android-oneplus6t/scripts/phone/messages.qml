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

  // The number the composer sends to: the open conversation, or whatever the
  // new-message screen has been addressed to.
  readonly property string target: root.screen === "new"
    ? root.toField.replace(/[ ()-]/g, "")
    : root.thread

  // Pre-load fallbacks only; every colour below is replaced from the active
  // Omarchy theme in the FileView. QML hex is #AARRGGBB — alpha first.
  property color cBg: "#f2111c18"
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
      root.cBg = "#f2" + pick("dark_background", "#111c18").replace("#", "")
      root.cText = pick("bright_foreground", "#F7E8B2")
      root.cMuted = pick("muted", "#53685B")
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

  // Navigation. Every screen except the list has a back path, and back always
  // lands on the list -- there is no deeper stack to unwind.
  function openThread(number) {
    root.thread = number
    root.screen = "thread"
    root.draft = ""
    root.lastError = ""
  }

  function compose() {
    root.screen = "new"
    root.thread = ""
    root.toField = ""
    root.draft = ""
    root.lastError = ""
  }

  function back() {
    root.screen = "list"
    root.thread = ""
    root.draft = ""
    root.toField = ""
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

  function send() {
    var number = root.target
    if (!number || !root.draft) return
    root.run("fajita-sms send " + root.sq(number) + " " + root.sq(root.draft))
    root.draft = ""
    // Sending from the new-message screen drops you into that conversation.
    root.thread = number
    root.screen = "thread"
    // The store gains the outgoing line as soon as the helper appends it;
    // reload shortly after rather than optimistically faking the row.
    sendSettle.restart()
  }

  Timer {
    id: sendSettle
    interval: 1200
    onTriggered: store.reload()
  }

  IpcHandler {
    target: "fajita-messages"

    function toggle(): void { root.toggle() }
    function show(): void { if (!root.open) root.toggle() }
    // The watcher raises a specific conversation on an incoming SMS.
    function open(number: string): void {
      root.openThread(number)
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
        ColumnLayout {
          visible: root.screen === "list"
          Layout.fillWidth: true
          Layout.fillHeight: true
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

          Item { Layout.fillHeight: true; Layout.fillWidth: true }

          Text {
            visible: root.messages.length === 0
            text: "no messages"
            color: root.cMuted
            font.family: "JetBrainsMono Nerd Font"
            font.pixelSize: 14
          }
        }

        // Screens 2 and 3 share the conversation view: an open thread, or the
        // history with whoever a new message is being addressed to.
        ColumnLayout {
          visible: root.screen !== "list"
          Layout.fillWidth: true
          Layout.fillHeight: true
          clip: true
          spacing: 6

          // Bubbles hug the bottom of whatever height the tile leaves us.
          Item { Layout.fillHeight: true; Layout.preferredHeight: 1 }

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

              Rectangle {
                Layout.maximumWidth: col.width * 0.78
                Layout.preferredWidth: Math.min(bubble.implicitWidth + 20, col.width * 0.78)
                height: bubble.implicitHeight + stampText.implicitHeight + 18
                radius: 8
                color: msgRow.modelData.dir === "out" ? root.cAccent : root.cRow

                Text {
                  id: bubble
                  anchors { left: parent.left; right: parent.right; top: parent.top; margins: 10 }
                  text: msgRow.modelData.text
                  color: msgRow.modelData.dir === "out" ? root.cBg : root.cText
                  font.family: "JetBrainsMono Nerd Font"
                  font.pixelSize: 14
                  wrapMode: Text.Wrap
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
            text: root.toField
            onTextChanged: root.toField = text
            color: root.cText
            font.family: "JetBrainsMono Nerd Font"
            font.pixelSize: 14
            inputMethodHints: Qt.ImhDialableCharactersOnly
            clip: true
            onAccepted: bodyInput.forceActiveFocus()

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
            onClicked: toInput.forceActiveFocus()
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
              text: root.draft
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
              onClicked: bodyInput.forceActiveFocus()
            }
          }

          Rectangle {
            width: 86
            height: 44
            radius: 8
            color: (root.draft && root.target) ? root.cGreen : root.cRow

            Text {
              anchors.centerIn: parent
              text: "send"
              color: (root.draft && root.target) ? root.cBg : root.cMuted
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
    }
  }
}
