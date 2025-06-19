TIME_ZONE=Asia/Manila
LOCALE="en_US.UTF-8 UTF-8"
LANG=en_US.UTF-8
HOSTNAME=archlinux

NTP_SERVERS=(
    0.pool.ntp.org
    1.pool.ntp.org
    2.pool.ntp.org
    3.pool.ntp.org
)

REFLECTOR_ARGS=(
    --save /etc/pacman.d/mirrorlist
    --country Singapore
    --fastest 5
    --protocol https
    --ipv4
)

BASE_SYSTEM_PKGS=(
    base
    base-devel
    bash
    bash-completion
    git
    gnupg
    helix
    linux
    linux-firmware
    linux-headers
    man-db
    man-pages
    networkmanager
    openssh
    pacman-contrib
    reflector
    sudo
    texinfo
)

USERSPACE_UTIL_PKGS=(
    dosfstools
    e2fsprogs
    exfatprogs
    ntfs-3g
)

COMMON_DRIVER_PKGS=(
    mesa
    xorg-server
)

INTEL_DRIVER_PKGS=(
    intel-ucode
    vulkan-intel
)

AMD_DRIVER_PKGS=(
    amd-ucode
    vulkan-radeon
)

PIPEWIRE_PKGS=(
    pipewire
    pipewire-alsa
    pipewire-audio
    pipewire-jack
    pipewire-pulse
    wireplumber
)

HYPRLAND_PKGS=(
    adobe-source-code-pro-fonts
    alacritty
    capitaine-cursors
    chezmoi
    firefox
    fuzzel
    grim
    hyprland
    hyprpaper
    hyprpolkitagent
    inter-font
    qt5-wayland
    qt6-wayland
    slurp
    ttf-nerd-fonts-symbols
    ttf-nerd-fonts-symbols-mono
    ttf-sourcecodepro-nerd
    uwsm
    waybar
    wl-clipboard
    xdg-desktop-portal-gtk
    xdg-desktop-portal-hyprland
    xdg-user-dirs
)

OPTIONAL_PKGS=(
    bottom
    fastfetch
    keepassxc
    lact
    sof-firmware
)

# systemd supersedes base, udev, fsck
INITRAMFS_HOOKS=(
    systemd
    autodetect
    microcode
    modconf
    kms
    # keyboard
    # keymap
    # consolefont
    block
    filesystems
)

KERNEL_PARAMETERS=(
    # root=${ROOT_PARTITION}
    rw
    quiet
    loglevel=3
    systemd.show_status=auto
    rd.udev.log_level=3
)
