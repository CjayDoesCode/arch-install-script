#!/usr/bin/env bash

# ------------------------------------------------------------------------------
#       constants
# ------------------------------------------------------------------------------

readonly BASE_SYSTEM_PACKAGES=(
  'base'
  'bash'
  'bash-completion'
  'linux'
  'linux-firmware'
  'man-db'
  'man-pages'
  'networkmanager'
  'pacman-contrib'
  'reflector'
  'sudo'
  'texinfo'
)

readonly FILESYSTEM_UTILITY_PACKAGES=(
  'dosfstools'
  'e2fsprogs'
  'exfatprogs'
  'ntfs-3g'
)

readonly COMMON_DRIVER_PACKAGES=('mesa' 'xorg-server')
readonly AMD_DRIVER_PACKAGES=('vulkan-radeon')
readonly INTEL_DRIVER_PACKAGES=('vulkan-intel')

readonly PIPEWIRE_PACKAGES=(
  'pipewire'
  'pipewire-alsa'
  'pipewire-audio'
  'pipewire-jack'
  'pipewire-pulse'
  'wireplumber'
)

readonly OPTIONAL_PACKAGES=(
  'base-devel'
  'git'
  'openssh'
  'sof-firmware'
)

declare -Ar COLOR_CODES=(
  [black]=30
  [red]=31
  [green]=32
  [yellow]=33
  [blue]=34
  [magenta]=35
  [cyan]=36
  [white]=37
)

# ------------------------------------------------------------------------------
#       main function
# ------------------------------------------------------------------------------

