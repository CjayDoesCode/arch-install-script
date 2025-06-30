#!/usr/bin/env bash

set -euo pipefail

# ------------------------------------------------------------------------------
#   configuration
# ------------------------------------------------------------------------------

editor_pkg="helix"                 # package for the console text editor
silent_boot="true"                 # include silent boot kernel parameters
create_user="true"                 # create a user
create_swap_file="true"            # create a swap file
install_userspace_util_pkgs="true" # install userspace utilities
install_driver_pkgs="true"         # install video drivers
install_pipewire_pkgs="true"       # install PipeWire

# ------------------------------------------------------------------------------
#   variables
# ------------------------------------------------------------------------------

target_disk=""
root_partition=""
boot_partition=""
root_partition_uuid=""
swap_file_size=""
country=""
system_pkgs=()
time_zone=""
locale=""
lang=""
hostname=""
user_name=""
user_password=""
root_password=""
reboot=""

ntp_servers=(
  "0.pool.ntp.org"
  "1.pool.ntp.org"
  "2.pool.ntp.org"
  "3.pool.ntp.org"
)

reflector_args=(
  "--save" "/etc/pacman.d/mirrorlist"
  "--sort" "score"
  # "--country" "${country}"
)

base_system_pkgs=(
  # "intel_ucode|amd_ucode"
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

# insert either amd-ucode or intel-ucode
# into base_system_pkgs based on the processor
case "$(lscpu | grep "Vendor ID" | awk '{print $3}')" in
AuthenticAMD)
  printf "\nDetected AMD CPU.\n"
  base_system_pkgs+=("amd-ucode")
  ;;
GenuineIntel)
  printf "\nDetected Intel CPU.\n"
  base_system_pkgs+=("intel-ucode")
  ;;
*)
  printf "\nUnknown CPU vendor.\n\n"
  exit 1
  ;;
esac

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
mkinitcpio_hooks=(
  "systemd"
  "autodetect"
  "microcode"
  "modconf"
  "kms"
  "block"
  "filesystems"
)

# root parameter inserted after
# root partition is formatted
kernel_parameters=(
  # root=UUID=${root_partition_uuid}
  "rw"
)

silent_boot_kernel_parameters=(
  "quiet"
  "loglevel=3"
  "systemd.show_status=auto"
  "rd.udev.log_level=3"
)

if [[ "${silent_boot}" == "true" ]]; then
  kernel_parameters+=("${silent_boot_kernel_parameters[@]}")
fi

# ------------------------------------------------------------------------------
#   functions
# ------------------------------------------------------------------------------

list_disks() {
  lsblk --nodeps --noheadings --output PATH,SIZE,MODEL |
    grep --extended-regexp "^/dev/(sd|nvme|mmcblk)"
}

list_countries() {
  reflector --list-countries |
    awk '{$NF=""; $(NF-1)=""; print $0}' |
    sed "1,2d" |
    sed "s/[[:space:]]*$//"
}

# ------------------------------------------------------------------------------
#   user input
# ------------------------------------------------------------------------------

# target_disk, root_partition, & boot_partition
printf "\nDisks:\n"
list_disks | sed "s/^/- /"

while true; do
  read -rp $'\n'"Enter target disk (e.g., \"/dev/sda\"): " target_disk
  if list_disks | grep --quiet "^${target_disk}\b"; then
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
  else
    printf "\nInvalid disk. Try again.\n"
  fi
done

# swap_file_size
if [[ "${create_swap_file}" == "true" ]]; then
  while true; do
    read -rp $'\n'"Enter swap file size (e.g., \"8GiB\"): " swap_file_size
    [[ "${swap_file_size}" =~ ^[0-9]+GiB$ ]] && break
    printf "\nInvalid swap file size. Try again.\n"
  done
fi

# country
printf "\nEnter a country to use as filter for reflector.\n"
printf "Enter 'l' to list countries. Enter 'q' to exit.\n"

while true; do
  read -rp $'\n'"Enter a country (e.g., \"Japan\"): " country
  if [[ "${country}" == "l" ]]; then
    list_countries | less
  elif list_countries | grep --quiet "^${country}$"; then
    reflector_args+=("--country" "${country}")
    break
  else
    printf "\nInvalid country. Try again.\n"
  fi
