#!/bin/bash
# Suspend diagnostic. Copy to the phone and run as root: sudo ./suspend-probe.sh 25
#
# What is known (2026-09-09/10): s2idle is the only sleep state. Entering it
# freezes userspace and nothing brings it back: not the PMIC RTC alarm, not the
# power key, both listed as wake sources. The kernel keeps answering ping and
# accepting TCP on :22, so it is alive and servicing USB interrupts, but sshd
# never sends a banner. Only a 12s power-button hold recovers it. The journal
# ends at "PM: suspend entry (s2idle)" because journald is frozen too.
# This kernel has no /sys/power/pm_test (CONFIG_PM_DEBUG off), so the freezer /
# devices / platform bisection is not available; pstore has no backend.
#
# This script makes the next attempt observable: fbcon owns the panel (chvt 2),
# console_suspend is off so printk keeps drawing through suspend and resume,
# and pm_debug_messages is on. Unplug USB right after it prints "armed" to take
# the USB gadget IRQ traffic out of the picture. Photograph the panel after it
# fails to wake; the last line is the diagnosis. suspend.target stays masked
# in normal use until this is fixed (Menu > Suspend is "Screen off" instead).
d=${1:-25}
zcat /proc/config.gz | grep -E "^CONFIG_(PM_SLEEP_DEBUG|PM_DEBUG|PSTORE_RAM|PSTORE_BLK|QCOM_PDC|QCOM_MPM|SUSPEND_SKIP_SYNC|RTC_DRV_PM8XXX|INPUT_PM8941_PWRKEY)=" | tr "\n" " "; echo
echo "console_suspend=$(cat /sys/module/printk/parameters/console_suspend) pm_debug=$(cat /sys/power/pm_debug_messages 2>&1) sync_on_suspend=$(cat /sys/power/sync_on_suspend 2>&1)"
# kernel messages straight to the panel, and keep printing through suspend/resume
echo N > /sys/module/printk/parameters/console_suspend
echo 1 > /sys/power/pm_debug_messages 2>/dev/null
echo 8 > /proc/sys/kernel/printk
echo 0 > /sys/class/rtc/rtc0/wakealarm; echo +40 > /sys/class/rtc/rtc0/wakealarm
# text console so fbcon owns the panel while userspace is frozen
chvt 2
nohup sh -c "sleep $d; echo mem > /sys/power/state; chvt 1" >/tmp/suspend.log 2>&1 &
echo "armed: suspend in ${d}s, rtc wake +40s, kernel log on panel (tty2)"
