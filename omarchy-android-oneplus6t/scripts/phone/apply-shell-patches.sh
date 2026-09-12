#!/bin/bash
# Re-apply the phone patches to Omarchy's shipped Quickshell shell.
# Run on the phone after any omarchy package upgrade (pacman overwrites /usr/share/omarchy).
set -euo pipefail
P=/usr/share/omarchy/shell/Ui/KeyboardPanel.qml
sudo cp -n "$P" "$P.orig" 2>/dev/null || true
sudo python3 - "$P" <<'PY'
import sys
p=sys.argv[1]; s=open(p).read()
old="""  mask: Region {
    width: root.screenW
    height: root.screenH
  }"""
new="""  mask: Region {
    width: root.screenW
    height: root.screenH
    // Phone port: the on-screen keyboard shares this overlay layer, so a tap on
    // a key counts as an outside click and closes the panel before anything is
    // typed. Subtract the keyboard strip so taps reach squeekboard instead.
    regions: [
      Region {
        x: 0
        y: root.screenH - 315
        width: root.screenW
        height: 315
        intersection: Intersection.Subtract
      }
    ]
  }"""
if new.split("\n")[3] in s:
    print("already patched"); sys.exit(0)
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



omarchy-restart-shell >/dev/null 2>&1 || true
# the shell remaps its bar; restart the clock row so it lands beneath it again
sleep 6; systemctl --user restart waybar.service 2>/dev/null || true
echo "shell restarted"
