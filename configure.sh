#!/bin/bash

set -euo pipefail
source /root/constants.sh

# --- variables ---

username=$1
password=$2

# --- create swap file ---

echo 'Creating swap file...'
mkswap --file /swapfile --uuid clear --size "$SWAP_FILE_SIZE" 
echo '/swapfile none swap defaults 0 0' >> /etc/fstab

# --- set time zone ---

echo 'Setting time zone...'
ln --symbolic --force "/usr/share/zoneinfo/${TIME_ZONE}" /etc/localtime

# --- set hardware clock ---

echo 'Setting hardware clock...'
hwclock --systohc

# --- set up time synchronization ---

echo 'Setting up time synchronization...'
systemctl enable systemd-timesyncd.service
mkdir /etc/systemd/timesyncd.conf.d
echo -e "[Time]\nNTP=${NTP_SERVERS[*]}" > /etc/systemd/timesyncd.conf.d/ntp.conf

# --- set locale ---

echo 'Setting locale...'
sed -i "/#${LOCALE}/s/#//" /etc/locale.gen && locale-gen
echo "LANG=${LANG}" > /etc/locale.conf

# --- set hostname ---

echo 'Setting hostname...'
echo "$HOSTNAME" > /etc/hostname

# --- set hosts ---

echo 'Setting hosts...'
cat > /etc/hosts <<HOSTS
127.0.0.1   localhost
::1         localhost
127.0.1.1   ${HOSTNAME}.localdomain   ${HOSTNAME}
HOSTS

# --- set up network manager ---

echo 'Setting up Network Manager...'
systemctl enable NetworkManager.service

# --- configure mkinitcpio ---

echo 'Configuring mkinitcpio...'
echo "HOOKS=(${INITRAMFS_HOOKS[*]})" > /etc/mkinitcpio.conf.d/hooks.conf

# --- regenerate initramfs image ---

echo 'Regenerating initramfs image...'
mkinitcpio --allpresets

# --- set password of root ---

echo 'Setting password of root...'
echo "$password" | passwd --stdin root

# --- create user ---

echo 'Creating user...'
useradd --groups wheel --create-home --shell /usr/bin/zsh "$username"
echo "$password" | passwd --stdin "$username"

# --- configure zsh ---

echo 'Configuring zsh...'
cat > "/home/${username}/.zshrc" <<DOTZSHRC
alias ls='ls --color=auto'
alias ll='ls -lah --color=auto'
alias grep='grep --color=auto'

autoload -Uz promptinit compinit
promptinit
compinit
prompt walters

bindkey -e

setopt histignorealldups sharehistory

HISTSIZE=1000
SAVEHIST=1000
HISTFILE=~/.zsh_history

source /usr/share/zsh/plugins/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh
source /usr/share/zsh/plugins/zsh-autosuggestions/zsh-autosuggestions.zsh
DOTZSHRC

chown "${username}:${username}" "/home/${username}/.zshrc"

# --- configure sudo ---

echo 'Configuring sudo...'
echo '%wheel ALL=(ALL) ALL' > /etc/sudoers.d/wheel
chmod 0440 /etc/sudoers.d/wheel

# --- install systemd-boot ---

echo 'Installing systemd-boot...'
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
options   ${KERNEL_PARAMETERS[*]}
ENTRY

cat > /boot/loader/entries/arch-fallback.conf <<ENTRY
title     Arch Linux (fallback)
linux     /vmlinuz-linux
initrd    /initramfs-linux-fallback.img
options   ${KERNEL_PARAMETERS[*]}
ENTRY

# --- configure pacman ---

echo 'Configuring pacman...'
sed -i '/#Color/s/#//' /etc/pacman.conf

# --- configure reflector ---

echo 'Configuring reflector...'
echo "${REFLECTOR_ARGS[*]}" > /etc/xdg/reflector/reflector.conf
systemctl enable reflector.timer

# --- configure paccache ---

echo 'Configuring paccache.timer...'
systemctl enable paccache.timer