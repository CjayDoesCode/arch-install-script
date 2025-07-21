# Arch Linux Install Script

Bash script for automating the installation of a base Arch Linux system from the live environment.
The process roughly follows the procedures outlined in the [ArchWiki Installation Guide](https://wiki.archlinux.org/title/Installation_guide).
The purpose of this script is to automate the installation of a base Arch Linux system as a foundation for a desktop environment, window manager, or compositor.

> [!WARNING]
> This script only supports x86_64 (AMD64) systems with AMD or Intel CPUs.
> You will be prompted to select appropriate video drivers (AMD, Intel, or both) during installation.

> [!NOTE]
> **This script is not meant to substitute learning the manual installation process yourself.**
> I strongly encourage reading the ArchWiki Installation Guide and creating your own installation script.
> (If you choose to do so, feel free to fork this repository.)

## Prerequisites

- Boot the live environment.
- Connect to the internet.

## Usage

1. Download the script.
```bash
curl -o install.sh https://raw.githubusercontent.com/CjayDoesCode/arch-install-script/main/install.sh
```

2. Grant execute permission.
```bash
chmod +x install.sh
```

3. Run the script.
```bash
./install.sh
```
