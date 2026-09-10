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
- **Omarchy floats are 875x600.** On a 540-wide phone the update prompt's
  "press any key" sat off the right edge. `looknfeel.lua` re-sizes the
  `floating-window` tag and the About window to 518x640.
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
screenshots (`scripts/shot.sh`).

Not working: Bluetooth (firmware loads, HCI reset times out), lock screen and
cellular. I haven't tried the camera or sensors.

Tested only on a OnePlus 6T (fajita) with Omarchy 4.0.2 and Hyprland 0.56.2.
The OnePlus 6 (enchilada) shares the SoC and should need only a DTB change.
