# Arch Linux Install Scripts

Bash scripts to automate the installation of a base Arch Linux system from the live environment. The process follows the procedures outlined in the ArchWiki Installation Guide.

> [!WARNING]
> These scripts are written for my particular hardware and environment. If you intend to use them, review and modify the code to fit your own setup.

## Usage

1. Boot the live environment and connect to the internet.
2. Download and unzip the repository:

```bash
curl -L https://api.github.com/repos/CjayDoesCode/arch-install-scripts/tarball/main | tar -xz
```

3. Change directory to the repository:

```bash
cd */
```

3. Allow `install.sh` to be executed:

```bash
chmod +x install.sh
```

4. Run the `install.sh` script:

```bash
./install.sh
```