#!/bin/bash

set -euo pipefail

# Variables

DRIVE="/dev/nvme0n1"
ROOT="${DRIVE}p2"
BOOT="${DRIVE}p1"

NTP_SERVERS="0.asia.pool.ntp.org 1.asia.pool.ntp.org 2.asia.pool.ntp.org 3.asia.pool.ntp.org"
REFLECTOR_ARGS="--save /etc/pacman.d/mirrorlist -f 5 -c sg -p https"

KERNEL_PARAMETERS="root=${ROOT} rw quiet loglevel=3 systemd.show_status=auto rd.udev.log_level=3"
BASE_SYSTEM_PKGS="
    base base-devel bc bottom dkms dosfstools e2fsprogs exfatprogs fastfetch git gnupg intel-ucode
    linux linux-firmware linux-headers man-db man-pages mesa networkmanager neovim openssh
    pacman-contrib pipewire pipewire-alsa pipewire-audio pipewire-jack pipewire-pulse
    reflector sof-firmware sudo texinfo vulkan-intel wireplumber zsh zsh-completions
"
BASE_SYSTEM_PKGS=$(echo "$BASE_SYSTEM_PKGS")
INITRAMFS_HOOKS="systemd autodetect modconf kms block filesystems"
SWAP_FILE_SIZE="8G"

LOCALE="en_US.UTF-8 UTF-8"
TIME_ZONE="Asia/Manila"
LANGUAGE="en_US.UTF-8"
HOSTNAME="archlinux"

# Prompt for user credentials

read -rp "Enter username: " username
while true; do
    read -rsp "Enter password: " password && echo
    read -rsp "Confirm password: " password_confirm && echo
    [[ "$password" == "$password_confirm" ]] && break
    echo "Passwords do not match. Try again."
done

# Configure systemd-timesyncd

echo "Configuring systemd-timesyncd..." && sleep 1
sed -i "s/^#NTP=/NTP=${NTP_SERVERS}/" /etc/systemd/timesyncd.conf

# Restart systemd-timesyncd

echo "Restarting systemd-timesyncd..." && sleep 1
systemctl restart systemd-timesyncd.service

# Wait for system clock to synchronize

echo "Waiting for system clock to synchronize..." && sleep 1
sleep 5

# Partition disk

echo "Partitioning disk..." && sleep 1
echo -e "label: gpt\n,1G,U\n,,L" | sfdisk -w always -W always "$DRIVE"

# Format partitions

echo "Formatting partitions..." && sleep 1
mkfs.ext4 "$ROOT"
mkfs.fat -F32 "$BOOT"

# Mount partitions

echo "Mounting partitions..." && sleep 1
mount "$ROOT" /mnt
mount -m "$BOOT" /mnt/boot

# Update mirrorlist

echo "Updating mirrorlist..." && sleep 1
reflector $REFLECTOR_ARGS

# Install base system packages

echo "Installing base system packages..." && sleep 1
pacstrap -K /mnt $BASE_SYSTEM_PKGS

# Generate file systems table

echo "Generating file systems table..." && sleep 1
genfstab -U /mnt >> /mnt/etc/fstab

# Change root into the new system

echo "Changing root into the new system..." && sleep 1
arch-chroot /mnt /bin/bash <<OUTER_EOF

set -euo pipefail

# Create swap file

echo "Creating swap file..." && sleep 1
mkswap -U clear -s "$SWAP_FILE_SIZE" -F /swapfile
echo "/swapfile none swap defaults 0 0" >> /etc/fstab

# Set time zone

echo "Setting time zone and synchronizing hardware clock..." && sleep 1
ln -sf "/usr/share/zoneinfo/${TIME_ZONE}" /etc/localtime

# Set hardware clock

echo "Setting hardware clock..." && sleep 1
hwclock -w

# Enable systemd-timesyncd

echo "Enabling systemd-timesyncd..." && sleep 1
systemctl enable systemd-timesyncd.service

