#!/bin/bash
# Re-apply the phone patches to Omarchy's shipped Quickshell shell.
# Run on the phone after any omarchy package upgrade (pacman overwrites /usr/share/omarchy).
set -euo pipefail
P=/usr/share/omarchy/shell/Ui/KeyboardPanel.qml
sudo cp -n "$P" "$P.orig" 2>/dev/null || true
sudo python3 - "$P" <<'PY'
import sys
p=sys.argv[1]; s=open(p).read()
if "Qt.inputMethod && Qt.inputMethod.visible" in s or "fajitaOskUp" in s:
    print("already patched"); sys.exit(0)
old="""  mask: Region {
    width: root.screenW
    height: root.screenH
  }"""
new="""  mask: Region {
    width: root.screenW
    height: root.screenH
    // Phone port: the on-screen keyboard sits on the same overlay layer as this
    // full-screen dismissal surface, so the first tap on a key registers as an
    // "outside click" and closes the panel before anything is typed. Subtract
    // the keyboard strip - but only while the input method is actually up.
    // Unconditional, the strip dead-zones the bottom quarter of the screen:
    // taps there fall through the mask and never dismiss the panel.
    regions: [
      Region {
        x: 0
        y: (Qt.inputMethod && Qt.inputMethod.visible) ? root.screenH - 315 : root.screenH
        width: root.screenW
        height: (Qt.inputMethod && Qt.inputMethod.visible) ? 315 : 0
        intersection: Intersection.Subtract
      }
    ]
  }"""
# Migrate a file patched by the older script (unconditional carve-out).
s2 = s.replace("        y: root.screenH - 315\n", "        y: (Qt.inputMethod && Qt.inputMethod.visible) ? root.screenH - 315 : root.screenH\n", 1)
s2 = s2.replace("        height: 315\n", "        height: (Qt.inputMethod && Qt.inputMethod.visible) ? 315 : 0\n", 1)
if s2 != s:
    open(p,"w").write(s2); print("migrated to conditional"); sys.exit(0)
assert old in s, "anchor not found; upstream KeyboardPanel.qml changed"
open(p,"w").write(s.replace(old,new,1)); print("patched")
PY
# 2) Menu rows: pointer-only handlers ignore finger taps on a layer surface.
M=/usr/share/omarchy/shell/plugins/menu/Menu.qml
sudo cp -n "$M" "$M.orig" 2>/dev/null || true
sudo python3 - "$M" <<'PY2'
import sys
p=sys.argv[1]; s=open(p).read()
if "acceptedDevices: PointerDevice.TouchScreen" in s:
    print("menu already patched"); sys.exit(0)
old="""                onClicked: {
                  root.cursorActive = true
                  root.selectedIndex = row.index
                  root.activateIndex(row.index, true)
                }
              }"""
new=old+"""

              // Phone port: the MouseArea above only sees pointer events, and a
              // finger tap on this layer surface never synthesizes one, so the
              // menu could not be used by touch. Handle the touchscreen here.
              TapHandler {
                acceptedDevices: PointerDevice.TouchScreen
                gesturePolicy: TapHandler.ReleaseWithinBounds
                onTapped: {
                  root.cursorActive = true
                  root.selectedIndex = row.index
                  root.activateIndex(row.index, true)
                }
              }"""
assert old in s, "menu anchor not found; upstream Menu.qml changed"
open(p,"w").write(s.replace(old,new,1)); print("patched menu")
PY2

# 3) Image picker (theme and background selectors): laptop-fixed geometry.
I=/usr/share/omarchy/shell/plugins/image-picker/ImagePicker.qml
sudo cp -n "$I" "$I.orig" 2>/dev/null || true
sudo python3 - "$I" <<'PY3'
import sys
p=sys.argv[1]; s=open(p).read()
if "fajitaFit" in s:
    print("image picker already patched"); sys.exit(0)
old="""  property int expandedWidth: 768
  property int expandedHeight: 475
  property int sliceWidth: 108
  property int sliceHeight: 432
  property int sliceSpacing: -30
  property int skewOffset: 28"""
