#!/usr/bin/env bash
# ==============================================================================
#  AstraOS - Bootable Live Linux ISO Builder
#  Architecture: x86_64 (UEFI + Legacy BIOS Hybrid)
#  Base: Debian 12 (Bookworm) Minimal + Kiosk Compositor + Chromium Web Shell
# ==============================================================================

set -euo pipefail

echo "=========================================================="
echo "          AstraOS Live Bootable ISO Builder               "
echo "=========================================================="

if [ "$(id -u)" -ne 0 ]; then
  echo "[!] Error: This script must be run as root (sudo)."
  exit 1
fi

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WORK_DIR="/tmp/astraos_iso_build"
ROOTFS="${WORK_DIR}/rootfs"
LIVE_DIR="${WORK_DIR}/live_iso"
OUTPUT_DIR="${PROJECT_DIR}/output"
ISO_NAME="AstraOS-v1.0-x86_64.iso"

echo "[*] Project Directory: ${PROJECT_DIR}"
echo "[*] Working Directory: ${WORK_DIR}"
echo "[*] Output Directory:  ${OUTPUT_DIR}"

# Step 1: Install required host tools
echo ""
echo "[1/7] Installing builder tools..."
export DEBIAN_FRONTEND=noninteractive
apt-get update -y
apt-get install -y --no-install-recommends \
  debootstrap \
  squashfs-tools \
  xorriso \
  grub-pc-bin \
  grub-efi-amd64-bin \
  mtools \
  dosfstools \
  curl \
  ca-certificates \
  rsync

# Step 2: Cleanup and prepare directories
echo ""
echo "[2/7] Preparing workspace..."
rm -rf "${WORK_DIR}"
mkdir -p "${WORK_DIR}" "${ROOTFS}" "${LIVE_DIR}/live" "${LIVE_DIR}/boot/grub" "${OUTPUT_DIR}"

# Step 3: Bootstrap minimal Debian Bookworm
echo ""
echo "[3/7] Bootstrapping minimal Debian Bookworm (amd64)..."
debootstrap --arch=amd64 --variant=minbase bookworm "${ROOTFS}" http://deb.debian.org/debian/

# Bind mount essential filesystems
mount --bind /dev "${ROOTFS}/dev"
mount --bind /run "${ROOTFS}/run"
mount -t proc /proc "${ROOTFS}/proc"
mount -t sysfs /sys "${ROOTFS}/sys"

cleanup_mounts() {
  echo "[*] Cleaning up chroot mount points..."
  umount -lf "${ROOTFS}/dev" 2>/dev/null || true
  umount -lf "${ROOTFS}/run" 2>/dev/null || true
  umount -lf "${ROOTFS}/proc" 2>/dev/null || true
  umount -lf "${ROOTFS}/sys" 2>/dev/null || true
}
trap cleanup_mounts EXIT

# Step 4: Configure chroot environment
echo ""
echo "[4/7] Configuring chroot system, kernel, display & kiosk shell..."

cat << 'EOF' > "${ROOTFS}/root/setup_chroot.sh"
#!/bin/bash
set -euo pipefail

export DEBIAN_FRONTEND=noninteractive
export LC_ALL=C

# Hostname and network configuration
echo "astraos" > /etc/hostname
cat << 'EHOST' > /etc/hosts
127.0.0.1   localhost
127.0.1.1   astraos
::1         localhost ip6-localhost ip6-loopback
EHOST

# APT Mirrors
cat << 'EAPT' > /etc/apt/sources.list
deb http://deb.debian.org/debian bookworm main contrib non-free non-free-firmware
deb http://deb.debian.org/debian-security bookworm-security main contrib non-free non-free-firmware
deb http://deb.debian.org/debian bookworm-updates main contrib non-free non-free-firmware
EAPT

apt-get update -y

# Install Kernel, Live boot tools, Xorg, Audio, Chromium, Openbox & Utilities
apt-get install -y --no-install-recommends \
  linux-image-amd64 \
  live-boot \
  systemd-sysv \
  xorg \
  xinit \
  openbox \
  chromium \
  python3 \
  alsa-utils \
  pulseaudio \
  network-manager \
  dbus-x11 \
  sudo \
  unclutter \
  curl \
  ca-certificates \
  fonts-noto-color-emoji \
  fonts-dejavu-core

# Create default live user 'astra'
useradd -m -s /bin/bash -G sudo,audio,video,netdev astra
echo "astra:astra" | chpasswd
echo "root:astraos" | chpasswd
echo "astra ALL=(ALL) NOPASSWD: ALL" >> /etc/sudoers

# Enable automatic console login on tty1 for user 'astra'
mkdir -p /etc/systemd/system/getty@tty1.service.d
cat << 'EGETTY' > /etc/systemd/system/getty@tty1.service.d/autologin.conf
[Service]
ExecStart=
ExecStart=-/sbin/agetty --autologin astra --noclear %I $TERM
EGETTY