# Configure systemd-timesyncd

echo "Configuring systemd-timesyncd..." && sleep 1
mkdir /etc/systemd/timesyncd.conf.d
echo -e "[Time]\nNTP=${NTP_SERVERS}" > /etc/systemd/timesyncd.conf.d/ntp.conf

# Set locale

echo "Setting locale..." && sleep 1
sed -i "/^#${LOCALE}/s/^#//" /etc/locale.gen && locale-gen
echo "LANG=${LANGUAGE}" > /etc/locale.conf

# Set hostname

echo "Setting hostname..." && sleep 1
echo "$HOSTNAME" > /etc/hostname

# Set hosts

echo "Setting hosts..." && sleep 1
cat > /etc/hosts <<INNER_EOF
127.0.0.1   localhost
::1         localhost
127.0.1.1   ${HOSTNAME}.localdomain   ${HOSTNAME}
INNER_EOF

# Enable NetworkManager service

echo "Enabling NetworkManager service..." && sleep 1
systemctl enable NetworkManager.service

# Configure mkinitcpio

echo "Configuring mkinitcpio..." && sleep 1
echo "HOOKS=(${INITRAMFS_HOOKS})" > /etc/mkinitcpio.conf.d/hooks.conf

# Regenerate initramfs image

echo "Regenerating initramfs image..." && sleep 1
mkinitcpio -P

# Set password of root

echo "Setting password of root..." && sleep 1
echo "$password" | passwd -s root

# Create user

echo "Creating user..." && sleep 1
useradd -m -G wheel -s /usr/bin/zsh "$username"
echo "$password" | passwd -s "$username"

# Allow wheel group sudo access

echo "Allowing wheel group sudo access..." && sleep 1
echo "%wheel ALL=(ALL) ALL" > /etc/sudoers.d/wheel
chmod 0440 /etc/sudoers.d/wheel

# Install systemd-boot

echo "Installing systemd-boot..." && sleep 1
bootctl install

# Configure systemd-boot

echo "Configuring systemd-boot..." && sleep 1
cat > /boot/loader/loader.conf <<INNER_EOF
default        arch.conf
timeout        0
console-mode   max
editor         no
INNER_EOF

cat > /boot/loader/entries/arch.conf <<INNER_EOF
title     Arch Linux
linux     /vmlinuz-linux
initrd    /initramfs-linux.img
options   ${KERNEL_PARAMETERS}
INNER_EOF

cat > /boot/loader/entries/arch-fallback.conf <<INNER_EOF
title     Arch Linux (fallback)
linux     /vmlinuz-linux
initrd    /initramfs-linux-fallback.img
options   ${KERNEL_PARAMETERS}
INNER_EOF

# Configure reflector

echo "Configuring reflector..." && sleep 1
echo "$REFLECTOR_ARGS" > /etc/xdg/reflector/reflector.conf

# Enable reflector.timer

echo "Enabling reflector.timer..." && sleep 1
systemctl enable reflector.timer

# Enable paccache.timer

echo "Enabling paccache.timer..." && sleep 1
systemctl enable paccache.timer

# Install RTL8822CE driver

echo "Installing RTL8822CE driver..." && sleep 1
git clone https://github.com/juanro49/rtl88x2ce-dkms.git
cp rtl88x2ce-dkms/rtw88_blacklist.conf /etc/modprobe.d/rtw88_blacklist.conf
mv rtl88x2ce-dkms /usr/src/rtl88x2ce-35403
dkms add -m rtl88x2ce -v 35403
dkms build -m rtl88x2ce -v 35403
dkms install -m rtl88x2ce -v 35403

OUTER_EOF

# Unmount partitions

echo "Unmounting partitions..." && sleep 1
umount -R /mnt

# Prompt for reboot

read -p "Installation finished. Reboot now? (y/N): " input
if [[ "$input" =~ ^[Yy]$ ]]; then
    echo "Rebooting now..." && sleep 1
    reboot
fi