#!/usr/bin/env bash

set -euo pipefail

# ----- configuration -----

editor_pkg="helix"
create_user="true"
install_userspace_util_pkgs="true"
install_driver_pkgs="true"
install_pipewire_pkgs="true"

# ----- variables -----

# variables recommended to change:
#     - time_zone
#     - locale
#     - lang
#     - hostname
#     - reflector_args

# https://wiki.archlinux.org/title/Installation_guide#Configure_the_system
time_zone="Asia/Manila"
locale="en_US.UTF-8 UTF-8"
lang="en_US.UTF-8"
hostname="archlinux"

# https://wiki.archlinux.org/title/Systemd-timesyncd#Configuration
ntp_servers=(
    "0.pool.ntp.org"
    "1.pool.ntp.org"
    "2.pool.ntp.org"
    "3.pool.ntp.org"
)

# https://wiki.archlinux.org/title/Reflector#systemd_service
reflector_args=(
    "--save" "/etc/pacman.d/mirrorlist"
    "--country" "Singapore"
    "--fastest" "5"
    "--protocol" "https"
    "--ipv4"
)

# pacman-contrib provides paccache.timer
# reflector provides reflector.timer
# paccache.timer automatically cleans pacman package cache
# reflect.timer automatically updates pacman mirror list
# https://wiki.archlinux.org/title/Pacman#Cleaning_the_package_cache
# https://wiki.archlinux.org/title/Reflector#systemd_timer
base_system_pkgs=(
    "${editor_pkg}"
    "base"
    "bash"
    "bash-completion"
    "linux"
    "linux-firmware"
    "man-db"
    "man-pages"
    "networkmanager"
    "pacman-contrib"
    "reflector"
    "sudo"
    "texinfo"
)

# inserts either intel_ucode or amd_ucode
# to base_system_pkgs based on the processor
# https://wiki.archlinux.org/title/Microcode
vendor=$(lscpu | grep "Vendor ID" | awk '{print $3}')
if [[ "${vendor}" == "AuthenticAMD" ]]; then
    printf "Detected AMD CPU.\n"
    base_system_pkgs+=("amd-ucode")
elif [[ "${vendor}" == "GenuineIntel" ]]; then
    printf "Detected Intel CPU.\n"
    base_system_pkgs+=("intel-ucode")
else
    printf "Unknown CPU vendor: %s\n" "${vendor}"
    exit 1
fi

# https://wiki.archlinux.org/title/File_systems#Types_of_file_systems
userspace_util_pkgs=(
    "dosfstools" # vfat
    "e2fsprogs"  # ext3/4
    "exfatprogs" # exfat
    "ntfs-3g"    # ntfs
)

# https://wiki.archlinux.org/title/Xorg#Driver_installation
common_driver_pkgs=("mesa" "xorg-server")
intel_driver_pkgs=("vulkan-intel")
amd_driver_pkgs=("vulkan-radeon")

# https://wiki.archlinux.org/title/PipeWire
pipewire_pkgs=(
    "pipewire"
    "pipewire-alsa"
    "pipewire-audio"
    "pipewire-jack"
    "pipewire-pulse"
    "wireplumber"
)

# sof-firmware is usually required for laptops
# https://wiki.archlinux.org/title/Advanced_Linux_Sound_Architecture#Firmware
optional_pkgs=(
    "base-devel"
    "git"
    "openssh"
    "sof-firmware"
)

# systemd supersedes base, udev, & fsck
# https://wiki.archlinux.org/title/Mkinitcpio#Common_hooks
initramfs_hooks=(
    "systemd"
    "autodetect"
    "microcode"
    "modconf"
    "kms"
    "block"
    "filesystems"
)

# root parameter inserted later
# https://wiki.archlinux.org/title/Kernel_parameters#Parameter_list
# https://wiki.archlinux.org/title/Silent_boot#Kernel_parameters
kernel_parameters=(
    # root=UUID=${root_partition_uuid}
    "rw"
    "quiet"
    "loglevel=3"
    "systemd.show_status=auto"
    "rd.udev.log_level=3"
)

# ----- prompt for user name and password -----