main() {
  printf '\n'

  # ----  configuration  -------------------------------------------------------

  local editor_package='nano'
  local swap='true'
  local install_filesystem_utility_packages='true'
  local install_driver_packages='true'
  local install_pipewire_packages='true'

  # ----  variables  -----------------------------------------------------------

  local target_disk=''
  local root_partition=''
  local boot_partition=''
  local swap_size=''

  local reflector_options=()
  local system_packages=()
  local driver_packages=()
  local optional_packages=()

  system_packages+=("${BASE_SYSTEM_PACKAGES[@]}")

  case "$(get_vendor_id)" in
  AuthenticAMD)
    print --color cyan 'info: detected amd cpu.\n\n'
    system_packages+=('amd-ucode')
    ;;
  GenuineIntel)
    print --color cyan 'info: detected intel cpu.\n\n'
    system_packages+=('intel-ucode')
    ;;
  *)
    print --color red 'error: unknown cpu vendor.\n\n' >&2
    return 1
    ;;
  esac

  if [[ "${install_filesystem_utility_packages}" == 'true' ]]; then
    system_packages+=("${FILESYSTEM_UTILITY_PACKAGES[@]}")
  fi

  system_packages+=("${editor_package}")

  if [[ "${install_driver_packages}" == 'true' ]]; then
    system_packages+=("${COMMON_DRIVER_PACKAGES[@]}")
  fi

  if [[ "${install_pipewire_packages}" == 'true' ]]; then
    system_packages+=("${PIPEWIRE_PACKAGES[@]}")
  fi

  # ----  checks  --------------------------------------------------------------

  if ! is_uefi; then
    print --color red 'error: system not booted in uefi mode.\n\n' >&2
    return 1
  fi

  if ! is_connected; then
    print --color red 'error: unable to connect to the internet.\n\n' >&2
    return 1
  fi

  if [[ ! -e "${BASH_SOURCE%/*}/configure.sh" ]]; then
    print --color red "error: 'configure.sh' not found.\\n\\n" >&2
    return 1
  fi

  # ----  input  ---------------------------------------------------------------

  target_disk="$(input_target_disk)" || return 1

  case "${target_disk}" in
  /dev/sd*)
    root_partition="${target_disk}2"
    boot_partition="${target_disk}1"
    ;;
  /dev/nvme*)
    root_partition="${target_disk}p2"
    boot_partition="${target_disk}p1"
    ;;
  /dev/mmcblk*)
    root_partition="${target_disk}p2"
    boot_partition="${target_disk}p1"
    ;;
  *)
    print --color red 'error: invalid disk.\n\n' >&2
    return 1
    ;;
  esac

  if [[ "${swap}" == 'true' ]]; then
    swap_size="$(input_swap_size)"
  fi

  readarray -t reflector_options < <(input_reflector_options)

  if [[ "${#reflector_options[@]}" -eq 0 ]]; then
    return 1
  fi

  if [[ "${install_driver_packages}" == 'true' ]]; then
    readarray -t driver_packages < <(input_driver_packages)
    system_packages+=("${driver_packages[@]}")
  fi

  readarray -t optional_packages < <(input_optional_packages)
  system_packages+=("${optional_packages[@]}")

  declare -p

  print --color yellow 'warning: installation will wipe target disk.\n\n'
  if ! confirm 'proceed with installation?'; then
    return 0
  fi

  # ----  installation  --------------------------------------------------------

  if ! is_clock_synced; then
    print --color cyan 'info: attempting to sync system clock...\n\n'
    sync_clock || {
      print --color red 'error: failed to sync system clock.\n\n' >&2
      return 1
    }
  fi

  print --color cyan 'info: partitioning disk...\n\n'
  partition_disk "${target_disk}" || {
    print --color red 'error: failed to partition disk.\n\n' >&2
    return 1
  }

  print --color cyan 'info: formatting partitions...\n\n'
  format_partitions "${root_partition}" "${boot_partition}" || {
    print --color red 'error: failed to format partitions.\n\n' >&2
    return 1
  }

  print --color cyan 'info: mounting file systems...\n\n'
  mount_file_systems "${root_partition}" "${boot_partition}" || {
    print --color red 'error: failed to mount file systems.\n\n' >&2
    return 1
  }

  if [[ "${swap}" == 'true' ]]; then
    print --color cyan 'info: creating swap...\n\n'
    create_swap "${swap_size}" || {
      print --color red 'error: failed to create swap.\n\n' >&2
      return 1
    }
  fi

  print --color cyan 'info: updating mirror list...\n\n'
  update_mirror_list "${reflector_options[@]}" || {
    print --color red 'error: failed to update mirror list.\n\n' >&2
    return 1
  }

  print --color cyan 'info: installing system packages...\n\n'
  install_system_packages "${system_packages[@]}" || {
    print --color red 'error: failed to install system packages.\n\n' >&2
    return 1
  }

  print --color cyan 'info: generating fstab...\n\n'
  generate_fstab || {
    print --color red 'error: failed to generate fstab.\n\n' >&2
    return 1
  }

  print --color cyan 'info: changing root to new system...\n\n'
  configure_system || {
    print --color red 'error: failed to configure the system.\n\n' >&2
    return 1
  }

  print --color cyan 'info: installation completed.\n\n'
}

# ------------------------------------------------------------------------------
#       input functions
# ------------------------------------------------------------------------------

confirm() {
  local prompt="$1"
  local input=''

  while true; do
    print --color cyan "${prompt} [y/n]: " >&2
    read -r input
    print '\n' >&2

    case "${input,,}" in
    y | yes)
      return 0
      ;;
    n | no)
      return 1
      ;;
    *)
      print --color red 'error: invalid input. try again.\n\n' >&2
      ;;
    esac
  done
}

input_target_disk() {
  local target_disk=''
  local disks=''

  disks="$(list_disks)" || {
    print --color red 'error: failed to get disks.\n\n' >&2
    return 1
  }

  print --color cyan 'disks:\n' >&2
  printf '%s' "${disks}" | sed 's/^/  - /' >&2
  printf '\n\n' >&2

  while true; do
    print --color cyan 'enter target disk (e.g., "/dev/sda"): ' >&2
    read -r target_disk
    print '\n' >&2

    if target_disk="$(is_disk_valid "${target_disk}" "${disks}")"; then
      break
    else
      print --color red 'error: invalid disk. try again.\n\n' >&2
    fi
  done

  printf '%s' "${target_disk}"
}

