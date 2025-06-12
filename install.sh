#!/bin/bash

set -euo pipefail
source config.sh

# --- prompt for user credentials ---

read -rp 'Enter username for new user: ' USERNAME
while true; do
    read -rsp 'Enter password for new user and root: ' PASSWORD && echo
    read -rsp 'Confirm password for new user and root: ' PASSWORD_CONFIRM && echo
    [[ "$PASSWORD" == "$PASSWORD_CONFIRM" ]] && break
    echo 'Passwords do not match. Try again.'
done

# --- prompt for system packages ---

SYSTEM_PKGS=(
    ${BASE_SYSTEM_PKGS[@]}
    ${USERSPACE_UTIL_PKGS[@]}
    ${PIPEWIRE_PKGS[@]}
    ${ZSH_PKGS[@]}
)

read -rp 'Install Intel driver packages? (Y/n): ' INPUT
[[ ! "$INPUT" =~ ^[nN]$ ]] && SYSTEM_PKGS+=(${INTEL_DRIVER_PKGS[@]})

read -rp 'Install AMD driver packages? (Y/n): ' INPUT
[[ ! "$INPUT" =~ ^[nN]$ ]] && SYSTEM_PKGS+=(${AMD_DRIVER_PKGS[@]})

for PKG in ${OPTIONAL_PKGS[@]}; do
    read -rp "Install $PKG? (Y/n): " INPUT
    [[ ! "$INPUT" =~ ^[nN]$ ]] && SYSTEM_PKGS+=($PKG)
done

# --- synchronize system clock ---

echo 'Synchronizing system clock...'
sed -i "s/#NTP=/NTP=${NTP_SERVERS[*]}/" /etc/systemd/timesyncd.conf
systemctl restart systemd-timesyncd.service && sleep 5

# --- partition disk, format partitions, mount file systems ---

# partition disk
echo 'Partitioning disk...'
echo -e 'size=1GiB, type=uefi\n type=linux' | \
sfdisk --wipe always --wipe-partitions always --label gpt $TARGET_DISK

# format partitions
echo 'Format partitions...'
mkfs.ext4 $ROOT_PARTITION
mkfs.fat -F 32 $BOOT_PARTITION

# mount file systems
echo 'Mounting file systems...'
mount $ROOT_PARTITION /mnt
mount --mkdir $BOOT_PARTITION /mnt/boot

# --- update mirror list ---

echo 'Updating mirror list...'
reflector ${REFLECTOR_ARGS[@]}

# --- install base system packages ---

echo 'Installing base system packages...'
pacstrap -K /mnt ${SYSTEM_PKGS[@]}

# --- configure new system ---

# generate file systems table
echo 'Generating file systems table...'
genfstab -U /mnt >> /mnt/etc/fstab

# change root to new system
echo 'Changing root to new system...'

cat > /mnt/root/config.sh <<CONFIG
TARGET_DISK=$TARGET_DISK
ROOT_PARTITION=$ROOT_PARTITION
BOOT_PARTITION=$BOOT_PARTITION
SWAP_FILE_SIZE=$SWAP_FILE_SIZE

TIME_ZONE=$TIME_ZONE
LOCALE='$LOCALE'
LANG=$LANG
HOSTNAME=$HOSTNAME

NTP_SERVERS=(${NTP_SERVERS[*]})
REFLECTOR_ARGS=(${REFLECTOR_ARGS[*]})
INITRAMFS_HOOKS=(${INITRAMFS_HOOKS[*]})
KERNEL_PARAMETERS=(${KERNEL_PARAMETERS[*]})

USERNAME=$USERNAME
PASSWORD='$PASSWORD'
CONFIG

cp configure.sh /mnt/root/
arch-chroot /mnt /bin/bash /root/configure.sh
rm /mnt/root/configure.sh /mnt/root/config.sh

# --- unmount partitions ---

echo 'Unmounting partitions...'
umount --recursive /mnt

# --- prompt for reboot ---

read -rp 'Installation completed. Reboot now? (Y/n): ' INPUT

if [[ ! "$INPUT" =~ ^[nN]$ ]]; then
    echo 'Rebooting now...'
    reboot
fi