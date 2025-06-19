#!/bin/bash

set -euo pipefail

curl -O https://raw.githubusercontent.com/CjayDoesCode/arch-install-scripts/refs/heads/main/configure.sh
curl -O https://raw.githubusercontent.com/CjayDoesCode/arch-install-scripts/refs/heads/main/config.sh

source config.sh

# --- prompt for user credentials ---

while true; do
    read -rp "Enter username for new user: " USERNAME
    [[ $USERNAME =~ ^[a-zA-Z0-9_-]+$ ]] && break
    echo "Invalid username. Try again."
done

while true; do
    read -rsp "Enter password for new user and root: " PASSWORD && echo
    read -rsp "Confirm password for new user and root: " PASSWORD_CONFIRM && echo
    [[ $PASSWORD == $PASSWORD_CONFIRM ]] && break
    echo "Passwords do not match. Try again."
done

# --- prompt for target disk ---

echo "Available disks:"
lsblk --nodeps --noheadings --output NAME,SIZE,MODEL --paths | \
grep --extended-regex "/dev/sda|/dev/nvme0n1"

while true; do
    read -rp "Enter target disk (e.g., /dev/sda): " TARGET_DISK

    if [[ $TARGET_DISK == /dev/sda ]]; then
        ROOT_PARTITION=${TARGET_DISK}2
        BOOT_PARTITION=${TARGET_DISK}1
        break
    elif [[ $TARGET_DISK == /dev/nvme0n1 ]]; then
        ROOT_PARTITION=${TARGET_DISK}p2
        BOOT_PARTITION=${TARGET_DISK}p1
        break
    fi

    echo "Invalid disk. Please try again."
done

# --- prompt for swap file size ---

while true; do
    read -rp "Enter swap file size (e.g., 8GiB): " SWAP_FILE_SIZE

    if [[ $SWAP_FILE_SIZE =~ ^[0-9]+GiB$ ]]; then
        break
    fi

    echo "Invalid swap file size. Please try again."
done

# --- prompt for system packages ---

SYSTEM_PKGS=(
    ${BASE_SYSTEM_PKGS[@]}
    ${USERSPACE_UTIL_PKGS[@]}
    ${PIPEWIRE_PKGS[@]}
)

read -rp "Install Intel driver packages? (Y/n): " INPUT
[[ ! $INPUT =~ ^[nN]$ ]] && DRIVER_PKGS=(${COMMON_DRIVER_PKGS[@]} ${INTEL_DRIVER_PKGS[@]})

read -rp "Install AMD driver packages? (Y/n): " INPUT
[[ ! $INPUT =~ ^[nN]$ ]] && DRIVER_PKGS=(${COMMON_DRIVER_PKGS[@]} ${AMD_DRIVER_PKGS[@]})

SYSTEM_PKGS+=(${DRIVER_PKGS[@]})

INSTALL_HYPRLAND=0
read -rp "Install Hyprland? (Y/n): " INPUT
if [[ ! $INPUT =~ ^[nN]$ ]]; then
    INSTALL_HYPRLAND=1
    SYSTEM_PKGS+=(${HYPRLAND_PKGS[@]} ${HYPRLAND_FONT_PKGS[@]})
    OPTIONAL_PKGS+=(${HYPRLAND_OPTIONAL_PKGS[@]})
fi

for PKG in ${OPTIONAL_PKGS[@]}; do
    read -rp "Install $PKG? (Y/n): " INPUT
    [[ ! $INPUT =~ ^[nN]$ ]] && SYSTEM_PKGS+=($PKG)
done

# --- synchronize system clock ---

echo "Synchronizing system clock..."
sed -i "s/#NTP=/NTP=${NTP_SERVERS[*]}/" /etc/systemd/timesyncd.conf
systemctl restart systemd-timesyncd.service && sleep 5

# --- partition disk, format partitions, mount file systems ---

# partition disk
echo "Partitioning disk..."
echo -e "size=1GiB, type=uefi\n type=linux" | \
sfdisk --wipe always --wipe-partitions always --label gpt $TARGET_DISK

# format partitions
echo "Format partitions..."
mkfs.ext4 $ROOT_PARTITION
mkfs.fat -F 32 $BOOT_PARTITION

# mount file systems
echo "Mounting file systems..."
mount $ROOT_PARTITION /mnt
mount --mkdir $BOOT_PARTITION /mnt/boot

# --- update mirror list ---

echo "Updating mirror list..."
reflector ${REFLECTOR_ARGS[@]}

# --- install base system packages ---

echo "Installing base system packages..."
pacstrap -K /mnt ${SYSTEM_PKGS[@]}

# --- configure new system ---

# generate file systems table
echo "Generating file systems table..."
genfstab -U /mnt >> /mnt/etc/fstab

# change root to new system
echo "Changing root to new system..."

cat << CONFIG > /mnt/root/config.sh
TARGET_DISK=$TARGET_DISK
ROOT_PARTITION=$ROOT_PARTITION
BOOT_PARTITION=$BOOT_PARTITION
SWAP_FILE_SIZE=$SWAP_FILE_SIZE

TIME_ZONE=$TIME_ZONE
LOCALE="$LOCALE"
LANG=$LANG
HOSTNAME=$HOSTNAME

NTP_SERVERS=(${NTP_SERVERS[*]})
REFLECTOR_ARGS=(${REFLECTOR_ARGS[*]})
INITRAMFS_HOOKS=(${INITRAMFS_HOOKS[*]})
KERNEL_PARAMETERS=(root=$ROOT_PARTITION ${KERNEL_PARAMETERS[*]})

USERNAME=$USERNAME
PASSWORD="$PASSWORD"
INSTALL_HYPRLAND=$INSTALL_HYPRLAND
CONFIG

cp configure.sh /mnt/root/
arch-chroot /mnt /bin/bash /root/configure.sh
rm /mnt/root/configure.sh /mnt/root/config.sh

# --- unmount partitions ---

echo "Unmounting partitions..."
umount --recursive /mnt

# --- prompt for reboot ---

read -rp "Installation completed. Reboot now? (Y/n): " INPUT

if [[ ! $INPUT =~ ^[nN]$ ]]; then
    echo "Rebooting now..."
    reboot
fi
