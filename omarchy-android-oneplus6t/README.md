# Omarchy on a OnePlus 6T (fajita)

This boots a OnePlus 6T into Arch Linux ARM, Hyprland 0.56 and Omarchy 4
Quattro instead of Android. It overwrites one boot slot and the userdata
partition; OxygenOS's system partitions stay, and the bootloader can fall back
to them if the Arch slot is never marked successful. The kernel is postmarketOS's prebuilt
`linux-postmarketos-qcom-sdm845` 6.16.7 with the fajita device tree, and
everything above it is Arch installed with pacman.

I haven't forked Omarchy or Arch. This assembles them: build scripts, the config
that lands on the phone, and a few patches to Omarchy's touch handling, which
are kept re-appliable because package upgrades overwrite them. What works and
what doesn't is at the bottom.

## Layout

- `scripts/build-rootfs.sh`: run inside the privileged arm64 Docker container
  (`fajita-build`, `work/` mounted at `/work`). Produces `work/out/rootfs.img`
  (16 GB ext4, label `archroot`) and `work/out/boot.img`.
- `scripts/rootfs/`: files that go into the image. mkinitcpio config, the
  `fajitaroot` initcpio hook, USB gadget service, networkd config.
- `scripts/build-hyprland.sh`: rebuilds Hyprland from the Arch PKGBUILD inside
  the chroot (ALARM's binary lags aquamarine's soname).
- `scripts/build-qcom-services.sh`: pd-mapper, tqftpserv (linux-msm GitHub) and
  the sdm845-mainline ALSA UCM profiles. Wi-Fi does not appear without pd-mapper.
- `scripts/build-ttfx.sh`: compiles the Rust `ttfx` effects engine for aarch64
  in an arm64 Docker container (native on Apple Silicon). Prerequisite: Docker
  running on the build host.
- `scripts/flash.sh`: runs on the host. `unlock`, `boot-test` or `flash` via fastboot.
- `scripts/phone-setup.sh`: Omarchy layer + phone adaptations over ssh.
- `scripts/phone/`: the phone-side files (Lua overrides, bash_profile, proxy env, hooks).
- `scripts/shot.sh`: screenshot the phone's Hyprland session over USB.
- `work/` (gitignored): tarballs, pmOS apks, images, Omarchy checkout, packages.

## Things that cost me a day

- **The bootloader fell back to Android after a week of reboots.** The 6T is
  an A/B device and Qualcomm's bootloader gives each slot 7 boot attempts until
  the OS marks the slot successful, which Android does and this install did
  not. When slot B hit zero it booted the untouched OxygenOS in slot A, whose
  init then wanted to "repair" our rootfs on userdata. `fajita-slot-ok` sets
  the successful bit with `sfdisk --part-attrs` from the post-boot hook, and
  `flash.sh` now writes the boot image to both slots. Android's system and
  vendor partitions are still on the phone; this install does not remove them.
- **`hyprctl dispatch` is Lua on Hyprland 0.56.** `hyprctl dispatch closewindow
  address:0x...` is a silent no-op; it has to be
  `hyprctl dispatch 'hl.dsp.window.close({ window = "address:0x..." })'`.
  The keyboard primer sat visible on workspace 1 until its two calls were
  rewritten.
- **Hyprland's donation popup is not a window.** It is an internal surface
  ~900px wide with its close button off the phone's screen, so no window rule
  can size it. `ecosystem.no_donation_nag = true` in `looknfeel.lua`.
- **Omarchy floats are 875x600 and centred, which is laptop shaped.** On a
  540x1170 phone the width overflowed by a third, so the update prompt's
  "press any key" sat off the right edge; `looknfeel.lua` sizes the
  `floating-window` tag and the About window to 518x960. Centring is left
  alone: a floating window centred in the 1093px band ends at y=944 while
  the on-screen keyboard starts at 855, so its bottom 89px — the line you
  have to read — hid behind the keys. Shrinking cannot fix that, because a
  centred window just recentres lower. `fajita-osk-fit` watches
  `PropertiesChanged` on `sm.puri.OSK0` `Visible` and drops the floating bit
  while the keyboard is up: Hyprland then tiles the window into the reserved
  area (`[12, 89] [516, 754]`, bottom 843) and does the arithmetic itself.
- **Chromium's first launch demands a new keyring.** Omarchy's
  `chromium-flags.conf` sets `--password-store=gnome-libsecret`, so gcr-prompter
  pops a two-password "choose a password" dialog — unanswerable on a phone with
  no keyboard, and the on-screen keyboard covers it. The phone's copy of that
  file ships in the repo with `--password-store=basic` instead. The file is not
  owned by any package, so nothing but `check-sync.sh` would have caught it.
- **Web pages are cut off on the right unless GTK text scaling is exactly
  1.0.** Chromium sizes its Wayland buffer as logical size x
  `org.gnome.desktop.interface text-scaling-factor`, and Hyprland crops the
  overflow, so at the phone's 1.6364 (set by `omarchy display text size` for a
  5.5in panel) about a third of every page painted off-screen. It is not a
  layout problem: `innerWidth`, `clientWidth` and `scrollWidth` were all 480
  with nothing overflowing, and a local page with a full-width box was clipped
  too. `--force-device-scale-factor` does not help — it moves
  `devicePixelRatio`, not the widget scale that sizes the surface. Setting the
  factor to 1.0 costs nothing elsewhere: the bar reads `shell.toml [font]
  base-size` (20) and the terminals their own point size (15), both unaffected.
  Readability comes back through Chromium's page zoom (1.35x in
  `Default/Preferences`), which scales layout and so cannot clip. Do not raise
  GTK `font-name` for this: it inflates some widget strings and not others, so
  a tab title renders huge next to a small URL. Re-run the block in
  `phone-setup.sh` after any `omarchy display text size`, which rewrites the
  factor.
