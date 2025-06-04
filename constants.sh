#!/bin/bash

DISK='/dev/nvme0n1'
ROOT_PARTITION="${DISK}p2"
BOOT_PARTITION="${DISK}p1"
SWAP_FILE_SIZE='8GiB'

TIME_ZONE='Asia/Manila'
LOCALE='en_US.UTF-8 UTF-8'
LANG='en_US.UTF-8'
HOSTNAME='archlinux'

NTP_SERVERS=(
    '0.asia.pool.ntp.org'
    '1.asia.pool.ntp.org'
    '2.asia.pool.ntp.org'
    '3.asia.pool.ntp.org'
)

REFLECTOR_ARGS=(
    '--save' '/etc/pacman.d/mirrorlist'
    '--country' 'Singapore'
    '--fastest' '5'
    '--protocol' 'https'
    '--ipv4'
)

BASE_SYSTEM_PKGS=(
    'base'
    'base-devel'
    'bottom'
    'dosfstools'
    'e2fsprogs'
    'exfatprogs'
    'fastfetch'
    'git'
    'gnupg'
    'intel-ucode'
    'linux'
    'linux-firmware'
    'linux-headers'
    'man-db'
    'man-pages'
    'mesa'
    'neovim'
    'networkmanager'
    'ntfs-3g'
    'openssh'
    'pacman-contrib'
    'pipewire'
    'pipewire-alsa'
    'pipewire-audio'
    'pipewire-jack'
    'pipewire-pulse'
    'reflector'
    'sof-firmware'
    'sudo'
    'texinfo'
    'vulkan-intel'
    'wireplumber'
    'xorg-server'
    'zsh'
    'zsh-autosuggestions'
    'zsh-completions'
    'zsh-syntax-highlighting'
)

INITRAMFS_HOOKS=( 
    'systemd' # supersedes base, udev, fsck
    'autodetect'
    'microcode'
    'modconf'
    'kms'
    # 'keyboard'
    # 'keymap'
    # 'consolefont'
    'block'
    'filesystems'
)

KERNEL_PARAMETERS=(
    "root=${ROOT_PARTITION}"
    'rw'
    'quiet'
    'loglevel=3'
    'systemd.show_status=auto'
    'rd.udev.log_level=3'
)