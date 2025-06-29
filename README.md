# Arch Linux Install Script

Bash script for automating the installation of a base Arch Linux system from the live environment.
The process roughly follows the procedures outlined in the [ArchWiki Installation Guide](https://wiki.archlinux.org/title/Installation_guide).
The purpose of this script is to automate the installation of a base Arch Linux system as a foundation for a desktop environment, window manager, or compositor.

## Prerequisites

- Boot the live environment
- Connect to the internet

## Usage

1. Download the script.
```bash
curl -OL "https://raw.githubusercontent.com/CjayDoesCode/arch-install-script/main/install.sh"
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

| Variable Name                  | Description                                              |
| :----------------------------- | :------------------------------------------------------- |
| editor_pkg                     | Package for the console text editor. (default: "helix")  |
| silent_boot                    | Include silent boot kernel parameters. (default: "true") |
| create_user                    | Create a user. (default: "true")                         |
| create_swap_file               | Create a swap file. (default: "true")                    |
| install_userspace_util_pkgs    | Install userspace utilities. (default: "true")           |
| install_driver_pkgs            | Install video drivers. (default: "true")                 |
| install_pipewire_pkgs          | Install PipeWire. (default: "true")                      |

## Packages

| Array Name            | Packages                                                                                                                                                                  |
| :-------------------- | :------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| base_system_pkgs      | intel-ucode|amd_ucode, ${editor_pkg}, base, bash, bash-completion, linux, linux-firmware, man-db, man-pages, networkmanager, pacman-contrib, reflector, sudo, texinfo     |
| userspace_util_pkgs   | dosfstools, e2fsprogs, exfatprogs, ntfs-3g                                                                                                                                |
| common_driver_pkgs    | mesa, xorg-server                                                                                                                                                         |
| intel_driver_pkgs     | vulkan-intel                                                                                                                                                              |
| amd_driver_pkgs       | vulkan-radeon                                                                                                                                                             |
| pipewire_pkgs         | pipewire, pipewire-alsa, pipewire-audio, pipewire-jack, pipewire-pulse, wireplumber                                                                                       |
| optional_pkgs         | base-devel, git, openssh, sof-firmware                                                                                                                                    |

## Partition Layout (UEFI/GPT)

| Mount Point | Partition Type          | Size                    |
| :---------- | :---------------------- | :---------------------- |
| `/boot`     | EFI system partition    | 1 GiB                   |
| `/`         | Linux x86-64 root (/)   | Remainder of the device |

## Defaults

| NTP Server     |
| :------------- |
| 0.pool.ntp.org |
| 1.pool.ntp.org |
| 2.pool.ntp.org |
| 3.pool.ntp.org |

| Reflector Arguments             |
| :------------------------------ |
| --save /etc/pacman.d/mirrorlist |
| --sort score                    |
| --country ${country}            |

| Mkinitcpio Hooks |
| :--------------- |
| systemd          |
| autodetect       |
| microcode        |
| modconf          |
| kms              |
| block            |
| filesystems      |

| Kernel Parameters                |
| :------------------------------- |
| root=UUID=${root_partition_uuid} |
| rw                               |

| Silent Boot Kernel Parameters |
| :---------------------------- |
| quiet                         |
| loglevel=3                    |
| systemd.show_status=auto      |
| rd.udev.log_level=3           |
