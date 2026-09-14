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


# 11) Screensaver, phone port. Five upstream assumptions break on a phone:
#   a) The wait loop is scoped to the launching tty (`pgrep -t "$tty"`). With no
#      controlling tty (ssh, some launchers) it matches nothing, the inner loop
#      exits at once and the outer `while true` respawns ttfx forever: the
#      load-229 wedge. ttfx only runs under the screensaver, so wait on any
#      ttfx, and floor the respawn at 1/s so a broken engine cannot storm.
#   b) The focus check requires the window to be *active*. The OSK stealing
#      focus (or an ssh launch) makes it inactive, force-exiting the render
#      instantly. Require the window to exist instead.
#   c) foot's text-input focus auto-shows squeekboard over the render, and each
#      tap re-shows it, so a one-shot hide loses the race: re-assert it every
#      loop pass. NEVER stop/start squeekboard.service here - fajita-osk-start
#      spawns the primer as a visible foot window and only parks it ~4s later,
#      so cycling the service flashes a terminal onto the screen.
#   d) Taps are not keys, so `read -n1` never fires and there is no finger path
#      out of the render. Mouse click reporting turns a tap into stdin bytes.
#   e) exit must restore the OSK, or the rest of the session loses its keyboard.
S=/usr/bin/omarchy-screensaver
sudo cp -n "$S" "$S.orig" 2>/dev/null || true
sudo python3 - "$S" <<'PY11'
import sys
p = sys.argv[1]; s = open(p).read()
if "Phone port" in s:
    print("screensaver already patched"); sys.exit(0)

HIDE = 'busctl --user call sm.puri.OSK0 /sm/puri/OSK0 sm.puri.OSK0 SetVisible b false'
# squeekboard honours this key globally: with it false the panel never maps,
# even if something calls SetVisible true. Racing per-show hides always lost
# (foot activates text-input as it maps, before this script's first line).
A11Y = 'gsettings set org.gnome.desktop.a11y.applications screen-keyboard-enabled'
ENABLE = A11Y + ' true'

# b) window exists, not window focused
old = "  hyprctl activewindow -j | jq -e '.class == \"org.omarchy.screensaver\"' >/dev/null 2>&1\n"
assert old in s, "screensaver focus anchor not found; upstream omarchy-screensaver changed"
s = s.replace(old,
    "  # Phone port: require the window to EXIST, not be the active/focused\n"
    "  # client. Launched from ssh or when the OSK takes focus, the window is\n"
    "  # never \"active\" and the original check force-exited the render.\n"
    "  hyprctl clients -j | jq -e 'any(.[]; .class == \"org.omarchy.screensaver\")' >/dev/null 2>&1\n", 1)

# e) restore the OSK on exit. The render disables squeekboard through the
# a11y key (see the launcher patch); re-enable it here, then sweep the hide
# for a second so the primer regaining focus does not pop the panel on the
# way out - that was the "keyboard shows coming out of screensaver" flash.
old = "  pkill -f '[o]rg.omarchy.screensaver' 2>/dev/null\n"
assert old in s, "screensaver exit anchor not found"
s = s.replace(old, old +
    "  " + ENABLE + " >/dev/null 2>&1 || true\n"
    "  (for _ in 1 2 3 4 5 6 7 8 9 10; do\n"
    "     " + HIDE + " >/dev/null 2>&1 || true; sleep 0.1\n"
    "   done) >/dev/null 2>&1 &\n", 1)

# c+d) hide the OSK and enable mouse reporting BEFORE the resize wait. foot
# activates text-input the moment it maps, so squeekboard pops immediately;
# hiding after wait_for_terminal_resize left it on screen for that whole
# window (up to 2s) — the "keyboard shows briefly" flash.
old = "wait_for_terminal_resize\n"
assert old in s, "screensaver resize anchor not found"
s = s.replace(old,
    "# Phone port: foot text-input focus makes squeekboard auto-show over the\n"
    "# render. Hide it first (SetVisible; the Visible property is read-only).\n"
    + HIDE + " || true\n"
    "\n# Phone port: taps are not keys. Mouse click reporting turns any tap into\n"
    "# stdin bytes so the read below fires and the screensaver exits.\n"
    "printf '\\e[?1000h\\e[?1006h'\n\n" + old, 1)