- **Chromium announces itself as a desktop.** The default UA is
  `X11; Linux x86_64` and `navigator.userAgentData.mobile` is false, so sites
  serve their desktop layout into a 480 CSS-px viewport — Wikipedia's Vector
  skin wants ~1000px and ran off the edge. The flags file sets a Pixel 7 UA,
  which brings up the mobile skin. **The value must be quoted**: the launcher
  splits that file on whitespace, so an unquoted UA arrives as a dozen
  arguments and Chromium opens the fragments as URLs (the window title comes
  up as `(linux;`). Only the UA *string* changes; Chromium has no flag for
  User-Agent Client Hints, so `userAgentData.mobile` stays false and sites
  sniffing UA-CH (mostly Google's own) still serve desktop.
- **`gum` is keyboard-only, so no yes/no prompt can be tapped.** gum 2.0.0
  emits no mouse-reporting sequences at all (verified: 464 bytes of output from
  `gum confirm`, none of `?1000h`/`?1002h`/`?1003h`/`?1006h`), so touch cannot
  reach `omarchy-update`'s Yes. `/usr/local/bin/gum` is a shim that routes
  `confirm` and single-select `choose` to `omarchy-menu-select`, Omarchy's
  Quickshell picker, which is touch-driven, and `exec`s the real
  `/usr/bin/gum` for everything else. It must be in `/usr/local/bin`:
  `~/.local/bin` sits *after* `/usr/bin` in the phone's PATH.
- **The theme and background pickers are laid out in fixed laptop pixels.**
  `ImagePicker.qml` hardcodes a 768x475 preview plus thirteen 108px side
  slices, roughly 1780px, so on a 540px panel only a slice of one preview is
  on screen and nothing can be aimed at. `apply-shell-patches.sh` adds a
  `fajitaFit` factor, `min(1, (panel - 100) / 768)`, and scales every one of
  those constants by it, so the picker fits any panel and stays untouched on a
  laptop. Re-run that script after any omarchy package upgrade.
- **Theme previews are 1800x1012 desktop screenshots.** They are illegible at
  540 wide and show the thing that does not change on a phone; each theme also
  ships 2-9 wallpapers, which are what is actually visible. The
  `/usr/local/bin/omarchy-theme-switcher` shim builds its preview cache from
  each theme's first wallpaper instead, then hands the directory to the same
  `omarchy-menu-images`.
- **Theme is mirrored into the System menu.** With no keyboard the only menu
  that can be summoned is the power key's `omarchy-menu toggle system`, so
  `omarchy-menu.jsonc` adds `system.theme` with Omarchy's own `style.theme`
  action. The `system.` prefix is what puts a row in that group: the merge
  infers `parent` from the id.
- **An empty workspace is indistinguishable from a dead phone.** A tiling
  compositor draws nothing when no window is open, and the laptop answer
  (SUPER+RETURN) needs a keyboard. `empty-hint.qml`, run by
  `empty-hint.service` as its own Quickshell process, draws the empty state
  and a "launch something" button that summons Omarchy's touch-driven apps
  menu. It is standalone rather than a plugin under `/usr/share/omarchy`, so a
  pacman upgrade cannot overwrite it and `apply-shell-patches.sh` need not
  know about it. It sits on `WlrLayer.Bottom` so a real window always paints
  over it, and its `mask` is the button alone, so it cannot eat a tap the way
  the keyboard panel's full-screen dismissal region did.
- **Suspend never resumes, so Menu > Suspend is "Screen off".** The
  `system.suspend` menu row is overridden to `fajita-screen-off` (DPMS off),
  and `bindings.lua` rebinds the power key to `fajita-power-key`: wake if the
  panel is off, otherwise Omarchy's power menu. `key_press_enables_dpms` and
  `mouse_move_enables_dpms` are off so only the power key wakes it.
- **Never shut the phone down: a clean poweroff cannot be undone with the
  power button.** After `systemctl poweroff` (or Menu > Shutdown, which
  `cfacc3b` made work) a normal Power press does nothing at all — no vibrate,
  no network, no fastboot, and no USB descriptor of any kind for over two
  minutes, so it is not EDL either. Battery is not the cause: fastboot
  reported `battery-voltage: 4325` and `battery-soc-ok: yes`. Recovery is
  cable-in (the PMIC cold-boots on charger attach), a 20-25 s Power hold, or
  the fastboot combo followed by `fastboot reboot`. The `system.shutdown` row
  is upstream's and shown deliberately: a phone whose own power menu cannot
  power it off reads as broken, and the recovery paths are documented above.
  `systemctl poweroff` over ssh remains available when a host is at hand.
- **The power key reaches logind and then dies there, so a dark panel looks
  like a dead phone.** logind logged 16 `Power key pressed short` events across
  one 5 h 44 m boot while `fajita-power-key` ran zero times. `HandlePowerKey`
  is `ignore` in two places (`10-fajita-nosuspend.conf` and
  `10-ignore-power-button.conf`), which correctly defers to Hyprland, but the
  compositor that owns the panel had **no keyboard devices and no bind
  referencing power** (`hyprctl devices`, `hyprctl binds`) — `bindings.lua`'s
  `XF86PowerOff` bind was never loaded. Suspect the login compositor, whose
  input devices `5073a35` hides and which never sources `bindings.lua`; the
  wake path is therefore inert whenever the session is not fully logged in.
  Diagnose with `journalctl | grep "Power key"` versus `hyprctl binds`, never
  by pressing the button.
- **Fastboot on a Mac needs a USB 2.0-only cable**, the sort that comes with a
  phone. USB 3 cables work fine for adb, then the bootloader silently fails to
  appear and you assume the phone is broken.
- **`system_profiler SPUSBDataType` is useless for this on macOS**: it can
  return zero bytes in 0.1 s with the phone plainly attached, which reads as
  "no USB device" and is indistinguishable from a dead phone. Use
  `ioreg -p IOUSB -w0` instead — the gadget shows as
  `OnePlus 6T (Arch Linux ARM)`, vendor `OnePlus`, `idVendor 7531`. Two wrong
  conclusions in one session came from trusting the former.
- **The host end of the USB net does not always get a lease.** The phone is
  static `172.16.42.1` with `DHCPServer=yes` (`rootfs/10-usb0.network`), so
  when `en16` sits on a self-assigned `169.254.x` address the phone's
  `systemd-networkd` has not configured `usb0` yet. The link being `active`
  proves nothing about it. Fix from the host without waiting:
  `sudo ifconfig en16 inet 172.16.42.9 netmask 255.255.255.0 alias`.
- **ssh over IPv6 link-local needs no address, no lease and no sudo.** When the
  host end has no `172.16.42.x` (see above) the gadget is still a working
  ethernet link, so the phone is reachable at its link-local address with
  nothing configured:

  ```
  ping6 -c3 ff02::1%en16                     # phone answers alongside the host
  ssh dan@fe80::7059:80ff:fe3f:2cc9%en16     # the non-permanent one in `ndp -an`
  ```

  `ndp -an` labels the host's own address `permanent`; the other entry is the
  phone. This unblocked an entire session that had otherwise stalled on a macOS
  sudo password. The suffix is derived from the gadget MAC, so it is stable
  until `usb-gadget.sh` regenerates one, and it changes nothing on the phone.
  Link-local addresses do drop on every gadget re-enumeration: a command that
  returns "No route to host" or exits 255 with no output usually needs nothing
  but a retry after re-reading `ndp -an`.
- **Transfer files with the ssh pipe, not `scp`.** The sftp subsystem has come
  and gone across rootfs rebuilds — when it is missing, scp fails with
  `scp: Connection closed`, which reads like a network fault. `ssh $PH
  'cat > dest' < src` works with or without sftp, and over the link-local v6
  target that scp's client-side parsing also chokes on. `ssh $PH 'sudo install
  -m755 /tmp/f /usr/local/bin/f'` for root-owned targets.
- **The phone's user is uid 1001, not 1000.** `hyprctl` against
  `/run/user/1000` returns empty lists rather than an error, so it looks like
  the compositor has zero keyboards and zero binds. That fabricated the original
  evidence for OPH-17 (`pm8941_pwrkey` *is* attached and `XF86PowerOff` *is*
  bound). Always `export XDG_RUNTIME_DIR=/run/user/1001` and take
  `HYPRLAND_INSTANCE_SIGNATURE` from `hyprctl instances`.
- **`pkill -f <pattern>` over ssh matches the ssh command line itself.** The
  remote shell carries the pattern in its own argv, so it kills the session:
  exit 255, no output, nothing cleaned up. Break the literal, e.g.
  `pkill -f '[o]marchy-menu-select'`.
- The OnePlus bootloader appends `root=/dev/dm-0 dm=...` after our cmdline.
  `PARTLABEL=userdata` and `/dev/sda17` both time out unless the initramfs
  hook `fajitaroot` forces the root device. maggu2810 hit this too.
- Booting from the flashed boot partition (not `fastboot boot`) hands the kernel
  a splash `simplefb` that steals fb0 and blanks the panel:
  `initcall_blacklist=simplefb_init`. Test on flashed boots, not `fastboot boot`.
- The Adreno 630 probes before the rootfs mounts: its firmware must be in the
  initramfs (`FILES=` in mkinitcpio.conf).
- The command-mode panel garbles fbcon unless `fbcon=rotate:1`.
- Key combos: fastboot = from off with cable OUT, Power+VolUp+VolDown, release
  Power at the vibrate, keep the volumes until "FastBoot Mode". Both volumes
  with the cable IN = EDL (9008). Exit EDL: unplug, VolUp+Power 20 s.
- Hard crashes land in EDL with no readable trace: ramoops IS wired up
  (4 MiB reserved at 0xac300000, CONFIG_PSTORE_RAM=y, pstore mounted) but every
  zone header fails at boot — `ramoops: uncorrectable error in header` — so
  `/sys/fs/pstore/` is always empty after a crash. Suspects: the EDL/crashdump
  programmers scribbling the reserved region, or a full power loss not
  preserving it. Three same-day EDL drops remain undiagnosable; capture needs
  fixing the header corruption (dump the raw region over ssh immediately after
  a *soft* reboot that follows a panic) or a serial console. Also cap
  `-j`/CPUQuota on long on-device builds — the load spikes before each drop.
- Once Linux runs, the boot partition can be rewritten over ssh with
  `dd if=boot.img of=/dev/disk/by-partlabel/boot_b`, so the button combination
  is only needed for the first flash.
- pacman 7's Landlock sandbox fails on this kernel: `DisableSandbox` in pacman.conf.
- No RTC: enable NTP (`timedatectl set-ntp true`) or set the date over ssh.
- Omarchy migration `1788124236` disables sshd at first session start if it
  thinks no key is authorized. It did, and locked the host out. `phone-setup.sh`
  now marks it done, a `post-boot` hook re-enables sshd, and an `ensuresshd`
  initramfs hook re-enables it before userspace even starts, so a lockout cannot
  survive a reboot.
- Omarchy's `omarchy-fcitx5.service` restart-loops without fcitx5 and steals
  Hyprland's single input-method slot from squeekboard: mask it.
- squeekboard only auto-shows on text focus with
  `gsettings set org.gnome.desktop.a11y.applications screen-keyboard-enabled true`,
  and it must bind while a text client already holds focus: an input method that
  connects to an empty session never receives activation again. `fajita-osk-start`
  opens a throwaway terminal to prime that, which is why the OSK is a systemd user
  service rather than a Hyprland `exec`.
- Never resolve the Hyprland session with `ls -t $XDG_RUNTIME_DIR/hypr/`. With no
  RTC the clock starts at 1970, so stale session directories sort newer than the
  live one and scripts silently drive a dead compositor. Use `hyprctl instances`.

## Suspend (not working)

`systemctl suspend` is masked. s2idle is the only state the kernel offers, and
entering it freezes userspace for good: the PMIC RTC alarm and the power key are
both registered wake sources and neither brings it back, while the kernel keeps
answering ping and accepting TCP on port 22. Only a 12 s power-button hold
recovers the phone, and `journalctl -b -1` ends at `PM: suspend entry (s2idle)`
because journald is frozen with everything else. Either the wake interrupt never
reaches the s2idle loop or resume hangs in a driver; the journal cannot tell
them apart. `scripts/suspend-probe.sh` sets the next attempt up so the kernel
log stays on the panel (fbcon, `console_suspend=N`, `pm_debug_messages`).
Until this is solved, Menu > Suspend is "Screen off" (DPMS) and the power key
wakes it: see `fajita-screen-off` and `fajita-power-key`.

## Configuration

Everything adjustable lives in `config.env` (user, password, USB subnet, locale,
timezone, image size). Every script sources it, so edit that one file or export
the variables in your shell. Defaults: user `dan`, phone at `172.16.42.1`.

## Access

- `ssh $PHONE_USER@$PHONE_IP` over the USB NCM gadget (sudo NOPASSWD; install your
  key on first login, the password only ever crosses the USB link).
- If that IP does not answer, the host never got a lease. Fall back to
  `ssh $PHONE_USER@fe80::...%en16` using the non-`permanent` address from
  `ndp -an` — no address assignment and no sudo on the host. See the notes
  above.
- Copy files with `ssh $PH 'cat > dest' < src`, not `scp`: the ssh pipe works
  whether or not the phone currently ships an sftp subsystem (see the trap above).
- Phone internet: on the host run `ssh -N -R 1080 $PHONE_USER@$PHONE_IP`; the phone's
  `/etc/profile.d/proxy.sh` points pacman/curl/git at `socks5h://127.0.0.1:1080`.
  The phone has no route of its own until you join Wi-Fi.
- On the phone: tap the top-left bar icon for the Omarchy menu, the keyboard icon
  at the top right toggles the on-screen keyboard.

## Phone adaptations beyond the build

`scripts/phone/apply-shell-patches.sh` patches Omarchy's own Quickshell interface
for touch. Re-run it after any `omarchy` package upgrade, since pacman replaces
those files:

- **Menu rows** get a `TapHandler`. Upstream handlers are pointer-only, and a
  finger tap on a layer surface never synthesizes a pointer event, so menus were
  unusable by touch.
- **Panel dismissal mask** subtracts the on-screen keyboard strip. The panel's
  full-screen click-catcher otherwise reads the first keypress as an outside
  click and closes the panel mid-typing.

Other phone-specific changes, applied by `phone-setup.sh`:

- Qt/GTK input-method variables point at `wayland`. Omarchy sets them to fcitx,
  which is masked here (its restart loop fights the on-screen keyboard), leaving
  Omarchy's own text fields with no keyboard at all.
- Suspend is masked. s2idle freezes userspace on this device with no wake path:
  the phone looks dead and ignores the power button.
- Arch's `man-db`, `plocate-updatedb` and `shadow` timers are masked. They
  saturate the SDM845 for minutes after boot and read as a hang.
- The screensaver's effects engine, `ttfx`, is published for x86_64 only. This
  is a gap in the published repo, not a missing port: upstream's
  `pkgbuilds/ttfx/PKGBUILD` already declares `arch=('x86_64' 'aarch64')` and
  `omacom/omarchy-pkgs` builds aarch64 (its `build/Dockerfile` is labelled
  `architectures="x86_64,aarch64"` and pulls from Arch Linux ARM mirrors), but
  `pkgs.omarchy.org/aarch64` holds one package, `omarchy-keyring` — an
  `arch=any` keyring, i.e. the first bootstrap step and nothing after it
  (their Dockerfile notes the ordering problem: an aarch64 build depends on an
  aarch64 repository only that build can populate). Verified 2026-09-13:
  x86_64 db 230 packages including `ttfx-0.3.2-1-x86_64.pkg.tar.zst`, aarch64
  db 1. So `scripts/build-ttfx.sh` compiles the Rust binary (v0.3.2,
  github.com/omacom-io/ttfx) in an arm64 Docker container on any host — native
  on Apple Silicon — against Debian bookworm's older glibc so it runs on the
  phone's Arch. The result is glibc-dynamic, not the static binary upstream's
  description advertises; musl was tried and abandoned (Alpine's packaged rust
  cannot build proc-macro crates like `clap_derive` for its own triple). The
  binary is committed at `scripts/phone/ttfx-aarch64` with its sha256 recorded
  in the build script, and installed to `/usr/local/bin/ttfx` (check-sync
  tracks it). Do not substitute the Python `tte`: even clamped to 20fps it
  saturates the SDM845, and `omarchy-screensaver`'s respawn loop multiplied it
  into hundreds of renderers that wedged the session (load average 229).
  Cleaner long-term shape, not yet done: build upstream's own PKGBUILD with
  `makepkg` in an Arch Linux ARM container, giving a real
  `ttfx-0.3.2-1-aarch64.pkg.tar.zst` that `pacman -Q` tracks and
  `fajita-omarchy-update` can upgrade — and that could be handed back upstream
  to seed their aarch64 repo.

### Screensaver on a phone

A working engine is not a working screensaver. `omarchy-screensaver` and
`omarchy-launch-screensaver` assume a desktop with a keyboard and a wide
terminal; five assumptions break on a phone. All five are patched idempotently
by `apply-shell-patches.sh` (sections 11-13), so a pacman upgrade cannot undo
them, and each section reports `already patched` on a second run.

- **The wait loop is scoped to the launching tty** (`pgrep -t "${tty#/dev/}"`).
  With no controlling tty the pgrep matches nothing, the inner loop exits at
  once and the outer `while true` respawns the renderer forever. The patch
  drops the tty filter and floors the loop with `sleep 1`, so a renderer that
  dies instantly degrades to one spawn per second instead of a fork bomb.
- **The exit check required the window to be *focused*** (`hyprctl
  activewindow`). When the on-screen keyboard or a non-interactive launch takes
  focus, the render force-exits immediately. Now it checks the window *exists*
  (`hyprctl clients | jq 'any(...)'`).
- **A tap is not a keypress.** The exit path waits on `read -n1`, and touch
  input produces no stdin bytes, so tapping the screen could never dismiss the
  render. Enabling mouse click reporting (`printf '\e[?1000h\e[?1006h'`) turns
  any tap into stdin bytes, which the existing `read` then consumes.
- **The banner clips.** `screensaver.txt` is 81 columns wide. Measured column
  counts for this 540px-logical portrait panel (foot, JetBrainsMono): 10pt → 42,
  9pt → 46, 8pt → 80, 7pt → 95. Only 7pt fits, and 8pt clips exactly the
  trailing `Y` — which is why several "smaller font" attempts looked almost
  right. Upstream's `wait_for_terminal_resize` also only blocks while `stty
  size` reads the literal `24 80` and gives up after 2s, so on this slow device
  ttfx could still measure an 80-column pty; the patch blocks until the pty
  actually widens past 80 columns.
- **The keyboard pops over the render.** foot activates text-input the instant
  its window maps, which is *before* the render script's first line runs, so
  per-show `SetVisible false` hides always lose the race (measured: ~0.5s of
  visible keyboard even with a 0.1s hide loop). The reliable lever is
  squeekboard's global gate, `org.gnome.desktop.a11y.applications
  screen-keyboard-enabled`: with it false the panel never maps even if
  something calls `SetVisible true`. The launcher sets it false before spawning
  foot; the exit path restores it and sweeps a hide for 1s (focus returning to
  the parked OSK primer would otherwise pop the panel on the way out).
  Entry and exit flashes both measured at 0 mapped-layer ticks afterwards.

Two safety notes on that gate. It is global, so a crash mid-render would leave
a phone with **no keyboard and no physical one to recover with**;
`squeekboard.service` therefore heals it on every start with
`ExecStartPre=-/usr/bin/gsettings set ... screen-keyboard-enabled true`. The
`-` prefix is load-bearing: without it a nonzero exit (dconf not ready that
early, schema missing) fails the unit, and `StartLimitBurst=3` then leaves
squeekboard dead — exactly the outcome the line exists to prevent.

Also patched: **re-selecting Screensaver while it runs is a toggle-close.**
Upstream's "already running" guard just exits, which on a phone leaves the
render up with no finger path out.

Traps worth knowing before touching any of this:

- `pgrep -f '[o]rg.omarchy.screensaver'` matches *your own* ssh command line if
  that string appears in it, so a test harness silently toggle-closes the thing
  it just launched. Build the string indirectly, or match on window class.
- `pkill -f <script-name>` has the same shape and will kill the ssh session
  running it. Kill spawned processes by recorded PID.
- Filter windows by **class**, never process name: the OSK primer runs as
  `foot --app-id fajita-osk-primer`, so `pkill foot` takes down the keyboard's
  IME primer while `class == "foot"` correctly excludes it.
- `systemctl --user restart squeekboard` respawns that primer as a *visible*
  window for ~4s before `fajita-osk-start` parks it on `special:osk` — which
  presents as "a terminal opens when I use the power menu". Hide the OSK over
  DBus; do not cycle the service.

### Cellular bring-up

Modem userspace is a stack of source builds, not pacman packages: `qrtr`,
`rmtfs`, `pd-mapper` and `tqftpserv` are not in the ALARM repos
(`build-qcom-services.sh` pins the validated qrtr/rmtfs commits), ModemManager
is rebuilt from a pinned git commit with a crash fix
(`build-modemmanager.sh` — see below), and `modem-uim-selection.service`
provisions the SIM's UIM session at every boot.

Three device-specific traps, all found the hard way on 2026-09-12:

- **ModemManager's netlink layer has a use-after-free** (`transaction_complete`
  removes the transaction from the hash table — running its value-destroy —
  before calling `tr->completion_fn`). Every muxed (qmapmux) data connection
  made MM segfault; it then crash-looped under NM autoconnect. Fixed in
  `scripts/mm-patches/`; still present upstream as of 1.25.95.
- **Android's RIL binds the WDS client to a subscription; ModemManager never
  does.** On this firmware the call manager refuses *every* PDN — internet and
  IMS alike — with `cm error: no-service` (QMI call-end reason 3,2001) unless
  the data client sends `WDS Bind Subscription` (primary) before Start
  Network. The SIM is fine (works in other phones, worked under Android here);
  registration and PS attach look healthy; the refusal is synchronous in the
  Start Network response. `mm-patches/0002` sends the bind in MM's connect
  path — RIL-parity the upstream tree still lacks.
- **Nothing provisions the SIM's UIM "primary GW" session at boot.** Android's
  RIL normally does it; without it ModemManager init fails with
  "couldn't check unlock status: GW primary session index unknown" and the
  modem lands in a failed `sim-missing` state even though the SIM is fine.
  `modem-uim-selection.service` replays pmOS's fix (activate the USIM AID on
  the occupied slot as primary-gw) before MM starts.

DMS also parks in `shutting-down` after cold boot; the pinned MM commit handles
that mode (upstream 31cbf9c1, found on this exact device by lynxis).

Two operational findings from getting the Data button working, both easy to
rediscover the hard way:

- **Only NetworkManager's `nmcli connection up three` yields a working link.**
  A raw `mmcli --simple-connect` brings the bearer up and reports an address,
  but nothing configures `qmapmux0.0`, and hand-configuring it (addr, onlink
  route) passes TX only — RX stays at zero. NM owns the netdev setup.
- **polkit denies NM control to seatless sessions.** Both ssh and the shell's
  process spawner get `Not authorized to control networking`, so anything the
  shell runs (the Data toggle, Reconnect) must go through `sudo -n nmcli`.

### Calls and SMS

Two standalone Quickshell apps under `~/.config/fajita`, launched from the
Apps menu (`calls.desktop` / `messages.desktop`) or by the watcher on an event:

- `calls.qml` — Recents (number/direction/missed/duration from the watcher's
  call log) and dialer (keypad) when idle, live call screen (accept/hangup,
  duration) while ModemManager has a call. Talks to `fajita-call`. Closing the
  window (✕, Close app, compositor close) hangs up any live call first —
  nothing else owns hang-up once the app is gone. The live screen also shows
  an output picker (earpiece / speaker / wired headset) and an audio-over-time
  strip: one bar per second per direction, green when the voice FE is
  `RUNNING`. On this box every bar is accent (open but idle) — the FE never
  runs, the honest display of the media-session gap below.
  `fajita-call-route` switches the hostless FE's AFE mixers mid-call (no
  profile change): speaker is `QUAT_MI2S_RX` (TFA amp), headset is
  `SLIMBUS_1_RX` + `SLIMBUS_2_TX` capture, earpiece restores the verb default
  (`SLIMBUS_0_RX`).
- `messages.qml` — thread list, conversation, new message. Talks to
  `fajita-sms`; history is `~/.local/state/fajita/messages.jsonl` (one JSON
  object per line, the helper is the only writer).
  Threads are keyed by the E.164 number: `fajita-sms`' `canon()` rewrites
  dialled forms (`07700900123`, `0044 7700 900123`) to `+447700900123` on every
  write, and `messages.qml` mirrors the same function so a composer addressed
  in national form opens (and keeps) the canonical thread. Without it sent and
  received messages land in two threads, the open one holds only their side,
  and nothing is right-aligned — which reads as "it doesn't say who sent what".
  Alphanumeric senders (`Missed Call`, `3UK`) and short codes pass through
  verbatim. `fajita-sms normalize` rewrites an already-split store in place.
- Both are plain xdg-toplevel windows, not layer-shell overlays, so they tile
  like any other app (two open = 50/50) and text fields raise squeekboard.
  An in-app key grid would double up with the OSK; don't add one back.
- `fajita-call-watch.service` (user) flips the card profile `HiFi` <-> `Voice
  Call` while a call is audio-bearing, raises the right app, and notifies on
  incoming calls/SMS. `q6voiced.service` (system, upstream postmarketOS C,
  built by `build-q6voiced.sh`) opens the hostless `VoiceMMode1` PCM
  (`hw:0,6`) on MM call signals; the UCM "Voice Call" verb does the backend
  routing (earpiece + bottom mic).
- **The call-audio path is provable without waiting for a callee.** Create a
  call and `--start` it: while it is `dialing`, q6voiced opens *both*
  VoiceMMode1 substreams — `/proc/asound/card0/pcm6{p,c}/sub0/status` go from
  `closed` to `state: PREPARED` with `owner_pid` equal to q6voiced's MainPID —
  the card sits on `Voice Call`, and both return to `closed` after hangup. So
  the kernel q6voice FE and the UCM backend work.
- **Calls do connect on this device; do not read "dialing only" into the
  logs.** `journalctl -u ModemManager` for 2025-09-14 07:17 has two outgoing
  calls going `unknown -> dialing -> ringing-out -> active -> terminated`
  (call0 active 07:17:12–07:17:19, call1 active 07:17:48–07:17:54) and an
  inbound `ringing-in` at 07:20:13, on `3 UK` / `access tech: lte` with the
  81voltd IMS bearer connected since 01:34:54. What is still *unproven* is
  audio during a connected call: q6voiced logged nothing in that window (its
  journal file for the period is damaged — "Identifier removed"), and
  `pcm6{p,c}` were not sampled while a call was `active`. That live sample,
  taken during a call rather than during `dialing`, is the remaining gap.
- **`ipc call … show || spawn` is not a launcher: a Quickshell process outlives
  the compositor.** After an overnight shell restart the `messages.qml`
  instance (pid 358400) was still running and still owned the
  `fajita-messages` IPC socket, but had no window: `ipc call fajita-messages
  show` returned rc=0 while `hyprctl clients` held 0 quickshell windows. The
  reason it is a *silent* no-op is the QML itself — `show()` is
  `if (!root.open) root.toggle()` (`messages.qml:211`), and `root.open` was
  still true from before the restart. Success without a window means the `||`
  fallback never ran and tapping the row did nothing at all.
  `fajita-app calls|messages` is the single launch path for the `.desktop`
  entries and the watcher: it focuses an existing *mapped* window (matched on
  `hyprctl clients` title), otherwise reaps any
  instance matching `quickshell -p <that qml>` and respawns under `setsid`,
  waiting until the window really appears. It forwards ipc args too, so
  `fajita-app messages open +44…` still lands on that conversation.
- `51-fajita-modem.rules` lets seatless callers (ssh, user units) run MM
  voice/messaging ops; without it every control call returns `Unauthorized`.
- **`PartOf=` propagates stop but never start**, which silently disabled call
  audio for an hour here. q6voiced was `PartOf=ModemManager.service`, so one
  `systemctl restart ModemManager` (mine, for a QMI probe — an MM crash does it
  too) stopped q6voiced and nothing ever brought it back; `Restart=on-failure`
  does not fire on a clean dependency stop. It is now
  `BindsTo=ModemManager.service` with `WantedBy=ModemManager.service`, so the
  lifecycle is symmetric in both directions — verified by restarting, stopping
  and starting MM and watching q6voiced follow each time.
- The watcher is **event-driven**; its poll is only a safety net. A 5s
  reconcile loop cost 2min 44s of CPU over 52min wall (~5% of a core, forever,
  on a phone) because each tick forked `fajita-call list` — one mmcli for the
  list plus one per call object — and an SMS sweep on top. It now reconciles on
  `Modem.Voice.CallAdded`/`CallDeleted`, per-call `StateChanged` and
  `Modem.Messaging.Added`, polls every 60s, sweeps SMS every 10 minutes, and
  takes one list snapshot per reconcile instead of two: 223ms of CPU over 120s
  (0.19% of a core), a 28x reduction. Latency is unaffected, so the poll really
  is only a net: the profile reaches "Voice Call" 205ms after `--start` and
  returns to `HiFi` 339ms after hangup.
- Two measurement traps bit me here, both worth avoiding: read the cost as
  `CPUUsageNSec` percent (`usec/10/seconds`) rather than hand arithmetic — I
  misreported 0.26% as 26% — and trim `pactl`'s `Active Profile:` value before
  comparing it, or a trailing space makes an already-correct profile look
  stuck and sends you chasing a release path that was never broken.
- `dbus-monitor` cannot use new-style monitoring here (`AccessDenied:
  "Sender is not authorized"`) and falls back to eavesdropping. That warning in
  the journal is expected; signals do arrive.

mmcli contract, verified against the pinned MM tree (`d776ea38`), because
guessing it wastes an afternoon:

- `--voice-create-call` only *creates* the object; dialing needs a second
  `mmcli -o PATH --start`. Per-call ops (`--start/--accept/--hangup`) are
  call-object actions, not modem options.
- `--messaging-create-sms` prints the path in its table form
  (`Messaging | created sms: /org/...`), and sending is an SMS-object action
  (`mmcli -s PATH --send`), not `-m ... --messaging-send-sms`.
- `-K` output pads keys (`call.properties.state        : active`), so any
  parser must trim before comparing. A key-equality match on the padded field
  silently yields empty state for every call.
- Terminated calls stay exported until deleted, and `--hangup` on a call that
  never connected fails with "This call was not active": `fajita-call hangup`
  falls back to `--voice-delete-call`, and `list` reaps only an explicit
  `terminated` (a freshly created call legitimately reports `--`).
- `-J` (and `-K`) nest SMS fields three levels deep: `.sms.content.number`,
  `.sms.content.text`, `.sms.properties.state`, `.sms.properties.timestamp` —
  *not* `.sms.number`/`.sms.state`. Parsing the short paths yields empty
  fields, the `received` test never passes, and every inbound message is
  dropped without a trace. `fajita-sms ingest` reads the long paths.
- A submit can take 25s and can fail, so `messages.qml` clears the composer
  only after `fajita-sms send` exits 0. Clearing on tap made a rejected send
  look like the text had simply vanished.

### VoLTE: 81voltd closes most of the gap

The first conclusion here was that no userspace change could help, because
Three UK (MCC 234 / MNC 20) is VoLTE-only — `qmicli --nas-get-serving-system`
reports `CS: 'detached'`, `PS: 'attached'`, and `--nas-get-system-info` says
LTE `Voice support: 'no'`, `IMS voice support: 'yes'`. LTE carries no
circuit-switched voice by design, so a phone must register either in the CS
domain (a VLR entry via 2G/3G or an SGs association) or with IMS. Neither held,
so the HSS had no route to this device: outgoing calls went
`dialing -> terminated` after ~25s, submits ended in `Timeout was reached`, and
incoming calls and texts never arrived at all. Forcing a CS-capable RAT is
refused by the plugin (`Unsupported: The given combination of allowed and
preferred modes is not supported`), so that escape is closed too.

That conclusion was wrong about the IMS half. postmarketOS ships
**`81voltd`** (`pmaports/temp/81voltd`, GPL-2.0, ~1400 lines of C): a
server-side implementation of the QMI IMS Data service. The modem firmware
*asks* the host to bring up an IMS PDN and has nobody to ask; 81voltd answers
that request, drives ModemManager to connect a bearer on the `ims` APN, and
hands the assigned address back over QMI. `scripts/build-81voltd.sh`
cross-builds it in the same debian:bookworm arm64 container as q6voiced; its
only deps are `mm-glib` and `libqrtr`, both already on the phone.

With it running, the IMS PDN comes up for real — `mmcli -b <path> -K` shows
`bearer.properties.apn : ims`, `ip-type : ipv6`, `status.connected : yes` on
`qmapmux0.1` — and **inbound SMS started working**. Three had queued every
message the phone could not receive; 81voltd started at 00:36:16 and the store
was written at 00:37:57 with all of them, original GSM timestamps intact
(21:57, 22:02, 23:25), plus the network's own missed-call notifications for
calls placed at 23:08 and 23:10. That is the whole receive path proven end to
end on real traffic: `Modem.Messaging.Added` -> `fajita-sms ingest` -> store ->
conversation UI.

**The bearer's netdev has to be configured by hand, and that is what makes
outbound SMS work.** ModemManager creates the IMS bearer and configures
nothing: the modem hands out a real IPv6 /64 (`bearer.ipv6-config.address`,
`prefix 64`, `mtu 1280`) while `qmapmux0.1` sits `DOWN` with no address.
Inbound SMS works anyway, because the modem's own IMS stack rides the PDN
context rather than host IP — which is exactly why this went unnoticed. Every
*outbound* submit, though, timed out at 25s with `message-reference` never
assigned and `QMI protocol error (56): 'WmsMessageDeliveryFailure'` in MM's
journal; that survived setting the SMSC explicitly and looked like a network
refusal. It was not. `ip link set qmapmux0.1 up` plus the bearer's own address
turns the same send from a 25s failure into `rc=0` in about a second, with the
object gone from the modem and the row in the store. So `fajita-ims-wait` does
that configuration as well as the verification, reading the address from the
bearer rather than hardcoding it (the prefix changes between PDN sessions —
verified by a recovery that came up on a different /64). NetworkManager never
touches this interface; data stays on `qmapmux0.0` via the `three` profile.

One thing is broken rather than misconfigured:

- **Calls connect but carry no audio; every host-side piece is now verified
  correct.** Sampled live during a clean 14 Sep 19:16 call (no host captures):
  profile `Voice Call`, both q6voice routing csets `on`
  (`SLIMBUS_0_RX…VoiceMMode1`, `VoiceMMode1 Capture…SLIMBUS_0_TX`),
  earpiece/mic muxes set, both `pcm6` substreams open — yet the FEs sat
  `PREPARED` for the whole call (never `RUNNING`) and the kernel logged zero
  q6voice/SLIM events. The modem completes SIP call control but never starts
  the ADSP media session. That is upstream's missing piece — the financed
  pmOS q6voice project (May 2026) targets exactly this codec-to-codec path.
  81voltd provides the IMS *data* bearer only, not media.
  The shipped `sdm845-mainline/alsa-ucm-conf` fajita profile *does* carry a
  full `Voice Call` verb (`ucm2/OnePlus/fajita/VoiceCall.conf`): it wires the
  q6voice FE both ways (`SLIMBUS_0_RX Voice Mixer VoiceMMode1`,
  `VoiceMMode1 Capture Mixer SLIMBUS_0_TX`) plus earpiece (RX0/AIF1_PB) and
  bottom-mic (TX7/DEC7/AMIC4) routing, and the watcher's profile flip is what
  applies it. So every component needed for call audio exists on the box;
  `fajita-call-audio-diag NUMBER` (dial, sample, dump `_verb`/csets/journal)
  is the one remaining test. Rate is not a suspect: q6voiced opens+prepares
  but never writes (hostless), so its 8 kHz pcm_config is decorative.

**81voltd needs verify-and-retry, not a precondition.** The modem asks for its
IMS PDN exactly once, when the service appears on QRTR, and 81voltd makes one
connect attempt per request with no retry. Started soon after ModemManager that
attempt returns `Failed to connect: ... cm error: no-service` and the unit then
sits `active` forever with no IMS bearer — the same silent-failure class as the
`PartOf=` bug, where the service is healthy and the thing it exists to provide
is absent. No precondition predicts it: gating the start on the modem being
exported, then on `registration-state: home`, then on `state: connected` all
still produced `no-service`, while restarting 81voltd alone minutes later
succeeds first time. So the unit verifies the outcome instead —
`ExecStartPost=/usr/local/bin/fajita-ims-wait` polls for an `apn: ims` bearer
reporting `connected: yes` and fails the unit otherwise, and `Restart=always`
comes back round. A hands-off `systemctl restart ModemManager` recovered in two
retries (`no connected ims bearer after 45s` twice, then `ims bearer
connected`, unit `active`). `StartLimitIntervalSec`/`StartLimitBurst` are
[Unit] keys and are set there, wide enough (30 in 600s) that the retry loop
does not trip the 5-in-10s default but a permanently IMS-less modem still stops.

One log line is harmless: 81voltd always logs the IPv4 variant as
`no-service`, because Three's IMS is IPv6-only. Only the v6 bearer matters.

Incoming calls, tested *before* 81voltd existed, failed one layer earlier than
the dialer: the network never paged the device. A call to `07700900456` from
another handset went straight to voicemail, with no call object, no
`Modem.Voice.CallAdded` signal and nothing in ModemManager's journal even at
`mmcli -G DEBUG` — only the QMI indication `type = "LTE Voice Support" (0x21)`.
With no CS registration and no IMS registration the HSS held no route, so the
network treated the phone as switched off and diverted to voicemail. Those
calls are the ones whose missed-call notifications later arrived as SMS, which
is itself proof the operator had queued traffic for a device it could not
reach. Re-testing incoming calls with the IMS bearer up is the obvious next
experiment and needs a second handset.

A SIM on an operator that still runs a circuit-switched radio remains the
fallback path *for calls*, since ModemManager's dial then works with no IMS at
all. It is no longer needed for inbound SMS: 81voltd made that work on this
VoLTE-only SIM. Which
operators still meet that is *not* measured here — the rest of this paragraph
is background as of 2026, from general knowledge rather than from this device,
and will age: in the UK, EE, Vodafone and O2 (and their MVNOs) kept 2G after
switching 3G off, while Three never ran 2G and shut 3G down in December 2024,
which is why this particular SIM was the worst case. Treat it as a hint about
which SIM to borrow, not as fact — the reliable test is to put one in and read
`--nas-get-serving-system` for `CS: 'attached'`.

Beware one iMessage trap when testing: an iPhone addressing this number may
send blue (iMessage over IP, never touching the modem). The bubble must be
green and labelled `Text Message • SMS` for the test to mean anything.

Two cheaper explanations were ruled out before settling on this, both worth
knowing because they produce the same 25s `Timeout was reached`:

- **Not a missing service centre.** An unsent submit reports
  `sms.properties.smsc : --` because MM only echoes an SMSC you set yourself.
  Creating the draft with Three's SMSC explicitly
  (`--messaging-create-sms='number="…",text="…",smsc="+447782000800"'`) still
  times out with `message-reference` never assigned.
- **Not the modem's SMS routing.** With MM stopped,
  `qmicli -d qrtr://0 --wms-get-routes` returns six routes, all
  `store-and-notify`, so an inbound message would be stored and signalled.
  `--ims-get-ims-services-enabled-setting` fails with QMI error 70
  (`InvalidOperation`): the modem exposes no IMS service to query, which is the
  other half of why VoLTE is unreachable. `qmicli -p` is useless here — there
  is no `qmi-proxy` binary in the rootfs, so drop the `-p` and take the device
  exclusively. Restart `ModemManager.service` afterwards or the phone has no
  data; `three` is `autoconnect=yes`, so NM reactivates it by itself once MM
  exports the modem again — no manual `nmcli connection up` needed.

## Upgrading Omarchy

`omarchy-update` cannot run here: it uses the `[omarchy]` pacman repo, which
publishes x86_64 packages that pacman refuses on aarch64. `fajita-omarchy-update`
does the same job for the packages that are portable. It reads the repo
database, fetches anything newer than what is installed, relabels packages that
contain no compiled code (`repack-noarch.sh` refuses any that do), installs
with `pacman -Udd`, fixes file ownership, re-applies the touch patches and
restarts the shell. `omarchy-update.timer` runs it on Sunday evenings;
`fajita-omarchy-update --check` lists what it would do.

`fajita-bar-order` (a user service) restarts the clock row whenever a shell
restart remaps Omarchy's bar underneath it, which otherwise puts the clock back
under the notch.

## Rebuild from scratch

1. Docker Desktop up. `docker run -d --name fajita-build --privileged --platform linux/arm64 -v $PWD/work:/work ubuntu:24.04 sleep infinity`, apt install e2fsprogs cpio arch-install-scripts android-sdk-libsparse-utils build-essential git zstd systemd-container, build osm0sis/mkbootimg with `CFLAGS="-O2 -w"`.
2. Download `ArchLinuxARM-aarch64-latest.tar.gz` and the pmOS v25.12 apks
   (`linux-postmarketos-qcom-sdm845`, `firmware-oneplus-sdm845`, `device-oneplus-fajita`) into `work/`, extract apks under `work/pmos/x/`.
3. `docker exec fajita-build bash /work/scripts/build-rootfs.sh`
4. Phone: OEM unlocking on, USB debugging on, USB 2.0 cable. `scripts/flash.sh unlock`, then `scripts/flash.sh flash`.
5. Fetch the arch=any Omarchy packages from `https://pkgs.omarchy.org/x86_64` into `work/opkgs/`, start the reverse tunnel, run `scripts/phone-setup.sh`.

## Status

Working: boots unattended into the Omarchy session, bar, menu (touch), on-screen
keyboard, terminal, theme, GPU acceleration, audio, Wi-Fi, USB networking, ssh,
screenshots (`scripts/shot.sh`), lock screen (swipe-up, cosmetic), and cellular
data: SIM provisioning, LTE registration, a working connection on the `three`
NM profile, and a bar widget with a panel, Data toggle and Reconnect. The Calls
and Messages apps are installed and tile 50/50 like any other window; verified
on device: dialing creates and starts a call object, hangup clears it in both
the live and never-connected cases, the store drives the conversation UI, and
flipping to the UCM "Voice Call" profile exposes the earpiece sink and call
mic. The call-audio path itself is verified as far as the network allows: on a
dial, q6voiced opens both VoiceMMode1 substreams (`PREPARED`, owned by its
MainPID) and closes them on hangup. **SMS works in both directions**, on real
traffic: `81voltd` brings up the IMS PDN and `fajita-ims-wait` configures its
netdev, after which the operator delivered every message it had queued
(`Modem.Messaging.Added` -> `fajita-sms ingest` -> store -> conversation UI,
numbers and GSM timestamps intact) and a send completes with `rc=0` in about a
second instead of timing out at 25s. That survives a hands-off `systemctl
restart ModemManager`: the unit retries until the bearer is up, reconfigures
the interface on whatever /64 the network grants, and sending works again with
no intervention.
Both apps appear in the Apps menu via `calls.desktop`/`messages.desktop`.

Partly working: calls. They reach `active` on the modem (twice on 14 Sep,
07:17:12-19 and 07:17:48-54, dialing -> ringing-out -> active) and an inbound
call reached `ringing-in` (07:20:13). What is *not* verified is audio on a
connected call: no live sample of `pcm6{p,c}` while `active` exists, and the
watcher now logs the FE state on every profile flip to close that gap on the
next call. 81voltd supplies the IMS data bearer, not SIP signalling or media.
See "VoLTE: 81voltd closes most of the gap". Bluetooth (firmware loads, HCI
reset times out). I haven't tried the camera or sensors.

Tested only on a OnePlus 6T (fajita) with Omarchy 4.0.2 and Hyprland 0.56.2.
The OnePlus 6 (enchilada) shares the SoC and should need only a DTB change.
