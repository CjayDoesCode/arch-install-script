#!/usr/bin/env bash

set -euo pipefail

# ----- configuration -----

editor_pkg="helix"
create_user="true"
create_swap_file="true"
install_userspace_util_pkgs="true"
install_driver_pkgs="true"
install_pipewire_pkgs="true"

# ----- variables -----

# variables recommended to change:
# - time_zone
# - locale
# - lang
# - hostname
# - reflector_args

time_zone="Asia/Manila"
locale="en_US.UTF-8 UTF-8"
lang="en_US.UTF-8"
hostname="archlinux"

ntp_servers=(
  "0.pool.ntp.org"
  "1.pool.ntp.org"
  "2.pool.ntp.org"
  "3.pool.ntp.org"
)

reflector_args=(
  "--save" "/etc/pacman.d/mirrorlist"
  "--country" "Singapore"
  "--fastest" "5"
  "--protocol" "https"
  "--ipv4"
)

# `pacman-contrib` provides `paccache.timer`
# `reflector` provides `reflector.timer`
# `paccache.timer` automatically cleans pacman package cache
# `reflect.timer` automatically updates pacman mirror list
base_system_pkgs=(
  # "intel_ucode" | "amd_ucode"
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

# inserts either "amd-ucode" or "intel-ucode"
# to base_system_pkgs based on the processor
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

userspace_util_pkgs=(
  "dosfstools" # vfat
  "e2fsprogs"  # ext3/4
  "exfatprogs" # exfat
  "ntfs-3g"    # ntfs
)

common_driver_pkgs=("mesa" "xorg-server")
intel_driver_pkgs=("vulkan-intel")
amd_driver_pkgs=("vulkan-radeon")

pipewire_pkgs=(
  "pipewire"
  "pipewire-alsa"
  "pipewire-audio"
  "pipewire-jack"
  "pipewire-pulse"
  "wireplumber"
)

optional_pkgs=(
  "base-devel"
  "git"
  "openssh"
  "sof-firmware"
)

# systemd supersedes base, udev, & fsck
initramfs_hooks=(
  "systemd"
  "autodetect"
  "microcode"
  "modconf"
  "kms"
  "block"
  "filesystems"
)

# root parameter inserted after formatting root partition
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

get_disks () {
  lsblk --nodeps --noheadings --output PATH,SIZE,MODEL |
    grep --extended-regexp "^/dev/(sd|nvme|mmcblk)"
}

printf "Disks:\n"
get_disks | sed "s/^/- /"

while true; do
  read -rp "Enter target disk (e.g., /dev/sda): " target_disk
  if get_disks | grep --quiet "^${target_disk}"; then
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

if [[ "${create_swap_file}" == "true" ]]; then
  while true; do
    read -rp "Enter swap file size (e.g., 4GiB): " swap_file_size
    [[ "${swap_file_size}" =~ ^[0-9]+GiB$ ]] && break
    printf "Invalid swap file size. Try again.\n"
  done
fi

# ----- prompt for system packages -----

system_pkgs=("${base_system_pkgs[@]}")
[[ "${install_userspace_util_pkgs}" == "true" ]] &&
  system_pkgs+=("${userspace_util_pkgs[@]}")
[[ "${install_pipewire_pkgs}" == "true" ]] &&
  system_pkgs+=("${pipewire_pkgs[@]}")

if [[ "${install_driver_pkgs}" == "true" ]]; then
  system_pkgs+=("${common_driver_pkgs[@]}")

  read -rp "Install Intel driver packages? [Y/n]: " input
  [[ ! "${input}" =~ ^[nN]$ ]] && system_pkgs+=("${intel_driver_pkgs[@]}")

  read -rp "Install AMD driver packages? [Y/n]: " input
  [[ ! "${input}" =~ ^[nN]$ ]] && system_pkgs+=("${amd_driver_pkgs[@]}")

  for pkg in "${optional_pkgs[@]}"; do
    read -rp "Install ${pkg}? [Y/n]: " input
    [[ ! "${input}" =~ ^[nN]$ ]] && system_pkgs+=("${pkg}")
  done
fi

# ----- synchronize system clock -----

printf "Synchronizing system clock...\n"
sed -i "s/^#NTP=/NTP=${ntp_servers[*]}/" /etc/systemd/timesyncd.conf
systemctl restart systemd-timesyncd.service && sleep 5

# ----- partition disk -----

# Layout (UEFI/GPT):
#   Mount point  Partition type         Size
#   /boot        EFI system partition   1 GiB
#   /            Linux x86-64 root (/)  Remainder of the device

printf "Partitioning disk...\n"
printf "size=1GiB, type=uefi\n type=linux\n" |
  sfdisk --wipe always --wipe-partitions always --label gpt "${target_disk}"

# ----- format partitions -----

printf "Format partitions...\n"
mkfs.ext4 "${root_partition}"
mkfs.fat -F 32 "${boot_partition}"

root_partition_uuid=$(lsblk --noheadings --output UUID "${root_partition}")
kernel_parameters=(
  "root=UUID=${root_partition_uuid}"
  "${kernel_parameters[@]}"
)

# ----- mount file systems -----

printf "Mounting file systems...\n"
mount "${root_partition}" /mnt
mount --mkdir "${boot_partition}" /mnt/boot

# ----- create swap file -----

if [[ "${create_swap_file}" == "true" ]]; then
  printf "Creating swap file...\n"
  mkswap --file /mnt/swapfile --uuid clear --size "${swap_file_size}"
  swapon /mnt/swapfile
fi

# ----- update mirror list -----

printf "Updating mirror list...\n"
reflector "${reflector_args[@]}"

# ----- install base system packages -----

printf "Installing base system packages...\n"
pacstrap -K /mnt "${system_pkgs[@]}"

# ----- configure new system -----

printf "Generating file systems table...\n"
genfstab -U /mnt >>/mnt/etc/fstab

printf "Changing root to new system...\n"
arch-chroot /mnt /bin/bash <<CONFIGURE
set -euo pipefail

# ----- set time zone -----

printf "Setting time zone...\n"
ln --force --symbolic "/usr/share/zoneinfo/${time_zone}" /etc/localtime

# ----- set hardware clock -----

printf "Setting hardware clock...\n"
hwclock --systohc

# ----- set up time synchronization -----

printf "Setting up time synchronization...\n"
systemctl enable systemd-timesyncd.service
mkdir --parents /etc/systemd/timesyncd.conf.d
printf "[Time]\nNTP=%s\n" "${ntp_servers[*]}" > \
  /etc/systemd/timesyncd.conf.d/ntp.conf

# ----- set locale -----

printf "Setting locale...\n"
sed -i "/^#${locale}/s/^#//" /etc/locale.gen && locale-gen
printf "LANG=%s\n" "${lang}" >/etc/locale.conf

# ----- set hostname -----

printf "Setting hostname...\n"
printf "%s\n" "${hostname}" >/etc/hostname

# ----- set up network manager -----

printf "Setting up Network Manager...\n"
systemctl enable NetworkManager.service

# ----- configure mkinitcpio -----

printf "Configuring mkinitcpio...\n"
printf "HOOKS=(%s)\n" "${initramfs_hooks[*]}" > \
  /etc/mkinitcpio.conf.d/hooks.conf

# ----- regenerate initramfs image -----

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
printf "%%wheel ALL=(ALL) ALL\n" >/etc/sudoers.d/wheel
chmod 0440 /etc/sudoers.d/wheel

# ----- install systemd-boot -----

printf "Installing systemd-boot...\n"
bootctl install

# ----- configure systemd-boot -----

printf "Configuring systemd-boot...\n"

cat <<LOADER >/boot/loader/loader.conf
default       arch.conf
timeout       0
console-mode  max
editor        no
LOADER

cat <<ENTRY >/boot/loader/entries/arch.conf
title    Arch Linux
linux    /vmlinuz-linux
initrd   /initramfs-linux.img
options  ${kernel_parameters[*]}
ENTRY

cat <<ENTRY >/boot/loader/entries/arch-fallback.conf
title    Arch Linux (fallback)
linux    /vmlinuz-linux
initrd   /initramfs-linux-fallback.img
options  ${kernel_parameters[*]}
ENTRY

# ----- configure pacman -----

printf "Configuring pacman...\n"
sed -i "/#Color/s/#//" /etc/pacman.conf

# ----- configure reflector -----

printf "Configuring reflector...\n"
printf "%s\n" "${reflector_args[*]}" >/etc/xdg/reflector/reflector.conf
systemctl enable reflector.timer

# ----- configure paccache -----

printf "Configuring paccache.timer...\n"
systemctl enable paccache.timer
CONFIGURE

# ----- unmount partitions -----

printf "Unmounting partitions...\n"
umount --recursive /mnt

# ----- prompt for reboot -----

read -rp "Installation completed. Reboot now? [Y/n]: " input
[[ ! "${input}" =~ ^[nN]$ ]] && reboot