# a+c) floor the respawn, drop the tty filter, re-assert the hide each pass
old = '  while pgrep -t "${tty#/dev/}" -x ttfx >/dev/null; do\n    if read -n1 -t 1'
assert old in s, "screensaver wait anchor not found"
s = s.replace(old,
    "  sleep 1\n"
    "  while pgrep -x ttfx >/dev/null; do\n"
    "    " + HIDE + " >/dev/null 2>&1 || true\n"
    "    if read -n1 -t 0.3", 1)

open(p, "w").write(s); print("patched screensaver")
PY11

# 12) Screensaver canvas: the OMARCHY banner is 81 columns wide. Measured
# column counts for this 540px-logical portrait panel (foot, JetBrainsMono):
# 18pt=23, 10pt=42, 9pt=46, 8pt=80, 7pt=95. So anything above 7pt clips —
# 8pt clips exactly one character, the trailing "Y". 7pt is the first size
# that fits, with margin. Upstream's wait_for_terminal_resize also only
# blocks while `stty size` reads exactly "24 80" and gives up after 2s, so on
# this slow device ttfx can still measure an 80-column pty and clip the
# trailing letter. Block until the resize actually widens the pty.
F=/usr/share/omarchy/default/foot/screensaver.ini
sudo cp -n "$F" "$F.orig" 2>/dev/null || true
sudo python3 - "$F" <<'PY12'
import sys, re
p = sys.argv[1]; s = open(p).read()
if "size=7" in s:
    print("screensaver font already patched"); sys.exit(0)
s2, n = re.subn(r"size=\d+", "size=7", s, count=1)
assert n == 1, "screensaver.ini font anchor not found"
open(p, "w").write(s2); print("patched screensaver font")
PY12
sudo python3 - "$S" <<'PY12B'
import sys
p = sys.argv[1]; s = open(p).read()
if "widen past 80 columns" in s:
    print("screensaver resize wait already patched"); sys.exit(0)
old = '  while ((SECONDS < deadline)) && [[ $(stty size 2>/dev/null) == "24 80" ]]; do\n'
assert old in s, "resize-wait anchor not found; upstream omarchy-screensaver changed"
new = ('  # Phone port: wait for the pty to actually widen past 80 columns, not\n'
       '  # just to leave the literal "24 80" state; ttfx measures once and a\n'
       '  # late resize clips the banner.\n'
       '  while ((SECONDS < deadline)) && [[ $(stty size 2>/dev/null | cut -d" " -f2) -le 80 ]]; do\n')
open(p, "w").write(s.replace(old, new, 1)); print("patched screensaver resize wait")
PY12B

# 13) Screensaver launcher: upstream's "already running" guard just exits, so
# re-selecting Screensaver while it renders does nothing - on a phone that
# leaves the render with no obvious way out. Make it a toggle-close.
L=/usr/bin/omarchy-launch-screensaver
sudo cp -n "$L" "$L.orig" 2>/dev/null || true
sudo python3 - "$L" <<'PY13'
import sys
p = sys.argv[1]; s = open(p).read()

A11Y = 'gsettings set org.gnome.desktop.a11y.applications screen-keyboard-enabled'
HIDE = 'busctl --user call sm.puri.OSK0 /sm/puri/OSK0 sm.puri.OSK0 SetVisible b false'

if "Phone port: re-selecting" in s:
    print("screensaver launcher already patched")
else:
    old = "pgrep -f '[o]rg.omarchy.screensaver' && exit 0\n"
    assert old in s, "launcher guard anchor not found; upstream omarchy-launch-screensaver changed"
    new = ("# Phone port: re-selecting Screensaver while it runs is a toggle-close.\n"
           "# Upstream just exited, leaving the render up with no finger path out.\n"
           "# Re-enable the OSK here too: this path bypasses exit_screensaver, and\n"
           "# leaving the a11y key false would cost the session its keyboard.\n"
           "if pgrep -f '[o]rg.omarchy.screensaver' >/dev/null; then\n"
           "  pkill -x ttfx 2>/dev/null\n"
           "  pkill -f '[o]rg.omarchy.screensaver' 2>/dev/null\n"
           "  " + A11Y + " true >/dev/null 2>&1 || true\n"
           "  " + HIDE + " || true\n"
           "  exit 0\n"
           "fi\n")
    open(p, "w").write(s.replace(old, new, 1)); print("patched screensaver launcher toggle")