if [[ "${create_user}" == "true" ]]; then
    read -rp "Enter user name: " user_name
    while true; do
        read -rsp "Enter user password: " user_password && printf "\n"
        read -rsp "Reenter user password: " reentered_password && printf "\n"
        [[ "${user_password}" == "${reentered_password}" ]] && break
        printf "Passwords do not match. Try again.\n"
    done
fi

# ----- prompt for root password -----

while true; do
    read -rsp "Enter root password: " root_password && printf "\n"
    read -rsp "Reenter root password: " reentered_password && printf "\n"
    [[ "${root_password}" == "${reentered_password}" ]] && break
    printf "Passwords do not match. Try again.\n"
done

# ----- prompt for target disk -----

printf "Disks:\n"
lsblk --nodeps --noheadings --output PATH,SIZE,MODEL \
    | grep -E "^/dev/(sd|nvme|mmcblk)" \
    | sed "s/^/- /"

while true; do
    read -rp "Enter target disk (e.g., /dev/sda): " target_disk
    if lsblk --nodeps --output PATH | grep -qx "${target_disk}"; then
        case "${target_disk}" in
            /dev/sd*)
                root_partition="${target_disk}2"
                boot_partition="${target_disk}1"
                break
                ;;
            /dev/nvme*)
                root_partition="${target_disk}p2"
                boot_partition="${target_disk}p1"
                break
                ;;
            /dev/mmcblk*)
                root_partition="${target_disk}p2"
                boot_partition="${target_disk}p1"
                break
                ;;
        esac
    fi
    printf "Invalid disk. Try again.\n"
done

# ----- prompt for swap file size -----

while true; do
    read -rp "Enter swap file size (e.g., 4GiB): " swap_file_size
    [[ "${swap_file_size}" =~ ^[0-9]+GiB$ ]] && break
    printf "Invalid swap file size. Try again.\n"
done

# ----- prompt for system packages -----

system_pkgs=("${base_system_pkgs[@]}")
[[ "${install_userspace_util_pkgs}" == "true" ]] \
    && system_pkgs+=("${userspace_util_pkgs[@]}")
[[ "${install_pipewire_pkgs}" == "true" ]] \
    && system_pkgs+=("${pipewire_pkgs[@]}")

if [[ "${install_driver_pkgs}" == "true" ]]; then
    system_pkgs+=("${common_driver_pkgs[@]}")
    
    read -rp "Install Intel driver packages? [Y/n]: " input
    [[ ! "${input}" =~ ^[Nn]$ ]] && system_pkgs+=("${intel_driver_pkgs[@]}")

    read -rp "Install AMD driver packages? [Y/n]: " input
    [[ ! "${input}" =~ ^[Nn]$ ]] && system_pkgs+=("${amd_driver_pkgs[@]}")

    for pkg in "${optional_pkgs[@]}"; do
        read -rp "Install ${pkg}? [Y/n]: " input
        [[ ! "${input}" =~ ^[Nn]$ ]] && system_pkgs+=("${pkg}")
    done
fi

# ----- synchronize system clock -----

printf "Synchronizing system clock...\n"
sed -i "s/#NTP=/NTP=${ntp_servers[*]}/" /etc/systemd/timesyncd.conf
systemctl restart systemd-timesyncd.service && sleep 5

# ----- partition disk -----

# Layout (UEFI/GPT):
#     Mount point  Partition type         Size
#     /boot        EFI system partition   1 GiB
#     /            Linux x86-64 root (/)  Remainder of the device

printf "Partitioning disk...\n"
printf "size=1GiB, type=uefi\n type=linux\n" | \
    sfdisk --wipe always --wipe-partitions always --label gpt "${target_disk}"

# ----- format partitions -----

printf "Format partitions...\n"
mkfs.ext4 "${root_partition}"
mkfs.fat -F 32 "${boot_partition}"

# ----- mount file systems -----

printf "Mounting file systems...\n"
mount "${root_partition}" /mnt
mount --mkdir "${boot_partition}" /mnt/boot

# ----- update mirror list -----

printf "Updating mirror list...\n"
reflector "${reflector_args[@]}"

# ----- install base system packages -----

printf "Installing base system packages...\n"
pacstrap -K /mnt "${system_pkgs[@]}"