input_swap_size() {
  local swap_size=''
  local number=''
  local suffix=''

  while true; do
    print --color cyan 'enter swap size (e.g., "8G"): ' >&2
    read -r swap_size
    print '\n' >&2

    number="${swap_size%%[^[:digit:]]*}"
    suffix="${swap_size##*[[:digit:]]}"

    if [[ "${swap_size}" =~ ^[[:digit:]]+[[:alpha:]]+$ ]]; then
      case "${suffix,,}" in
      g | gb | gib)
        swap_size="${number}GiB"
        break
        ;;
      m | mb | mib)
        swap_size="${number}MiB"
        break
        ;;
      esac
    fi

    print --color red 'error: invalid swap size. try again.\n\n' >&2
  done

  printf '%s' "${swap_size}"
}

input_reflector_options() {
  local reflector_options=()
  local country=''
  local countries=''

  countries="$(list_countries)" || {
    print --color red 'error: failed to get countries.\n\n' >&2
    return 1
  }

  print --color cyan 'info: enter a country ' >&2
  print --color cyan 'to use as filter for reflector.\n' >&2

  print --color cyan "info: enter 'l' to list countries. " >&2
  print --color cyan "enter 'q' to return.\\n\\n" >&2

  while true; do
    print --color cyan 'enter a country (e.g., "Japan"): ' >&2
    read -r country
    print '\n' >&2

    case "${country}" in
    l)
      print "${countries}" |
        column --fillrows |
        less --clear-screen --tilde >&2
      ;;
    *)
      if country="$(is_country_valid "${country}" "${countries}")"; then
        break
      else
        print --color red 'error: invalid country. try again.\n\n' >&2
      fi
      ;;
    esac
  done

  if [[ "${country}" == *' '* ]]; then
    country="'${country}'"
  fi

  reflector_options=(
    '--save' '/etc/pacman.d/mirrorlist'
    '--sort' 'score'
    '--country' "${country}"
  )

  printf '%s\n' "${reflector_options[@]}"
}

input_driver_packages() {
  local driver_packages=()

  if confirm 'install amd driver packages?' >&2; then
    driver_packages+=("${AMD_DRIVER_PACKAGES[@]}")
  fi

  if confirm 'install intel driver packages?' >&2; then
    driver_packages+=("${INTEL_DRIVER_PACKAGES[@]}")
  fi

  printf '%s\n' "${driver_packages[@]}"
}

input_optional_packages() {
  local optional_packages=()
  local package=''

  for package in "${OPTIONAL_PACKAGES[@]}"; do
    if confirm "install ${package}?" >&2; then
      optional_packages+=("${package}")
    fi
  done

  printf '%s\n' "${optional_packages[@]}"
}

# ------------------------------------------------------------------------------
#       install functions
# ------------------------------------------------------------------------------

sync_clock() {
  local config_directory='/etc/systemd/timesyncd.conf.d'
  local config_path="${config_directory}/ntp.conf"

  local ntp_servers=(
    '1.pool.ntp.org'
    '0.pool.ntp.org'
    '2.pool.ntp.org'
    '3.pool.ntp.org'
  )

  mkdir --parents "${config_directory}" || return 1
  printf '[Time]\nNTP=%s\n' "${ntp_servers[*]}" >"${config_path}" || return 1
  systemctl restart systemd-timesyncd.service || return 1

  local interval=5
  local retries=0
  local max_retries=3

  until is_clock_synced; do
    ((++retries > max_retries)) && return 1
    sleep "${interval}"
  done
}

partition_disk() {
  local disk="$1"
  local partition_layout='size=1GiB, type=uefi\n type=linux'
  local sfdisk_options=(
    '--wipe' 'always'
    '--wipe-partitions' 'always'
    '--label' 'gpt'
  )

  sfdisk "${sfdisk_options[@]}" "${disk}" <<<"${partition_layout}" || return 1
}

format_partitions() {
  local root_partition="$1"
  local boot_partition="$2"

  mkfs.ext4 "${root_partition}" || return 1
  mkfs.fat -F 32 "${boot_partition}" || return 1
}

mount_file_systems() {
  local root_partition="$1"
  local boot_partition="$2"

  mount "${root_partition}" /mnt || return 1
  mount --mkdir "${boot_partition}" /mnt/boot || return 1
}