# 13b) Suppress the OSK BEFORE foot is spawned. foot activates text-input the
# instant it maps, which is before omarchy-screensaver's first line runs, so a
# hide inside the render script can only ever catch up - measured 0.5s of
# visible keyboard, the "keyboard shows briefly going into screensaver" flash.
# The a11y key stops the panel mapping at all; exit_screensaver restores it.
s = open(p).read()
if "Phone port: pre-hide" not in s:
    old2 = "focused=$(omarchy-hyprland-monitor-focused)\n"
    assert old2 in s, "launcher monitor anchor not found"
    s = s.replace(old2,
        "# Phone port: pre-hide the OSK. foot takes text-input focus as it maps,\n"
        "# before the render script runs, so this has to happen out here. The\n"
        "# a11y key is authoritative: squeekboard will not map while it is false.\n"
        + A11Y + " false >/dev/null 2>&1 || true\n"
        + HIDE + " || true\n\n"
        + old2, 1)
    open(p, "w").write(s); print("patched screensaver launcher pre-hide")
PY13

# 14) Menu dismissal flashed the keyboard: the menu layer owns an active
# text-input, and on unmap the input-method deactivation trails the unmap, so
# squeekboard maps its layer and shows for ~0.9s before self-hiding. Assert the
# hide from the menu's own close handler instead of waiting for the deactivate.
M=/usr/share/omarchy/shell/plugins/menu/Menu.qml
sudo cp -n "$M" "$M.orig" 2>/dev/null || true
sudo python3 - "$M" <<'PY14'
import sys
p = sys.argv[1]; s = open(p).read()
if "fajitaOskHide" in s:
    print("menu osk hide already patched"); sys.exit(0)
anchor = '    // Phone port: squeekboard is raised over DBus, which never sets\n'
assert anchor in s, "menu probe anchor not found; run the menu osk gate section first"
s = s.replace(anchor,
    '    // Phone port: the menu layer owns an active text-input. On unmap the\n'
    '    // input-method deactivation trails the unmap, so squeekboard maps its\n'
    '    // layer and flashes before self-hiding. Assert the hide on close.\n'
    '    Process {\n'
    '      id: fajitaOskHide\n'
    '      command: ["busctl", "--user", "call", "sm.puri.OSK0", "/sm/puri/OSK0", "sm.puri.OSK0", "SetVisible", "b", "false"]\n'
    '    }\n' + anchor, 1)
old = '    onVisibleChanged: if (!visible) { cardTop = -1; maxRowsHeight = -1 }\n'
assert old in s, "menu onVisibleChanged anchor not found; upstream Menu.qml changed"
s = s.replace(old, '    onVisibleChanged: if (!visible) { cardTop = -1; maxRowsHeight = -1; fajitaOskHide.running = true }\n', 1)
open(p, "w").write(s); print("patched menu osk hide")
PY14

# 15) Notification card width: upstream sizes toasts for a desktop (380 style
# units). With this theme's spacing scale that exceeds the 540px logical
# screen, and the popup column anchors right, so the card hangs off the left
# edge ("SMS from +44…" clipped to "om +44…"). Clamp to the card's own screen
# minus toast margins; Layout.fillWidth inside reflows the text.
C=/usr/share/omarchy/shell/plugins/notifications/components/NotificationCard.qml
sudo cp -n "$C" "$C.orig" 2>/dev/null || true
sudo python3 - "$C" <<'PY15'
import re, sys
p=sys.argv[1]; s=open(p).read()
if "Screen.width - Style.gapsOut * 2" in s:
    print("already patched notification card"); sys.exit(0)
# Indentation-agnostic: the anchor was observed over ssh grep only, and a
# missed exact match would abort the whole patcher run half-applied.
m = re.search(r'^([ \t]*)implicitWidth: Style\.space\(380\)[ \t]*$', s, re.M)
assert m, "notification card width anchor not found; upstream NotificationCard.qml changed"
i = m.group(1)
new = (f"{i}// Phone port: clamp to the screen so the card cannot overflow the panel\n"
       f"{i}// (upstream's 380 assumes a desktop monitor). Popup margins are gapsOut.\n"
       f"{i}implicitWidth: Math.min(Style.space(380), Screen.width - Style.gapsOut * 2)")
s = s[:m.start()] + new + s[m.end():]
open(p,"w").write(s); print("patched notification card")
PY15
omarchy-restart-shell >/dev/null 2>&1 || true
# the shell remaps its bar; restart the clock row so it lands beneath it again
systemctl --user reset-failed waybar.service 2>/dev/null || true
# waybar has StartLimitIntervalSec=300/Burst=3: repeated restarts (e.g. several
# patcher runs in a row) trip the limit and the clock row silently stays dead.
systemctl --user is-active --quiet waybar.service && systemctl --user restart waybar.service || true
echo "shell restarted"
