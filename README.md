# Arch Linux Install Script

Bash script for automating the installation of a base Arch Linux system from the live environment.
The process roughly follows the procedures outlined in the [ArchWiki Installation Guide](https://wiki.archlinux.org/title/Installation_guide).
The purpose of this script is to automate the installation of a base Arch Linux system as a foundation for a desktop environment, window manager, or compositor.

> [!WARNING]
> This script supports only x86_64 (AMD64) systems with AMD or Intel CPUs.
> You will be prompted to select appropriate video drivers (AMD, Intel, or both) during installation.

> [!NOTE]
> **This script is not meant to substitute learning the manual installation process yourself.**
> I strongly encourage reading the ArchWiki Installation Guide and creating your own installation script.
> (If you choose to do so, feel free to fork this repository.)

## Prerequisites

- Boot the live environment
- Connect to the internet

## Usage

1. Download the script.
```bash
curl -o install.sh https://raw.githubusercontent.com/CjayDoesCode/arch-install-script/main/install.sh
```

2. Add executable permissions.
```bash
chmod +x install.sh
```

3. Run the script.
```bash
./install.sh
```

## Configuration

| Setting                        | Description                                                |
| :----------------------------- | :--------------------------------------------------------- |
| editor_pkg                     | Package for the console text editor. *(default: "helix")*  |
| silent_boot                    | Include silent boot kernel parameters. *(default: "true")* |
| create_user                    | Create a user. *(default: "true")*                         |
| create_swap_file               | Create a swap file. *(default: "true")*                    |
| install_userspace_util_pkgs    | Install userspace utilities. *(default: "true")*           |
| install_driver_pkgs            | Install video drivers. *(default: "true")*                 |
| install_pipewire_pkgs          | Install PipeWire. *(default: "true")*                      |

## Installed Packages

| Package Group         | Packages                                                                                                                                                                              |
| :-------------------- | :------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| base_system_pkgs      | `intel-ucode\|amd_ucode` `${editor_pkg}` `base` `bash` `bash-completion` `linux` `linux-firmware` `man-db` `man-pages` `networkmanager` `pacman-contrib` `reflector` `sudo` `texinfo` |
| userspace_util_pkgs   | `dosfstools` `e2fsprogs` `exfatprogs` `ntfs-3g`                                                                                                                                       |
| common_driver_pkgs    | `mesa` `xorg-server`                                                                                                                                                                  |
| intel_driver_pkgs     | `vulkan-intel`                                                                                                                                                                        |
| amd_driver_pkgs       | `vulkan-radeon`                                                                                                                                                                       |
| pipewire_pkgs         | `pipewire` `pipewire-alsa` `pipewire-audio` `pipewire-jack` `pipewire-pulse` `wireplumber`                                                                                            |
| optional_pkgs         | `base-devel` `git` `openssh` `sof-firmware`                                                                                                                                           |

Either `intel-ucode` or `amd-ucode` is installed, depending on the processor.

## Partition Layout (UEFI/GPT)

| Mount Point | Partition Type          | Size                    |
| :---------- | :---------------------- | :---------------------- |
| /boot       | EFI system partition    | 1 GiB                   |
| /           | Linux x86-64 root (/)   | Remainder of the device |
