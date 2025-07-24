# Arch Linux Install Scripts

Bash scripts for automating the installation of a base Arch Linux system from the live environment.
The process roughly follows the procedures outlined in the [ArchWiki Installation Guide](https://wiki.archlinux.org/title/Installation_guide).
The purpose of these scripts is to automate the installation of a base Arch Linux system as a foundation for a desktop environment, window manager, or compositor.

> [!NOTE]
> **This script is not meant to substitute learning the manual installation process yourself.**
> I strongly encourage reading the ArchWiki Installation Guide and creating your own installation script.
> (If you choose to do so, feel free to fork this repository.)

## Prerequisites

- Boot the live environment.
- Connect to the internet.

## Usage

1. Download and extract the archive.
```bash
curl -L https://api.github.com/repos/CjayDoesCode/arch-install-scripts/tarball/main | tar -xz
```

2. Navigate into the project directory.
```bash
cd CjayDoesCode-arch-install-scripts-*
```

2. Make the installer script executable.
```bash
chmod +x install.sh
```

3. Run the installer.
```bash
./install.sh
```

## Installed Packages

| Package Group               | Packages                                                                                                                                                      |
| --------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| base_system_packages        | amd-ucode\|intel-ucode, base, bash, bash-completion, linux, linux-firmware, man-db, man-pages, networkmanager, nano, pacman-contrib, reflector, sudo, texinfo |
| filesystem_utility_packages | dosfstools, e2fsprogs, exfatprogs, ntfs-3g                                                                                                                    |
| amd_driver_packages         | mesa, vulkan-radeon, xorg-server                                                                                                                              |
| intel_driver_packages       | mesa, vulkan-intel, xorg-server                                                                                                                               |
| pipewire_packages           | pipewire, pipewire-alsa, pipewire-audio, pipewire-jack, pipewire-pulse, wireplumber                                                                           |
| optional_packages           | base-devel, git, openssh, sof-firmware                                                                                                                        |

Depending on the processor, either intel-ucode or amd-ucode is installed.<br/>
You can replace nano with the --editor option (e.g., `./install.sh --editor helix`).
