# omarchy-phone

Ports of Omarchy (Arch + Hyprland desktop shell) to Android phones, replacing
one A/B boot slot with mainline Linux. One device so far: OnePlus 6T (fajita),
Snapdragon 845, booting into Omarchy 4 on `linux-postmarketos-qcom-sdm845`.
The device folder README is the detailed journal; this file is the map.

## Layout

- `README.md`: top-level overview, why ARM was the slow part.
- `omarchy-android-oneplus6t/`: everything for fajita.
  - `README.md`: full device journal, read this before changing build or modem
    behaviour.
  - `config.env`: shared settings (phone user, USB subnet 172.16.42.1, proxy
    port). Sourced by every script; override via environment.
  - `patches/`: shell (QML/Lua) patches applied on the phone by
    `scripts/phone/apply-shell-patches.sh` (ships to `~/.local/bin`; run by
    `phone-setup.sh` and by `fajita-omarchy-update` after upgrades).
  - `scripts/`: host-side build and flash scripts.
  - `scripts/phone/`: files copied verbatim onto the phone: Quickshell apps
    (`calls.qml`, `messages.qml`), `fajita-*` helpers, systemd units, polkit
    rules, committed binaries (`ttfx-aarch64`, `gum`, `81voltd`, `q6voiced`).
  - `scripts/rootfs/`: units and configs baked into the image.

## The build

Host needs Docker (cross-builds happen in containers) and `fastboot`
(`scripts/flash.sh`: `unlock`, `boot-test`, `flash`). Android system partitions
stay; only a boot slot and userdata are written, so an unmarked slot falls back
to OxygenOS on reboot.

Omarchy publishes x86_64 only; `pkgs.omarchy.org/aarch64` holds one package
(`omarchy-keyring`). `repack-noarch.sh` relabels genuinely arch-independent
packages from the x86_64 repo (verified by unpacking; refuses real binaries).
Everything compiled is built here: Hyprland, a patched ModemManager, ttfx,
81voltd. Kernel is postmarketOS's prebuilt SDM845 package, not built here.

## Qualcomm userspace: what comes from where

Mainline Qualcomm hardware boots the modem/Wi-Fi remoteprocs but ships none of
the userspace Android ran to serve them. No single project has it all; the port
collects the set one piece at a time from several upstreams.
`build-qcom-services.sh` builds the linux-msm four plus the UCM tree in the
rootfs chroot:

| Piece | Upstream | Role here |
|---|---|---|
| `linux-postmarketos-qcom-sdm845` 6.16.7 | postmarketOS (prebuilt pkg) | Kernel with fajita DTB. |
| `qrtr` (pinned `ae88108`) | linux-msm | Qualcomm IPC router; 81voltd and the modem talk over it. Pins are the commits validated on the live image. |
| `pd-mapper`, `tqftpserv` | linux-msm | Protection-domain services. Without pd-mapper the modem never appears and the WCN3990 Wi-Fi does not either. |
| `rmtfs` (pinned `14cb1ee`) | linux-msm | Remote filesystem for the modem's EFS partitions; runs `-r -P -s` (pmOS-parity unit). |
| `q6voiced` | postmarketOS | Opens the hostless `VoiceMMode1` PCM (`hw:0,6`) on ModemManager call start/stop. Without it calls connect silent. |
| `81voltd` | flamingradian, packaged in `pmaports/temp/81voltd` | Server side of the QMI IMS Data service: answers the modem's one-time request for an IMS data connection by driving ModemManager onto an `ims` APN bearer. Author tested it working on Optus, not Telstra: carrier-dependent. |
| `alsa-ucm-conf` sdm845 tree (pinned `1b8d290`) | sdm845-mainline | UCM verbs `HiFi` / `Voice Call`. Upstream alsa-ucm-conf ships only DB845c/Lenovo for sdm845, so PipeWire sees a dummy sink without this tree. Pin matches the md5s `fajita-call-audio-diag` checks. |
| ModemManager + `qmicli` | freedesktop, built here | Local build exists for the two patches in `scripts/mm-patches`: netlink transaction-completion use-after-free, and bearer WDS Bind Subscription. |

## Telephony on a network with no CS fallback