new="""  // Phone port: these were fixed at laptop size, so the 768-wide preview hung
  // off both edges of a 540px panel (the card is capped at panel width - 80)
  // and the theme picker could not be used. Scale the whole coverflow by the
  // width the panel actually has. The factor is capped at 1, so anything at
  // least 868 logical pixels wide keeps upstream's exact numbers.
  property real fajitaFit: Math.min(1, ((panel.width > 0 ? panel.width : 1920) - 100) / 768)
  property int expandedWidth: Math.round(768 * fajitaFit)
  property int expandedHeight: Math.round(475 * fajitaFit)
  property int sliceWidth: Math.round(108 * fajitaFit)
  property int sliceHeight: Math.round(432 * fajitaFit)
  property int sliceSpacing: Math.round(-30 * fajitaFit)
  property int skewOffset: Math.round(28 * fajitaFit)"""
assert old in s, "image picker anchor not found; upstream ImagePicker.qml changed"
open(p,"w").write(s.replace(old,new,1)); print("patched image picker")
PY3

# 4) Workspaces: numeric labels become dots — filled for focused, small dot for
# occupied, hollow for empty — like the concept shell. Narrower buttons so the
# bar keeps room for the centre clock on a 540px panel.
W=/usr/share/omarchy/shell/plugins/bar/widgets/Workspaces.qml
sudo cp -n "$W" "$W.orig" 2>/dev/null || true
sudo python3 - "$W" <<'PY4'
import sys
p=sys.argv[1]; s=open(p).read()
if "fajitaDots" in s:
    print("workspaces already patched"); sys.exit(0)
old="""        text: focused ? "\\uDB85\\uDCFB" : (modelData === 10 ? "0" : String(modelData))
        opacity: occupied || focused ? 1 : 0.5
        horizontalMargin: 6
        verticalPadding: 6
        fixedWidth: root.vertical ? root.barSize : Style.space(20)"""
new="""        // Phone port: dots instead of digits (concept shell). Filled = focused,
        // small dot = has windows, hollow = empty. Narrower hit targets fit the
        // 540px bar with a centre clock.
        text: focused ? "\\u25CF" : (occupied ? "\\u2022" : "\\u25CB")
        opacity: occupied || focused ? 1 : 0.5
        horizontalMargin: 6
        verticalPadding: 6
        readonly property bool fajitaDots: true
        fixedWidth: root.vertical ? root.barSize : Style.space(14)"""
assert old in s, "workspaces anchor not found; upstream Workspaces.qml changed"
open(p,"w").write(s.replace(old,new,1)); print("patched workspaces")
PY4

# 5) Clock: left tap opens the phone's notification center (notif.qml) instead
# of the calendar panel. Right = cycle format and middle = timezone stay.
C=/usr/share/omarchy/shell/plugins/panels/clock/BarWidget.qml
sudo cp -n "$C" "$C.orig" 2>/dev/null || true
sudo python3 - "$C" <<'PY5'
import sys
p=sys.argv[1]; s=open(p).read()
if "fajita-notif" in s:
    print("clock already patched"); sys.exit(0)
old="""      else root.togglePanel()"""
new="""      else Quickshell.execDetached(["bash", "-lc", "quickshell -p ~/.config/fajita/notif.qml ipc call fajita-notif toggle 2>/dev/null || quickshell -p ~/.config/fajita/notif.qml"]) // fajita-notif"""
assert old in s, "clock anchor not found; upstream clock BarWidget.qml changed"
open(p,"w").write(s.replace(old,new,1)); print("patched clock")
PY5

# 6) Power: left tap opens the phone's quick settings (quicksettings.qml)
# instead of the built-in battery panel. Right = percentage stays.
PP=/usr/share/omarchy/shell/plugins/panels/power/Panel.qml
sudo cp -n "$PP" "$PP.orig" 2>/dev/null || true
sudo python3 - "$PP" <<'PY6'
import sys
p=sys.argv[1]; s=open(p).read()
if "fajita-qs" in s:
    print("power already patched"); sys.exit(0)
