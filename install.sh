#!/usr/bin/env bash

set -euo pipefail
IFS=$'\n\t'

source config.sh

# --- prompt for user name and password ---

read -rp "Enter user name: " USER_NAME
while true; do
    read -rsp "Enter user password: " USER_PASSWORD && echo
    read -rsp "Reenter user password: " REENTERED_PASSWORD && echo
    [[ "$USER_PASSWORD" == "$REENTERED_PASSWORD" ]] && break
    echo "Passwords do not match. Try again."
done

# --- prompt for root password ---

while true; do
    read -rsp "Enter root password: " ROOT_PASSWORD && echo
    read -rsp "Reenter root password: " REENTERED_PASSWORD && echo
    [[ "$ROOT_PASSWORD" == "$REENTERED_PASSWORD" ]] && break
    echo "Passwords do not match. Try again."
done

# --- prompt for target disk ---

echo "Disks:"
lsblk --nodeps --noheadings -o PATH,SIZE,MODEL | sed "s/^/- /"

while true; do
    read -rp "Enter target disk (e.g., /dev/sda): " TARGET_DISK
    if lsblk --nodeps -o PATH | grep -qx "$TARGET_DISK"; then
        case "$TARGET_DISK" in
            /dev/sd*)
                ROOT_PARTITION="${TARGET_DISK}2"
                BOOT_PARTITION="${TARGET_DISK}1"
                break
                ;;
            /dev/nvme*)
                ROOT_PARTITION="${TARGET_DISK}p2"
                BOOT_PARTITION="${TARGET_DISK}p1"
                break
                ;;
            /dev/mmcblk*)
                ROOT_PARTITION="${TARGET_DISK}p2"
                BOOT_PARTITION="${TARGET_DISK}p1"
                break
                ;;
        esac
    fi
    echo "Invalid disk. Try again."
done

KERNEL_PARAMETERS=(
    "$(lsblk --noheadings -o UUID $ROOT_PARTITION)"
    "${KERNEL_PARAMETERS[@]}"
)

# --- prompt for swap file size ---

while true; do
    read -rp "Enter swap file size (e.g., 4GiB): " SWAP_FILE_SIZE
    [[ "$SWAP_FILE_SIZE" =~ ^[0-9]+GiB$ ]] && break
    echo "Invalid swap file size. Try again."
done

# --- prompt for system packages ---

SYSTEM_PKGS=(
    "${BASE_SYSTEM_PKGS[@]}"
    "${USERSPACE_UTIL_PKGS[@]}"
    "${COMMON_DRIVER_PKGS}"
    "${PIPEWIRE_PKGS[@]}"
)

read -rp "Install Intel driver packages? [Y/n]: " INPUT
[[ ! "$INPUT" =~ ^[Nn]$ ]] && SYSTEM_PKGS+=("${INTEL_DRIVER_PKGS[@]}")

read -rp "Install AMD driver packages? [Y/n]: " INPUT
[[ ! "$INPUT" =~ ^[Nn]$ ]] && SYSTEM_PKGS+=("${AMD_DRIVER_PKGS[@]}")

for PKG in "${OPTIONAL_PKGS[@]}"; do
    read -rp "Install $PKG? [Y/n]: " INPUT
    [[ ! "$INPUT" =~ ^[Nn]$ ]] && SYSTEM_PKGS+=("$PKG")
done

# --- synchronize system clock ---

echo "Synchronizing system clock..."
sed -i "s/#NTP=/NTP=${NTP_SERVERS[@]}/" /etc/systemd/timesyncd.conf
systemctl restart systemd-timesyncd.service && sleep 5

# --- partition disk, format partitions, mount file systems ---

echo "Partitioning disk..."
echo -e "size=1GiB, type=uefi\n type=linux" | \
sfdisk --wipe always --wipe-partitions always --label gpt "$TARGET_DISK"

echo "Format partitions..."
mkfs.ext4 "$ROOT_PARTITION"
mkfs.fat -F 32 "$BOOT_PARTITION"

echo "Mounting file systems..."
mount "$ROOT_PARTITION" /mnt
mount --mkdir "$BOOT_PARTITION" /mnt/boot

