#!/bin/bash
set -euo pipefail

# Prompt for user credentials
read -rp "Enter username: " USERNAME
while true; do
    read -rsp "Enter password: " PASSWORD && echo
    read -rsp "Confirm password: " PASSWORD_CONFIRM && echo
    [[ "$PASSWORD" == "$PASSWORD_CONFIRM" ]] && break
    echo "Passwords do not match. Try again."
done

# Configure systemd-timesyncd
sed -i "s/^#NTP=.*/NTP=0.asia.pool.ntp.org 1.asia.pool.ntp.org 2.asia.pool.ntp.org 3.asia.pool.ntp.org/" /etc/systemd/timesyncd.conf
systemctl restart systemd-timesyncd.service
sleep 5

# Partition the disk
echo -e "label: gpt\n,1G,U\n,,L" | sfdisk -w always -W always /dev/nvme0n1

# Format partitions
mkfs.fat -F32 /dev/nvme0n1p1
mkfs.ext4 /dev/nvme0n1p2

# Mount partitions
mount /dev/nvme0n1p2 /mnt
mount --mkdir /dev/nvme0n1p1 /mnt/boot

# Update mirrorlist
reflector --save /etc/pacman.d/mirrorlist -f 5 -c sg -p https

# Install essential packages
pacstrap -K /mnt base linux linux-firmware intel-ucode networkmanager neovim man-db man-pages texinfo sudo

# Generate fstab
genfstab -U /mnt >> /mnt/etc/fstab

# Chroot and configure system
arch-chroot /mnt /bin/bash <<EOF
set -euo pipefail

# Create swap file
mkswap -U clear -s 8G -F /swapfile
echo "/swapfile none swap defaults 0 0" >> /etc/fstab

# Set timezone and synchronize hardware clock
ln -sf /usr/share/zoneinfo/Asia/Manila /etc/localtime
hwclock --systohc

# Configure systemd-timesyncd
mkdir /etc/systemd/timesyncd.conf.d
echo -e "[Time]\nNTP=0.asia.pool.ntp.org 1.asia.pool.ntp.org 2.asia.pool.ntp.org 3.asia.pool.ntp.org" > /etc/systemd/timesyncd.conf.d/ntp.conf
systemctl enable systemd-timesyncd.service

# Set locale
sed -i "/^#en_US\\.UTF-8 UTF-8/s/^#//" /etc/locale.gen && locale-gen
echo "LANG=en_US.UTF-8" > /etc/locale.conf

# Set hostname
echo "archlinux" > /etc/hostname

# Enable NetworkManager service
systemctl enable NetworkManager.service

# Set root password
echo "$PASSWORD" | passwd -s root

# Create user
useradd -m -G wheel "$USERNAME"
echo "$PASSWORD" | passwd -s "$USERNAME"

# Allow wheel group sudo access
echo "%wheel ALL=(ALL) ALL" > /etc/sudoers.d/wheel
chmod 0440 /etc/sudoers.d/wheel

# Install and configure systemd-boot
bootctl install

cat > /boot/loader/loader.conf <<LOADER
default arch.conf
console-mode max
editor no
LOADER

cat > /boot/loader/entries/arch.conf <<ENTRY
title Arch Linux
linux /vmlinuz-linux
initrd /initramfs-linux.img
options root=/dev/nvme0n1p2 rw
ENTRY

cat > /boot/loader/entries/arch-fallback.conf <<ENTRY
title Arch Linux (fallback)
linux /vmlinuz-linux
initrd /initramfs-linux-fallback.img
options root=/dev/nvme0n1p2 rw
ENTRY
EOF

# Unmount /mnt
umount -R /mnt