old="""      if (b === Qt.RightButton) root.togglePercentage()
      else root.toggle()"""
new="""      if (b === Qt.RightButton) root.togglePercentage()
      else Quickshell.execDetached(["bash", "-lc", "quickshell -p ~/.config/fajita/quicksettings.qml ipc call fajita-qs toggle 2>/dev/null || quickshell -p ~/.config/fajita/quicksettings.qml"]) // fajita-qs"""
assert old in s, "power anchor not found; upstream power Panel.qml changed"
open(p,"w").write(s.replace(old,new,1)); print("patched power")
PY6

# 7) Idle lock: the session lock is a pocket brick on touch (no keyboard can
# render above ext-session-lock), so the idle timer and menu Lock row both get
# the concept lock screen instead (fajita-lock-screen → lock.qml, swipe to
# unlock).
D=/usr/share/omarchy/shell/plugins/services/idle/Service.qml
sudo cp -n "$D" "$D.orig" 2>/dev/null || true
sudo python3 - "$D" <<'PY7'
import sys
p=sys.argv[1]; s=open(p).read()
if "fajita-lock-screen" in s:
    print("idle lock already patched"); sys.exit(0)
old='''runProcess(lockProcess, "lock", "omarchy-system-lock")'''
new='''runProcess(lockProcess, "lock", "/home/dan/.local/bin/fajita-lock-screen")'''
assert old in s, "idle anchor not found; upstream idle Service.qml changed"
open(p,"w").write(s.replace(old,new,1)); print("patched idle lock")
PY7

# 8) Menu: the scrim MouseArea behind the card only sees pointer events on
# this build — touch taps outside the card did nothing. Add a TapHandler so
# tapping outside closes the menu, like a desktop click already does.
M=/usr/share/omarchy/shell/plugins/menu/Menu.qml
sudo cp -n "$M" "$M.orig" 2>/dev/null || true
sudo python3 - "$M" <<'PY8'
import sys
p=sys.argv[1]; s=open(p).read()
if "fajita-menu-tap2" in s:
    print("menu tap already patched"); sys.exit(0)
# v1 gated nothing: the handler ate taps on the on-screen keyboard (which
# covers the bottom 315px) and dismissed the menu mid-typing. v2 ignores
# anything in the OSK strip.
s = s.replace("} // fajita-menu-tap", "}", 1)  # drop v1 handler if present
s = s.replace("""    TapHandler {
      gesturePolicy: TapHandler.ReleaseWithinBounds
      onTapped: root.cancel()
    }""", "", 1)
old="""    MouseArea {
      anchors.fill: parent
      onClicked: root.cancel()
    }"""
new=old+"""

    // Phone port: touch taps never synthesize MouseArea clicks here. Taps in
    // the bottom 315px are the OSK strip — never treat them as outside-taps.
    TapHandler {
      id: fajitaTap
      gesturePolicy: TapHandler.ReleaseWithinBounds
      onTapped: function(button) {
        if (fajitaTap.point.position.y > fajitaTap.parent.height - 315) return
        root.cancel()
      }
    } // fajita-menu-tap2"""
assert old in s, "menu scrim anchor not found; upstream Menu.qml changed"
open(p,"w").write(s.replace(old,new,1)); print("patched menu tap")
PY8



# 9) Notification toasts: clear the waybar clock row (second 34px bar at y=43)
# that upstream's barClearance (omarchy bar + gap only) knows nothing about.
N=/usr/share/omarchy/shell/plugins/notifications/Service.qml
sudo cp -n "$N" "$N.orig" 2>/dev/null || true
sudo python3 - "$N" <<'PY9'
import sys
p=sys.argv[1]; s=open(p).read()
old="  readonly property int barClearance: liveBarSize + Style.gapsOut"
new="""  // Phone port: the waybar clock row sits directly under Omarchy's bar;
  // toasts must clear both or they cover the clock.
  readonly property int barClearance: liveBarSize + 34 + Style.gapsOut"""