Three UK (test SIM) never built 2G and switched 3G off (fully by Nov 2025;
UK 2G lingers on EE/Vodafone/O2 until at least 2029, all gone by 2033). LTE has
no circuit-switched domain, so with `CS: detached` and `IMS voice support: yes`
(`qmicli --nas-get-system-info`), SMS and calls must ride IMS. Status: SMS both
directions work; calls connect through `active`; connected-call audio wired but
unproven (no PCM sample mid-call yet; the watcher now logs every profile flip).

Moving parts: `81voltd.service` brings the IMS bearer up (verify-and-retry,
see gotchas), `fajita-ims-wait` configures its interface, `fajita-call-watch`
(user service) watches ModemManager: raises the calls/messages apps, notifies,
writes the call log that the calls app's Recents tab renders. `fajita-sms`
canonicalises numbers into `~/.local/state/fajita/messages.jsonl`.

## Keeping repo and phone identical

`check-sync.sh` diffs tracked files (59 at last count) against the live phone
over SSH and reports drift; it degrades to `(unreachable)` rather than failing.
`phone-setup.sh` is idempotent: edits are anchored with asserts (script aborts
if an anchor is missing), `.orig` backups are taken once. After changing
anything in `scripts/phone/`, deploy it and re-run check-sync in the same
commit window. The USB link drops often; if the phone is unreachable, say so
and queue the deploy rather than claiming it shipped.

## Gotchas

- **No RTC.** Boots read 1970 until NTP; anything picking newest-by-mtime
  chooses stale files.
- **Suspend never resumes.** Looks like a dead phone. Recovery: hold power
  20-25s, or attach a charger.
- **omarchy-update clobbers local files.** The UCM tree overwrites
  pacman-owned `/usr/share/alsa/ucm2`; patched Omarchy files drift. The
  `fajita-omarchy-update` wrapper and `check-sync.sh` exist to catch this.
- **`PartOf=` propagates stop, never start.** q6voiced was silent after any
  ModemManager restart until the unit bound both ways.
- **81voltd requests its IMS PDN exactly once.** A failed attempt leaves the
  daemon idle forever; the unit verifies outcome (`ExecStartPost` polls for a
  connected `apn: ims` bearer) and `Restart=always` retries. Gate on the
  outcome, not a precondition.
- **ModemManager creates the IMS bearer configured for nothing.** `qmapmux0.1`
  sits DOWN with no address; outbound SMS times out as if refused.
  `fajita-ims-wait` sets it up, reading address and prefix from the bearer
  (prefix changes between PDN sessions; never hardcode). Data stays on
  `qmapmux0.0`.
- **iMessage poisons SMS tests.** An iPhone routes to the number over
  iMessage and the modem never sees it; the bubble must be green.
- **Canon numbers on storage, not the wire.** Store E.164; send the dialled
  form (the network accepts it). Alphanumeric senders pass through untouched.
- **Quickshell outlives the compositor.** A windowless instance still answers
  IPC, so "ipc call show" succeeds with no window. `fajita-app` verifies a
  mapped window and respawns otherwise.
- **Desktop-sized UI on a 540px panel.** Notification cards anchor right and
  overflow; the clamp patch exists because of this. Expect the same for any
  Omarchy popup.
- **ttfx: build the Rust one.** `python-terminaltexteffects` at 120fps
  saturates SDM845 and wedges the session. `build-ttfx.sh` builds v0.3.2 for
  aarch64 (glibc, not musl; reasons in the script header); binary is committed
  at `scripts/phone/ttfx-aarch64` and installed to `/usr/local/bin/ttfx`.
- **SSH and user services have no seat.** polkit rules (`50-fajita-power`,
  `51-fajita-modem`) exist because of this; without them fajita helpers are
  denied when run from SSH.
- **Worktree copies.** Two other git worktrees of this repo exist on this
  machine with stale copies; the canonical checkout is this directory.

## Working in this repo

- Evidence first: probe the phone (`ssh $PHONE_SSH`, `mmcli`, `qmicli`,
  `journalctl`) before theorising. `fajita-call-audio-diag` dumps verb, cset
  and PCM state for audio questions.
- Never overwrite `main`. Do work on a branch, fast-forward `main` when the
  working session ends.
- Commits should name the subsystem (Calls, Toasts, README, Modem) like the
  existing log.