create_swap() {
  local swap_size="$1"

  mkswap --file /mnt/swapfile --size "${swap_size}" --uuid clear || return 1
  swapon /mnt/swapfile || return 1
}

update_mirror_list() {
  local reflector_options=("$@")

  local retries=0
  local max_retries=3

  until reflector "${reflector_options[@]}"; do
    ((++retries > max_retries)) && return 1
    print --color red 'error: failed to update mirror list. ' >&2
    print --color red 'retrying...\n\n' >&2
  done
}

install_system_packages() {
  local system_packages=("$@")

  pacman -Sy --needed --noconfirm archlinux-keyring

  local retries=0
  local max_retries=3

  until pacstrap -K /mnt "${system_packages[@]}"; do
    ((++retries > max_retries)) && return 1
    print --color red 'error: failed to install system packages. ' >&2
    print --color red 'retrying...\n\n' >&2
  done
}

generate_fstab() {
  genfstab -U /mnt >>/mnt/etc/fstab || return 1
}

configure_system() {
  local source_script_path=''
  local copied_script_path=''
  local exit_status=0

  source_script_path="${BASH_SOURCE%/*}/configure.sh"
  copied_script_path='/root/configure.sh'

  cp --force "${source_script_path}" "/mnt/${copied_script_path}" || return 1
  arch-chroot /mnt /bin/bash "${copied_script_path}" || exit_status=1
  rm --force "/mnt/${copied_script_path}" || return 1
  return "${exit_status}"
}

# ------------------------------------------------------------------------------
#       check functions
# ------------------------------------------------------------------------------

is_uefi() {
  if ls /sys/firmware/efi/efivars &>/dev/null; then
    return 0
  else
    return 1
  fi
}

is_connected() {
  if ping -c 1 -W 3 archlinux.org &>/dev/null; then
    return 0
  else
    return 1
  fi
}

is_clock_synced() {
  if [[ "$(timedatectl show -P NTPSynchronized)" == 'yes' ]]; then
    return 0
  else
    return 1
  fi
}

is_disk_valid() {
  local disk="$1"
  local disks="$2"
  local match=''

  match="$(awk -v disk="${disk}" '
    BEGIN { IGNORECASE = 1 }
    $1 == disk { print $1 ; exit }
  ' <<<"${disks}")"

  if [[ -n "${match}" && "${match}" =~ ^/dev/(sd|nvme|mmcblk) ]]; then
    printf '%s' "${match}"
    return 0
  else
    return 1
  fi
}

is_country_valid() {
  local country="$1"
  local countries="$2"
  local match=''

  match="$(awk -v country="${country}" '
    BEGIN { IGNORECASE = 1 }
    $0 == country { print $0 ; exit }
  ' <<<"${countries}")"

  if [[ -n "${match}" ]]; then
    printf '%s' "${match}"
    return 0
  else
    return 1
  fi
}

# ------------------------------------------------------------------------------
#       output functions
# ------------------------------------------------------------------------------

# usage: print [--color color] message
print() {
  local message=''
  local color=''

  while [[ "$#" -gt 0 ]]; do
    case "$1" in
    --color)
      color="$2"
      shift 2
      ;;
    *)
      message="$1"
      shift
      ;;
    esac
  done

  if [[ -n "${color}" ]]; then
    local color_sequence="\\033[1;${COLOR_CODES[${color}]}m"
    local reset_sequence='\033[0m'

    printf '%b' "${color_sequence}${message}${reset_sequence}"
  else
    printf '%b' "${message}"
  fi
}

get_vendor_id() {
  awk '/vendor_id/ { print $NF ; exit }' /proc/cpuinfo
}

list_disks() {
  local disks=''
  local lsblk_options=('--nodeps' '--noheadings' '--output' 'PATH,MODEL')

  disks="$(lsblk "${lsblk_options[@]}" 2>/dev/null)" || return 1

  awk '$1 ~ "^/dev/(sd|nvme|mmcblk)"' <<<"${disks}"
}

list_countries() {
  local countries=''

  countries="$(reflector --list-countries 2>/dev/null)" || return 1

  awk --field-separator='[ ]{2,}' 'FNR > 2 { print $1 }' <<<"${countries}"
}

main