done

# system_pkgs
system_pkgs=("${base_system_pkgs[@]}")
[[ "${install_userspace_util_pkgs}" == "true" ]] &&
  system_pkgs+=("${userspace_util_pkgs[@]}")
[[ "${install_pipewire_pkgs}" == "true" ]] &&
  system_pkgs+=("${pipewire_pkgs[@]}")

if [[ "${install_driver_pkgs}" == "true" ]]; then
  system_pkgs+=("${common_driver_pkgs[@]}")

  read -rp $'\n'"Install Intel driver packages? [Y/n]: " input
  [[ ! "${input}" =~ ^[nN]$ ]] && system_pkgs+=("${intel_driver_pkgs[@]}")

  read -rp $'\n'"Install AMD driver packages? [Y/n]: " input
  [[ ! "${input}" =~ ^[nN]$ ]] && system_pkgs+=("${amd_driver_pkgs[@]}")

  for pkg in "${optional_pkgs[@]}"; do
    read -rp $'\n'"Install ${pkg}? [Y/n]: " input
    [[ ! "${input}" =~ ^[nN]$ ]] && system_pkgs+=("${pkg}")
  done
fi

# time_zone
printf "\nEnter 'l' to list time zones. Enter 'q' to exit.\n"

while true; do
  read -rp $'\n'"Enter time zone (e.g., \"Asia/Tokyo\"): " time_zone
  if [[ "${time_zone}" == "l" ]]; then
    timedatectl list-timezones | less
  elif timedatectl list-timezones | grep --quiet "^${time_zone}$"; then
    break
  else
    printf "\nInvalid time zone. Try again.\n"
  fi
done

# locale & lang
printf "\nEnter 'l' to list locales. Enter 'q' to exit.\n"

while true; do
  read -rp $'\n'"Enter locale (e.g., \"en_US.UTF-8 UTF-8\"): " locale
  if [[ "${locale}" == "l" ]]; then
    less /usr/share/i18n/SUPPORTED
  elif grep --quiet "^${locale}$" /usr/share/i18n/SUPPORTED; then
    lang="$(printf "%s\n" "${locale}" | awk '{print $1}')"
    break
  else
    printf "\nInvalid locale. Try again.\n"
  fi
done

# hostname
while true; do
  read -rp $'\n'"Enter hostname (e.g., archlinux): " hostname
  [[ "${hostname}" =~ ^[a-zA-Z0-9]+$ ]] && break
  printf "\nInvalid hostname. Try again.\n"
done

# user_name & user_password
if [[ "${create_user}" == "true" ]]; then
  while true; do
    read -rp $'\n'"Enter user name: " user_name
    [[ "${user_name}" =~ ^[a-zA-Z0-9]+$ ]] && break
    printf "\nInvalid user name. Try again.\n"
  done
  while true; do
    read -rsp $'\n'"Enter user password: " user_password && printf "\n"
    read -rsp "Reenter user password: " reentered_password && printf "\n"
    [[ "${user_password}" == "${reentered_password}" ]] && break
    printf "\nPasswords do not match. Try again.\n"
  done
fi

# root_password
while true; do
  read -rsp $'\n'"Enter root password: " root_password && printf "\n"
  read -rsp "Reenter root password: " reentered_password && printf "\n"
  [[ "${root_password}" == "${reentered_password}" ]] && break
  printf "\nPasswords do not match. Try again.\n"
done

# reboot
read -rp $'\n'"Reboot after installation? [Y/n]: " reboot

# ------------------------------------------------------------------------------
#   pre-installation
# ------------------------------------------------------------------------------

# synchronize system clock
printf "\nSynchronizing system clock...\n"
sed -i "s/^#NTP=/NTP=${ntp_servers[*]}/" /etc/systemd/timesyncd.conf
systemctl restart systemd-timesyncd.service && sleep 5

# partition disk
printf "\nPartitioning disk...\n"
printf "size=1GiB, type=uefi\n type=linux\n" |
  sfdisk --wipe always --wipe-partitions always --label gpt "${target_disk}"

