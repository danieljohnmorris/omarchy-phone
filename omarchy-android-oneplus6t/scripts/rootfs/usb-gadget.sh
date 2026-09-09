#!/bin/bash
# Bring up a USB NCM+RNDIS ethernet gadget on fajita so the Mac sees the phone
# as a network interface. Phone = 172.16.42.1, host picks 172.16.42.2.
set -e
modprobe libcomposite 2>/dev/null || true
modprobe usb_f_ncm 2>/dev/null || true
modprobe usb_f_rndis 2>/dev/null || true

G=/sys/kernel/config/usb_gadget/fajita
mountpoint -q /sys/kernel/config || mount -t configfs none /sys/kernel/config
[ -d $G ] && exit 0
mkdir -p $G && cd $G
echo 0x1d6b > idVendor   # Linux Foundation
echo 0x0104 > idProduct  # Multifunction composite
echo 0x0100 > bcdDevice
echo 0x0200 > bcdUSB
mkdir -p strings/0x409
echo "fajita-$(cat /etc/machine-id | cut -c1-8)" > strings/0x409/serialnumber
echo "OnePlus" > strings/0x409/manufacturer
echo "OnePlus 6T (Arch Linux ARM)" > strings/0x409/product
mkdir -p configs/c.1/strings/0x409
echo "ncm" > configs/c.1/strings/0x409/configuration
echo 250 > configs/c.1/MaxPower
mkdir -p functions/ncm.usb0
ln -sf functions/ncm.usb0 configs/c.1/
# pick the UDC
UDC=$(ls /sys/class/udc | head -1)
[ -n "$UDC" ] && echo "$UDC" > UDC
