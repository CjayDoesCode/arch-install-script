#!/bin/bash

set -euo pipefail
source constants.sh

# --- prompt for user credentials ---

read -rp 'Enter username for new user: ' username

while true; do
    read -rsp 'Enter password for new user and root: ' password && echo
    read -rsp 'Confirm password for new user and root: ' password_confirm && echo
    [ "$password" = "$password_confirm" ] && break
    echo 'Passwords do not match. Try again.'
done

# --- synchronize system clock ---

echo 'Synchronizing system clock...'
sed -i "s/#NTP=/NTP=${NTP_SERVERS[*]}/" /etc/systemd/timesyncd.conf
systemctl restart systemd-timesyncd.service && sleep 5

# --- partition disk, format partitions, mount file systems ---

# parition disk
echo 'Partitioning disk...'
echo -e 'size=1GiB, type=uefi\n type=linux' | \
sfdisk --wipe always --wipe-partitions always --label gpt "$DISK"

# format partitions
echo 'Format partitions...'
mkfs.ext4 "$ROOT_PARTITION"
mkfs.fat -F 32 "$BOOT_PARTITION"

# mount file systems
echo 'Mounting file systems...'
mount "$ROOT_PARTITION" /mnt
mount --mkdir "$BOOT_PARTITION" /mnt/boot

# --- update mirror list ---

echo 'Updating mirror list...'
reflector "${REFLECTOR_ARGS[@]}"

# --- install base system packages ---

echo 'Installing base system packages...'
pacstrap -K /mnt "${BASE_SYSTEM_PKGS[@]}"

# --- configure new system ---

# generate file systems table
echo 'Generating file systems table...'
genfstab -U /mnt >> /mnt/etc/fstab

# change root to new system
echo 'Changing root to new system...'
cp configure.sh constants.sh /mnt/root/
arch-chroot /mnt /bin/bash /root/configure.sh "$username" "$password"
rm /mnt/root/configure.sh /mnt/root/constants.sh

# --- unmount partitions ---

echo 'Unmounting partitions...'
umount --recursive /mnt

# --- prompt for reboot ---

read -rp 'Installation completed. Reboot now? (Y/n): ' input

if [ "$input" = 'n' ] || [ "$input" = 'N' ]; then
    exit 0
fi

echo 'Rebooting now...'
reboot