# ----- configure new system -----

printf "Generating file systems table...\n"
genfstab -U /mnt >> /mnt/etc/fstab

printf "Changing root to new system...\n"
arch-chroot /mnt /bin/bash << CONFIGURE

set -euo pipefail

# ----- create swap file -----

printf "Creating swap file...\n"
mkswap --file /swapfile --uuid clear --size "${swap_file_size}"
printf "/swapfile none swap defaults 0 0\n" >> /etc/fstab

# ----- set time zone, set hardware clock, & set up time synchronization -----

printf "Setting time zone...\n"
ln --force --symbolic "/usr/share/zoneinfo/${time_zone}" /etc/localtime

printf "Setting hardware clock...\n"
hwclock --systohc

printf "Setting up time synchronization...\n"
systemctl enable systemd-timesyncd.service
mkdir /etc/systemd/timesyncd.conf.d
printf "[Time]\nNTP=%s\n" "${ntp_servers[*]}" > \
    /etc/systemd/timesyncd.conf.d/ntp.conf

# ----- set locale -----

printf "Setting locale...\n"
sed -i "/#${locale}/s/#//" /etc/locale.gen && locale-gen
printf "LANG=%s\n" "${lang}" > /etc/locale.conf

# ----- set hostname, set hosts, & set up network manager -----

printf "Setting hostname...\n"
printf "%s\n" "${hostname}" > /etc/hostname

printf "Setting hosts...\n"
cat << HOSTS > /etc/hosts
127.0.0.1  localhost
::1        localhost
127.0.1.1  ${hostname}.localdomain  ${hostname}
HOSTS

printf "Setting up Network Manager...\n"
systemctl enable NetworkManager.service

# ----- configure mkinitcpio & regenerate initramfs image -----

printf "Configuring mkinitcpio...\n"
printf "HOOKS=(%s)\n" "${initramfs_hooks[*]}" > \
    /etc/mkinitcpio.conf.d/hooks.conf

printf "Regenerating initramfs image...\n"
mkinitcpio --allpresets

# ----- create new user -----

if [[ "${create_user}" == "true" ]]; then
    printf "Creating user...\n"
    useradd --groups wheel --create-home --shell /usr/bin/bash "${user_name}"
    printf "%s:%s\n" "${user_name}" "${user_password}" | chpasswd
fi

# ----- set root password -----

printf "Setting root password...\n"
printf "root:%s\n" "${root_password}" | chpasswd

# ----- configure sudo -----

printf "Configuring sudo...\n"
printf "%%wheel ALL=(ALL) ALL\n" > /etc/sudoers.d/wheel
chmod 0440 /etc/sudoers.d/wheel

# ----- install systemd-boot -----

printf "Installing systemd-boot...\n"
bootctl install

cat << LOADER > /boot/loader/loader.conf
default       arch.conf
timeout       0
console-mode  max
editor        no
LOADER

kernel_parameters=(
    "root=UUID=$(lsblk --noheadings --output UUID "${root_partition}")"
    "${kernel_parameters[@]}"
)

cat << ENTRY > /boot/loader/entries/arch.conf
title    Arch Linux
linux    /vmlinuz-linux
initrd   /initramfs-linux.img
options  ${kernel_parameters[*]}
ENTRY

cat << ENTRY > /boot/loader/entries/arch-fallback.conf
title    Arch Linux (fallback)
linux    /vmlinuz-linux
initrd   /initramfs-linux-fallback.img
options  ${kernel_parameters[*]}
ENTRY

# ----- configure pacman, reflector, & paccache -----

printf "Configuring pacman...\n"
sed -i "/#Color/s/#//" /etc/pacman.conf

printf "Configuring reflector...\n"
printf "%s\n" "${reflector_args[*]}"  > /etc/xdg/reflector/reflector.conf
systemctl enable reflector.timer

printf "Configuring paccache.timer...\n"
systemctl enable paccache.timer

CONFIGURE

# ----- unmount partitions & prompt for reboot -----

printf "Unmounting partitions...\n"
umount --recursive /mnt

read -rp "Installation completed. Reboot now? [Y/n]: " input
[[ ! "${input}" =~ ^[nN]$ ]] && reboot