if new.splitlines()[-1] in s:
    print("already patched notifications"); sys.exit(0)
assert old in s, "notifications anchor not found; upstream Service.qml changed"
open(p,"w").write(s.replace(old,new,1)); print("patched notifications")
PY9

# 10) OSK gate: squeekboard is raised over DBus (fajita-osk-toggle), which never
# sets Qt.inputMethod.visible, so both outside-tap gates above were wrong in
# opposite directions: the keyboard-strip carve-out never applied while typing,
# and the menu ignored every tap in the bottom 315px whether the keyboard was
# up or not (thumb-height taps on the wallpaper did nothing). Poll squeekboard's
# real Visible property instead.
sudo python3 - <<'PY10'
PROBE = """  // Phone port: squeekboard is raised over DBus, which never sets
  // Qt.inputMethod.visible, so poll its real visibility.
  property bool fajitaOskUp: false
  Process {
    id: fajitaOskProbe
    command: ["busctl", "--user", "get-property", "sm.puri.OSK0", "/sm/puri/OSK0", "sm.puri.OSK0", "Visible"]
    stdout: SplitParser { onRead: line => OWNER.fajitaOskUp = line.indexOf("true") >= 0 }
  }
  Timer {
    // Only while the surface is actually up: a permanent 400ms busctl spawn
    // would burn battery for a property nothing reads the rest of the time.
    interval: 400; repeat: true; running: OWNER_LIVE; triggeredOnStart: true
    onTriggered: fajitaOskProbe.running = true
  }
"""

k = "/usr/share/omarchy/shell/Ui/KeyboardPanel.qml"
s = open(k).read()
if "fajitaOskUp" in s:
    print("keyboard panel osk gate already patched")
else:
    assert "Qt.inputMethod && Qt.inputMethod.visible" in s, "run section 1 first"
    if "import Quickshell.Io" not in s:
        s = s.replace("import Quickshell\n", "import Quickshell\nimport Quickshell.Io\n", 1)
    s = s.replace("  mask: Region {", PROBE.replace("OWNER_LIVE", "root.open").replace("OWNER", "root") + "\n  mask: Region {", 1)
    s = s.replace("(Qt.inputMethod && Qt.inputMethod.visible) ? root.screenH - 315 : root.screenH",
                  "root.fajitaOskUp ? root.screenH - 315 : root.screenH")
    s = s.replace("(Qt.inputMethod && Qt.inputMethod.visible) ? 315 : 0", "root.fajitaOskUp ? 315 : 0")
    open(k, "w").write(s)
    print("patched keyboard panel osk gate")

m = "/usr/share/omarchy/shell/plugins/menu/Menu.qml"
s = open(m).read()
if "fajitaOskUp" in s:
    print("menu osk gate already patched")
else:
    old = "        if (fajitaTap.point.position.y > fajitaTap.parent.height - 315) return\n"
    assert old in s, "menu tap anchor not found; run section 8 first"
    s = s.replace(old, "        if (panel.fajitaOskUp && fajitaTap.point.position.y > fajitaTap.parent.height - 315) return\n", 1)
    tail = "    } // fajita-menu-tap2\n"
    assert tail in s
    body = "\n".join("  " + l if l.strip() else l for l in PROBE.replace("OWNER_LIVE", "panel.visible").replace("OWNER", "panel").split("\n"))
    s = s.replace(tail, tail + body, 1)
    open(m, "w").write(s)
    print("patched menu osk gate")
PY10

omarchy-restart-shell >/dev/null 2>&1 || true
# the shell remaps its bar; restart the clock row so it lands beneath it again
systemctl --user reset-failed waybar.service 2>/dev/null || true
# waybar has StartLimitIntervalSec=300/Burst=3: repeated restarts (e.g. several
# patcher runs in a row) trip the limit and the clock row silently stays dead.
systemctl --user is-active --quiet waybar.service && systemctl --user restart waybar.service || true
echo "shell restarted"