# Configure auto startx on login
cat << 'EPROF' >> /home/astra/.profile
if [ -z "$DISPLAY" ] && [ "$(tty)" = "/dev/tty1" ]; then
    exec startx -- -nocursor
fi
EPROF
chown astra:astra /home/astra/.profile

# Configure .xinitrc for AstraOS kiosk environment
cat << 'EXINIT' > /home/astra/.xinitrc
#!/bin/bash

# Disable screen blanking & DPMS power management
xset s off
xset -dpms
xset s noblank

# Start local AstraOS web server in background
cd /opt/astraos/web && python3 -m http.server 8080 --bind 127.0.0.1 >/dev/null 2>&1 &

# Brief pause for server readiness
sleep 1

# Hide mouse cursor when idle
unclutter -idle 3 &

# Launch Chromium in Fullscreen Kiosk Mode
exec chromium \
  --kiosk \
  --noerrdialogs \
  --disable-infobars \
  --disable-session-crashed-bubble \
  --check-for-update-interval=31536000 \
  --overscroll-history-navigation=0 \
  --disable-pinch \
  --autoplay-policy=no-user-gesture-required \
  --no-first-run \
  --disable-features=Translate \
  --disk-cache-dir=/tmp/chromium-cache \
  --user-data-dir=/tmp/chromium-profile \
  --app="http://127.0.0.1:8080"
EXINIT
chmod +x /home/astra/.xinitrc
chown astra:astra /home/astra/.xinitrc

# Clean up apt caches to minimize image size
apt-get clean
rm -rf /var/lib/apt/lists/*
EOF

chmod +x "${ROOTFS}/root/setup_chroot.sh"
chroot "${ROOTFS}" /bin/bash /root/setup_chroot.sh
rm -f "${ROOTFS}/root/setup_chroot.sh"

# Step 5: Copy AstraOS Web Application into RootFS
echo ""
echo "[5/7] Copying AstraOS build into RootFS (/opt/astraos/web)..."
mkdir -p "${ROOTFS}/opt/astraos/web"

if [ -d "${PROJECT_DIR}/build" ] && [ -f "${PROJECT_DIR}/build/index.html" ]; then
  cp -r "${PROJECT_DIR}/build/"* "${ROOTFS}/opt/astraos/web/"
else
  echo "[!] Warning: ${PROJECT_DIR}/build not found or incomplete. Attempting to build..."
  cd "${PROJECT_DIR}"
  if command -v npm >/dev/null 2>&1; then
    npm run build
    cp -r "${PROJECT_DIR}/build/"* "${ROOTFS}/opt/astraos/web/"
  else
    echo "[!] Error: No built files found and npm is not installed. Run 'npm run build' first."
    exit 1
  fi
fi

# Step 6: Extract Kernel & Initrd, and build SquashFS
echo ""
echo "[6/7] Extracting Kernel/Initrd and building SquashFS..."
cp "$(ls -1 "${ROOTFS}/boot"/vmlinuz-* | head -n1)" "${LIVE_DIR}/live/vmlinuz"
cp "$(ls -1 "${ROOTFS}/boot"/initrd.img-* | head -n1)" "${LIVE_DIR}/live/initrd.img"

mksquashfs "${ROOTFS}" "${LIVE_DIR}/live/filesystem.squashfs" \
  -comp xz \
  -wildcards

# Unmount chroot before making ISO
cleanup_mounts
trap - EXIT

# Step 7: Configure GRUB and generate Hybrid Bootable ISO
echo ""
echo "[7/7] Generating GRUB bootloader and Hybrid ISO..."

cat << 'EGRUB' > "${LIVE_DIR}/boot/grub/grub.cfg"
set default="0"
set timeout=5

insmod font
if loadfont /boot/grub/fonts/unicode.pf2 ; then
    insmod gfxterm
    set gfxmode=auto
    set gfxpayload=keep
    terminal_output gfxterm
fi

menuentry "AstraOS 1.0 (Live Desktop)" --class gnu-linux --class os {
    linux /live/vmlinuz boot=live quiet splash
    initrd /live/initrd.img
}

menuentry "AstraOS 1.0 (Safe Graphics / Nomodeset)" --class gnu-linux --class os {
    linux /live/vmlinuz boot=live nomodeset quiet
    initrd /live/initrd.img
}

menuentry "Reboot Computer" {
    reboot
}

menuentry "Shut Down Computer" {
    halt
}
EGRUB

grub-mkrescue -o "${OUTPUT_DIR}/${ISO_NAME}" "${LIVE_DIR}"

echo ""
echo "=========================================================="
echo "  SUCCESS! AstraOS Bootable Live ISO Created:             "
echo "  Path: ${OUTPUT_DIR}/${ISO_NAME}                        "
echo "  Size: $(du -h "${OUTPUT_DIR}/${ISO_NAME}" | cut -f1)   "
echo "=========================================================="
