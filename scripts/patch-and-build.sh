#!/usr/bin/env bash
set -euo pipefail

KERNEL_URL="https://github.com/ahngoo8Gongi/android_kernel_samsung_xcover4s.git"

if [ ! -d kernel/fs ]; then
  echo "[*] Kernel source mangler. Cloner..."
  rm -rf kernel
  git clone --depth=1 "$KERNEL_URL" kernel
fi

cd kernel

export ARCH=arm64
export SUBARCH=arm64
export ANDROID_MAJOR_VERSION=11
export PLATFORM_VERSION=11
export CROSS_COMPILE=aarch64-linux-gnu-
export HOSTCFLAGS="-fcommon"
export KCFLAGS="-Wno-error -w"

echo "[*] Patch sdcardfs recursive Kconfig"
[ -f fs/sdcardfs/Kconfig ] && sed -i -E '/^[[:space:]]*source[[:space:]]+/d' fs/sdcardfs/Kconfig || true

echo "[*] Patch DTC yylloc"
grep -RIl -- 'YYLTYPE yylloc' scripts/dtc 2>/dev/null \
  | xargs -r sed -i 's/^YYLTYPE yylloc;/extern YYLTYPE yylloc;/'

echo "[*] Patch HID read_spinlock"
[ -f drivers/usb/gadget/function/f_hid.c ] && \
  sed -i 's/read_spinlock/spinlock/g' drivers/usb/gadget/function/f_hid.c || true

echo "[*] Dummy Samsung blobs"
mkdir -p init firmware ../out/init ../out/firmware
printf '\177ELF\002\001\001' > init/uh.elf
truncate -s 4096 init/uh.elf
cp init/uh.elf ../out/init/uh.elf || true

printf '\0' > firmware/exynos7885_acpm_fvp.fw
truncate -s 4096 firmware/exynos7885_acpm_fvp.fw
cp firmware/exynos7885_acpm_fvp.fw ../out/firmware/exynos7885_acpm_fvp.fw || true

echo "[*] Disable broken conn_gadget"
find drivers/usb/gadget -name Makefile -type f -print0 \
  | xargs -0 sed -i -e '/f_conn_gadget/d' -e '/conn_gadget/d'

rm -rf ../out
mkdir -p ../out ../out/init ../out/firmware
cp init/uh.elf ../out/init/uh.elf
cp firmware/exynos7885_acpm_fvp.fw ../out/firmware/exynos7885_acpm_fvp.fw

make O=../out exynos7885-xcover4s_defconfig

./scripts/config --file ../out/.config -d CC_STACKPROTECTOR_STRONG || true
./scripts/config --file ../out/.config -d CC_STACKPROTECTOR_REGULAR || true
./scripts/config --file ../out/.config -e CC_STACKPROTECTOR_NONE || true

for x in \
  CONFIGFS_FS USB_GADGET USB_CONFIGFS USB_CONFIGFS_F_HID USB_F_HID \
  HID HIDRAW UHID TUN PACKET USB_USBNET USB_NET_RNDIS_HOST \
  USB_NET_CDCETHER USB_NET_CDC_NCM
do
  ./scripts/config --file ../out/.config -e "$x" || true
done

make O=../out olddefconfig

make O=../out -j"$(nproc)" \
  HOSTCFLAGS="$HOSTCFLAGS" \
  KCFLAGS="$KCFLAGS"

mkdir -p ../dist
IMG="$(find ../out/arch -type f \( -name 'Image.gz-dtb' -o -name 'Image.gz' -o -name 'zImage' \) | head -n1)"

[ -n "$IMG" ] || {
  echo "[!] Fant ikke kernel image"
  exit 1
}

cp "$IMG" ../dist/Image.gz-dtb
echo "[+] Built: dist/Image.gz-dtb"