# --- update mirror list ---

echo "Updating mirror list..."
reflector "${REFLECTOR_ARGS[@]}"

# --- install base system packages ---

echo "Installing base system packages..."
pacstrap -K /mnt "${SYSTEM_PKGS[@]}"

# --- configure new system ---

echo "Generating file systems table..."
genfstab -U /mnt >> /mnt/etc/fstab

echo "Changing root to new system..."

arch-chroot /mnt /bin/bash << CONFIGURE

# --- create swap file ---

echo "Creating swap file..."
mkswap --file /swapfile --uuid clear --size "$SWAP_FILE_SIZE"
echo "/swapfile none swap defaults 0 0" >> /etc/fstab

# --- set time zone ---

echo "Setting time zone..."
ln -sf "/usr/share/zoneinfo/$TIME_ZONE" /etc/localtime

# --- set hardware clock ---

echo "Setting hardware clock..."
hwclock --systohc

# --- set up time synchronization ---

echo "Setting up time synchronization..."
systemctl enable systemd-timesyncd.service
mkdir /etc/systemd/timesyncd.conf.d
echo -e "[Time]\nNTP=${NTP_SERVERS[@]}" > /etc/systemd/timesyncd.conf.d/ntp.conf

# --- set locale ---

echo "Setting locale..."
sed -i "/#$LOCALE/s/#//" /etc/locale.gen && locale-gen
echo "LANG=$LANG" > /etc/locale.conf

# --- set hostname ---

echo "Setting hostname..."
echo "$HOSTNAME" > /etc/hostname

# --- set hosts ---

echo "Setting hosts..."
cat << HOSTS > /etc/hosts
127.0.0.1  localhost
::1        localhost
127.0.1.1  $HOSTNAME.localdomain  $HOSTNAME
HOSTS

# --- set up network manager ---

echo "Setting up Network Manager..."
systemctl enable NetworkManager.service

# --- configure mkinitcpio ---

echo "Configuring mkinitcpio..."
echo "HOOKS=(${INITRAMFS_HOOKS[@]})" > /etc/mkinitcpio.conf.d/hooks.conf

# --- regenerate initramfs image ---

echo "Regenerating initramfs image..."
mkinitcpio --allpresets

# --- create new user ---

echo "Creating user..."
useradd --groups wheel --create-home --shell /usr/bin/bash "$USER_NAME"

# --- set password of new user and root ---

echo "root:$ROOT_PASSWORD" | chpasswd
echo "$USER_NAME:$USER_PASSWORD" | chpasswd

# --- configure sudo ---

echo "Configuring sudo..."
echo "%wheel ALL=(ALL) ALL" > /etc/sudoers.d/wheel
chmod 0440 /etc/sudoers.d/wheel

# --- install systemd-boot ---

echo "Installing systemd-boot..."
bootctl install

cat << LOADER > /boot/loader/loader.conf
default       arch.conf
timeout       0
console-mode  max
editor        no
LOADER

cat << ENTRY > /boot/loader/entries/arch.conf
title    Arch Linux
linux    /vmlinuz-linux
initrd   /initramfs-linux.img
options  ${KERNEL_PARAMETERS[@]}
ENTRY

cat << ENTRY > /boot/loader/entries/arch-fallback.conf
title    Arch Linux (fallback)
linux    /vmlinuz-linux
initrd   /initramfs-linux-fallback.img
options  ${KERNEL_PARAMETERS[@]}
ENTRY

# --- configure pacman ---

echo "Configuring pacman..."
sed -i "/#Color/s/#//" /etc/pacman.conf

# --- configure reflector ---

echo "Configuring reflector..."
echo "${REFLECTOR_ARGS[@]}" > /etc/xdg/reflector/reflector.conf
systemctl enable reflector.timer

# --- configure paccache ---

echo "Configuring paccache.timer..."
systemctl enable paccache.timer

CONFIGURE

# --- unmount partitions ---

echo "Unmounting partitions..."
umount --recursive /mnt

# --- prompt for reboot ---

read -rp "Installation completed. Reboot now? [Y/n]: " INPUT
[[ ! "$INPUT" =~ ^[nN]$ ]] && reboot
