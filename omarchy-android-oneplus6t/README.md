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
  is therefore hidden with `"when": "false"` in the menu extension, which also
  blanks its action, so the trap cannot be reached from the phone; use
  `fajita-screen-off`, or `systemctl poweroff` over ssh when a real power-off
  is wanted and a host is at hand to recover it.
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
- The screensaver's effects engine, `ttfx`, is x86_64-only upstream. A shim maps
  it to `tte` from `python-terminaltexteffects` with the frame rate clamped, and
  the screensaver ships disabled: the Python engine at 120fps wedges the phone.

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
screenshots, modem bring-up (SIM provisioning, LTE registration — data
in progress at the time of writing; `scripts/shot.sh`).

Not working: Bluetooth (firmware loads, HCI reset times out), lock screen and
cellular data. I haven't tried the camera or sensors.

Tested only on a OnePlus 6T (fajita) with Omarchy 4.0.2 and Hyprland 0.56.2.
The OnePlus 6 (enchilada) shares the SoC and should need only a DTB change.
