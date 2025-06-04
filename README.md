# Arch Linux Install Scripts

Bash scripts to automate the installation of a minimal Arch Linux system from the live environment. The process follows the procedures outlined in the ArchWiki Installation Guide.

> [!WARNING]
> These scripts are written for my particular hardware and environment. If you intend to use them, review and modify the code to fit your own setup.

## Usage

1. Boot the live environment and connect to the internet.
2. Clone the repository:

```bash
git clone https://github.com/CjayDoesCode/arch-install-script.git
cd arch-install-scripts
```

3. Allow `install.sh` to be executed:

```bash
chmod +x install.sh
```

4. Run the `install.sh` script:

```bash
./install.sh
```