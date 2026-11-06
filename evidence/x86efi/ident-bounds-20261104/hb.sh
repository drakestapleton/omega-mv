#!/bin/sh
# hb.sh OMC SRC OUTDIR CPU [SMBIOS-ARG] : run.sh's boot() with a -cpu value and one -smbios value.
set -u
omc=$1 src=$2 d=$3 cpu=$4 smb=${5:-}
code=/usr/share/OVMF/OVMF_CODE_4M.fd vars=/usr/share/OVMF/OVMF_VARS_4M.fd
mkdir -p "$d"
"$omc" < "$src" > "$d/app.efi" 2> "$d/omc.err" || { echo "omc refused"; cat "$d/omc.err"; exit 1; }
cp "$vars" "$d/vars.fd"
dd if=/dev/zero of="$d/disk.img" bs=1048576 count=16 2> /dev/null
mformat -i "$d/disk.img" :: && mmd -i "$d/disk.img" ::/EFI ::/EFI/BOOT && mcopy -i "$d/disk.img" "$d/app.efi" ::/EFI/BOOT/BOOTX64.EFI
timeout 60 nice -n 19 taskset -c 9 qemu-system-x86_64 -machine q35,smbios-entry-point-type=64 -cpu "$cpu" -m 512 -display none ${smb:+-smbios "$smb"} \
  -drive if=pflash,format=raw,readonly=on,file="$code" -drive if=pflash,format=raw,file="$d/vars.fd" \
  -device qemu-xhci,id=xhci -drive if=none,id=stick,format=raw,file="$d/disk.img" \
  -device usb-storage,bus=xhci.0,drive=stick -net none -serial file:"$d/serial.log" -no-reboot > "$d/qemu.log" 2>&1
rm -f "$d/disk.img" "$d/vars.fd"
echo "app.efi $(sha256sum "$d/app.efi" | cut -d' ' -f1)"
tr -d '\r' < "$d/serial.log" | awk '/^==B$/ { on = 1 } on { print }' | sed 's/\x1b\[[0-9;]*[A-Za-z]//g'
tr -d '\r' < "$d/serial.log" | grep -a 'failed to start' | sed 's/\x1b\[[0-9;]*[A-Za-z]//g'