# format partitions
printf "\nFormatting partitions...\n"
mkfs.ext4 "${root_partition}"
mkfs.fat -F 32 "${boot_partition}"

# insert root parameter into kernel parameters
root_partition_uuid="$(lsblk --noheadings --output UUID "${root_partition}")"
kernel_parameters=(
  "root=UUID=${root_partition_uuid}"
  "${kernel_parameters[@]}"
)

# mount file systems
printf "\nMounting file systems...\n"
mount "${root_partition}" /mnt
mount --mkdir "${boot_partition}" /mnt/boot

# create swap file
if [[ "${create_swap_file}" == "true" ]]; then
  printf "\nCreating swap file...\n"
  mkswap --file /mnt/swapfile --uuid clear --size "${swap_file_size}"
  swapon /mnt/swapfile
fi

# ------------------------------------------------------------------------------
#   installation
# ------------------------------------------------------------------------------

# update mirror list
printf "\nUpdating mirror list...\n"
reflector "${reflector_args[@]}"

# install base system packages
printf "\nInstalling base system packages...\n"
pacstrap -K /mnt "${system_pkgs[@]}"

# generate file systems table
printf "\nGenerating file systems table...\n"
genfstab -U /mnt >>/mnt/etc/fstab

# change root to new system
printf "\nChanging root to new system...\n"
arch-chroot /mnt /bin/bash <<CONFIGURE
set -euo pipefail

# set time zone
printf "\nSetting time zone...\n"
ln --force --symbolic "/usr/share/zoneinfo/${time_zone}" /etc/localtime

# set hardware clock
printf "\nSetting hardware clock...\n"
hwclock --systohc

# set up time synchronization
printf "\nSetting up time synchronization...\n"
systemctl enable systemd-timesyncd.service
mkdir --parents /etc/systemd/timesyncd.conf.d
printf "[Time]\nNTP=%s\n" "${ntp_servers[*]}" > \
  /etc/systemd/timesyncd.conf.d/ntp.conf

# set locale
printf "\nSetting locale...\n"
sed -i "/^#${locale}/s/^#//" /etc/locale.gen && locale-gen
printf "LANG=%s\n" "${lang}" >/etc/locale.conf

# set hostname
printf "\nSetting hostname...\n"
printf "%s\n" "${hostname}" >/etc/hostname

# enable network manager
printf "\nEnabling Network Manager...\n"
systemctl enable NetworkManager.service

# configure mkinitcpio
printf "\nConfiguring mkinitcpio...\n"
printf "HOOKS=(%s)\n" "${mkinitcpio_hooks[*]}" > \
  /etc/mkinitcpio.conf.d/hooks.conf

# regenerate initramfs image
printf "\nRegenerating initramfs image...\n"
mkinitcpio --allpresets

# create new user
if [[ "${create_user}" == "true" ]]; then
  printf "\nCreating user...\n"
  useradd --groups wheel --create-home --shell /usr/bin/bash "${user_name}"
  printf "%s:%s\n" "${user_name}" "${user_password}" | chpasswd
fi

# set root password
printf "\nSetting root password...\n"
printf "root:%s\n" "${root_password}" | chpasswd

# configure sudo
printf "\nConfiguring sudo...\n"
printf "%%wheel ALL=(ALL) ALL\n" >/etc/sudoers.d/wheel
chmod 0440 /etc/sudoers.d/wheel

# install systemd-boot
printf "\nInstalling systemd-boot...\n"
bootctl install

# configure systemd-boot
printf "\nConfiguring systemd-boot...\n"

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

# configure pacman
printf "\nConfiguring pacman...\n"
sed -i --regexp-extended "/^#(Color|VerbosePkgLists)/s/^#//" /etc/pacman.conf

# set up reflector
printf "\nSetting up reflector...\n"
printf "%s\n" "${reflector_args[*]}" >/etc/xdg/reflector/reflector.conf
systemctl enable reflector.timer

# enable paccache timer
printf "\nEnabling paccache timer...\n"
systemctl enable paccache.timer
CONFIGURE

# ------------------------------------------------------------------------------
#   post-installation
# ------------------------------------------------------------------------------

printf "\nInstallation completed.\n\n"
[[ ! "${reboot}" =~ ^[nN]$ ]] && reboot
