#!/bin/bash
set -euo pipefail

# Variables
DRIVE="/dev/nvme0n1"
ROOT="${DRIVE}p2"
BOOT="${DRIVE}p1"

NTP_SERVERS="0.asia.pool.ntp.org 1.asia.pool.ntp.org 2.asia.pool.ntp.org 3.asia.pool.ntp.org"
REFLECTOR_ARGS="--save /etc/pacman.d/mirrorlist -f 5 -c sg -p https"

KERNEL_PARAMETERS="root=${ROOT} rw quiet loglevel=3 systemd.show_status=auto rd.udev.log_level=3"
BASE_SYSTEM_PKGS="base base-devel linux linux-headers linux-firmware sof-firmware intel-ucode dosfstools exfatprogs e2fsprogs networkmanager neovim man-db man-pages texinfo sudo git bash-completion"
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
echo "Configuring systemd-timesyncd..."
sed -i "s/^#NTP=/NTP=${NTP_SERVERS}/" /etc/systemd/timesyncd.conf

# Restart systemd-timesyncd
echo "Restarting systemd-timesyncd..."
systemctl restart systemd-timesyncd.service
sleep 5

# Partition the disk
echo "Partitioning the disk..."
echo -e "label: gpt\n,1G,U\n,,L" | sfdisk -w always -W always "$DRIVE"

# Format partitions
echo "Formatting partitions..."
mkfs.ext4 "$ROOT"
mkfs.fat -F32 "$BOOT"

# Mount partitions
echo "Mounting partitions..."
mount "$ROOT" /mnt
mount -m "$BOOT" /mnt/boot

# Update mirrorlist
echo "Updating mirrorlist..."
reflector $REFLECTOR_ARGS

# Install base system packages
echo "Installing base system packages..."
pacstrap -K /mnt $BASE_SYSTEM_PKGS

# Generate file systems table
echo "Generating file systems table..."
genfstab -U /mnt >> /mnt/etc/fstab

# Change root into the new system
echo "Changing root into the new system..."
arch-chroot /mnt /bin/bash <<EOF
set -euo pipefail

# Create a swap file
echo "Creating a swap file..."
mkswap -U clear -s "$SWAP_FILE_SIZE" -F /swapfile
echo "/swapfile none swap defaults 0 0" >> /etc/fstab

# Set time zone
echo "Setting time zone and synchronizing hardware clock..."
ln -sf "/usr/share/zoneinfo/${TIME_ZONE}" /etc/localtime

# Set the hardware clock
echo "Setting the hardware clock..."
hwclock -w

# Enable systemd-timesyncd
echo "Enabling systemd-timesyncd..."
systemctl enable systemd-timesyncd.service

# Configure systemd-timesyncd
echo "Configuring systemd-timesyncd..."
mkdir /etc/systemd/timesyncd.conf.d
echo -e "[Time]\nNTP=${NTP_SERVERS}" > /etc/systemd/timesyncd.conf.d/ntp.conf

# Set locale
echo "Setting locale..."
sed -i "/^#${LOCALE}/s/^#//" /etc/locale.gen && locale-gen
echo "LANG=${LANGUAGE}" > /etc/locale.conf

# Set hostname
echo "Setting hostname..."
echo "$HOSTNAME" > /etc/hostname

# Set hosts
echo "Setting hosts..."
cat > /etc/hosts <<HOSTS
127.0.0.1   localhost
::1         localhost
127.0.1.1   ${HOSTNAME}.localdomain   ${HOSTNAME}
HOSTS

# Enable NetworkManager service
echo "Enabling NetworkManager service..."
systemctl enable NetworkManager.service

# Configure mkinitcpio
echo "Configuring mkinitcpio..."
echo "HOOKS=(${INITRAMFS_HOOKS})" > /etc/mkinitcpio.conf.d/hooks.conf
mkinitcpio -P

# Set root password
echo "Setting root password..."
echo "$password" | passwd -s root

# Create a user
echo "Creating a user..."
useradd -m -G wheel "$username"
echo "$password" | passwd -s "$username"

# Allow wheel group sudo access
echo "Allowing wheel group sudo access..."
echo "%wheel ALL=(ALL) ALL" > /etc/sudoers.d/wheel
chmod 0440 /etc/sudoers.d/wheel

# Install and configure systemd-boot
echo "Installing and configuring systemd-boot..."
bootctl install

cat > /boot/loader/loader.conf <<LOADER
default        arch.conf
timeout        0
console-mode   max
editor         no
LOADER

cat > /boot/loader/entries/arch.conf <<ENTRY
title     Arch Linux
linux     /vmlinuz-linux
initrd    /initramfs-linux.img
options   ${KERNEL_PARAMETERS}
ENTRY

cat > /boot/loader/entries/arch-fallback.conf <<ENTRY
title     Arch Linux (fallback)
linux     /vmlinuz-linux
initrd    /initramfs-linux-fallback.img
options   ${KERNEL_PARAMETERS}
ENTRY
EOF

# Unmount partitions
echo "Unmounting partitions..."
umount -R /mnt

# Prompt for reboot
read -p "Installation finished. Reboot now? (y/N): " input
if [[ "$input" =~ ^[Yy]$ ]]; then
    echo "Rebooting now..."
    reboot
fi