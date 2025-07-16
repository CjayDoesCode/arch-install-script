#!/usr/bin/env bash

# ------------------------------------------------------------------------------
#       main function
# ------------------------------------------------------------------------------

main() {
  printf '\n'

  # ----  configuration  -------------------------------------------------------

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
  local base_system_packages=(
    'base'
    'bash'
    'bash-completion'
    'linux'
    'linux-firmware'
    'man-db'
    'man-pages'
    'nano'
    'networkmanager'
    'pacman-contrib'
    'reflector'
    'sudo'
    'texinfo'
  )

  local filesystem_utility_packages=(
    'dosfstools'
    'e2fsprogs'
    'exfatprogs'
    'ntfs-3g'
  )

  local common_driver_packages=('mesa' 'xorg-server')
  local amd_driver_packages=('vulkan-radeon')
  local intel_driver_packages=('vulkan-intel')

  local pipewire_packages=(
    'pipewire'
    'pipewire-alsa'
    'pipewire-audio'
    'pipewire-jack'
    'pipewire-pulse'
    'wireplumber'
  )

  local optional_packages=('base-devel' 'git' 'openssh' 'sof-firmware')

  system_packages+=("${base_system_packages[@]}")

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
    exit 1
    ;;
  esac

  if [[ "${install_filesystem_utility_packages}" == 'true' ]]; then
    system_packages+=("${filesystem_utility_packages[@]}")
  fi

  if [[ "${install_driver_packages}" == 'true' ]]; then
    system_packages+=("${common_driver_packages[@]}")
  fi

  if [[ "${install_pipewire_packages}" == 'true' ]]; then
    system_packages+=("${pipewire_packages[@]}")
  fi

  # ----  checks  --------------------------------------------------------------

  if ! is_uefi; then
    print --color red 'error: system is not booted in uefi mode.\n\n' >&2
    exit 1
  fi

  if ! is_connected; then
    print --color red 'error: failed to connect to the internet.\n\n' >&2
    exit 1
  fi

  if [[ ! -e "$(dirname "$0")/configure.sh" ]]; then
    print --color red 'error: failed to find configure.sh.\n\n' >&2
    exit 1
  fi

  # ----  input  ---------------------------------------------------------------

  {
    read -r target_disk
    read -r root_partition
    read -r boot_partition
  } < <(input_target_disk)

  if [[ "${swap}" == 'true' ]]; then
    read -r swap_size < <(input_swap_size)
  fi

  readarray -t reflector_options < <(input_reflector_options)

  if [[ "${install_driver_packages}" == 'true' ]]; then
    if [[ "$(confirm 'install amd driver packages?')" == 'true' ]]; then
      system_packages+=("${amd_driver_packages[@]}")
    fi

    if [[ "$(confirm 'install intel driver packages?')" == 'true' ]]; then
      system_packages+=("${intel_driver_packages[@]}")
    fi
  fi

  for package in "${optional_packages[@]}"; do
    if [[ "$(confirm "install ${package}?")" == 'true' ]]; then
      system_packages+=("${package}")
    fi
  done

  print --color red 'warning: installation will wipe target disk.\n'
  if [[ "$(confirm 'proceed with installation?')" != 'true' ]]; then
    exit 0
  fi

  # ----  installation  --------------------------------------------------------

  if ! is_clock_synced; then
    print --color cyan 'info: attempting to sync system clock...\n\n'
    sync_clock || {
      print --color red 'error: failed to sync system clock.\n\n' >&2
      exit 1
    }
  fi

  print --color cyan 'info: partitioning disk...\n\n'
  partition_disk "${target_disk}" || {
    print --color red 'error: failed to partition disk.\n\n' >&2
    exit 1
  }

  print --color cyan 'info: formatting partitions...\n\n'
  format_partitions "${root_partition}" "${boot_partition}" || {
    print --color red 'error: failed to format partitions.\n\n' >&2
    exit 1
  }

  print --color cyan 'info: mounting file systems...\n\n'
  mount_file_systems "${root_partition}" "${boot_partition}" || {
    print --color red 'error: failed to mount file systems.\n\n' >&2
    exit 1
  }

  if [[ "${swap}" == 'true' ]]; then
    print --color cyan 'info: creating swap...\n\n'
    create_swap "${swap_size}" || {
      print --color red 'error: failed to create swap.\n\n' >&2
      exit 1
    }
  fi

  print --color cyan 'info: updating mirror list...\n\n'
  update_mirror_list "${reflector_options[@]}" || {
    print --color red 'error: failed to update mirror list.\n\n' >&2
    exit 1
  }

  print --color cyan 'info: installing system packages...\n\n'
  install_system_packages "${system_packages[@]}" || {
    print --color red 'error: failed to install system packages.\n\n' >&2
    exit 1
  }

  print --color cyan 'info: generating fstab...\n\n'
  generate_fstab || {
    print --color red 'error: failed to generate fstab.\n\n' >&2
    exit 1
  }

  print --color cyan 'info: changing root to new system...\n\n'
  configure_system || {
    print --color red 'error: failed to configure the system.\n\n' >&2
    exit 1
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
    printf '\n' >&2

    case "${input,,}" in
    y | yes)
      printf 'true'
      break
      ;;
    n | no)
      printf 'false'
      break
      ;;
    *)
      print --color red 'error: invalid input. try again.\n\n' >&2
      ;;
    esac
  done
}

input_target_disk() {
  local target_disk=''
  local root_partition=''
  local boot_partition=''

  local disks=''
  if ! disks="$(list_disks)"; then
    print --color red 'error: failed to get disks.\n\n' >&2
    exit 1
  fi

  print --color cyan 'disks:\n' >&2
  printf '%s' "${disks}" | sed 's/^/  - /' >&2
  printf '\n\n' >&2

  while true; do
    print --color cyan 'enter target disk (e.g., "/dev/sda"): ' >&2
    read -r target_disk
    printf '\n' >&2

    target_disk="${target_disk,,}"

    if is_disk_valid "${target_disk}"; then
      case "${target_disk}" in
      /dev/sd*)
        root_partition="${target_disk}2"
        boot_partition="${target_disk}1"
        break
        ;;
      /dev/nvme*)
        root_partition="${target_disk}p2"
        boot_partition="${target_disk}p1"
        break
        ;;
      /dev/mmcblk*)
        root_partition="${target_disk}p2"
        boot_partition="${target_disk}p1"
        break
        ;;
      *)
        print --color red 'error: invalid disk. try again.\n\n' >&2
        ;;
      esac
    elif [[ "$?" -eq 2 ]]; then
      print --color red 'error: failed to get disks.\n\n' >&2
      exit 1
    else
      print --color red 'error: invalid disk. try again.\n\n' >&2
    fi
  done

  local return_list=(
    "${target_disk}"
    "${root_partition}"
    "${boot_partition}"
  )

  printf '%s\n' "${return_list[@]}"
}

input_swap_size() {
  local swap_size=''
  local number=''
  local suffix=''

  while true; do
    print --color cyan 'enter swap size (e.g., "8G"): ' >&2
    read -r swap_size
    printf '\n' >&2

    swap_size="${swap_size,,}"
    number="${swap_size%%[^[:digit:]]*}"
    suffix="${swap_size##*[[:digit:]]}"

    if [[ "${swap_size}" == "${number}${suffix}" ]]; then
      case "${suffix}" in
      g | gib)
        swap_size="${number}GiB"
        break
        ;;
      m | mib)
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
  local country=''
  local countries=''

  print --color cyan 'info: enter a country ' >&2
  print --color cyan 'to use as filter for reflector.\n' >&2

  print --color cyan "info: enter 'l' to list countries. " >&2
  print --color cyan "enter 'q' to return.\\n\\n" >&2

  while true; do
    print --color cyan 'enter a country (e.g., "Japan"): ' >&2
    read -r country
    printf '\n' >&2

    case "${country}" in
    l)
      if countries="$(list_countries)"; then
        printf '%s' "${countries}" |
          column --fillrows |
          less --clear-screen --tilde >&2
      else
        print --color red 'error: failed to get countries.\n\n' >&2
        exit 1
      fi
      ;;
    *)
      if is_country_valid "${country}"; then
        break
      elif [[ "$?" -eq 2 ]]; then
        print --color red 'error: failed to get countries.\n\n' >&2
        exit 1
      else
        print --color red 'error: invalid country. try again.\n\n' >&2
      fi
      ;;
    esac
  done

  if printf '%s' "${country}" | grep --quiet ' '; then
    country="'${country}'"
  fi

  local return_list=(
    '--save' '/etc/pacman.d/mirrorlist'
    '--sort' 'score'
    '--country' "${country}"
  )

  printf '%s\n' "${return_list[@]}"
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
  local target_disk="$1"
  local partition_layout='size=1GiB, type=uefi\n type=linux\n'
  local sfdisk_options='--wipe always --wipe-partitions always --label gpt'

  printf '%s' "${partition_layout}" |
    sfdisk "${sfdisk_options}" "${target_disk}" || return 1
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
  genfstab -U /mnt >>/mnt/etc/fstab
}

configure_system() {
  local source_script_path=''
  local copied_script_path=''
  local exit_status=0

  source_script_path="$(dirname "$0")/configure.sh"
  copied_script_path="/root/configure.sh"

  cp --force "${source_script_path}" "/mnt/${copied_script_path}" || return 1

  if ! arch-chroot /mnt /bin/bash "${copied_script_path}"; then
    exit_status="$?"
  fi

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

is_disk_valid() {
  local disk="$1"
  local disks=''

  if ! disks="$(list_disks)"; then
    return 2
  fi

  if printf '%s' "${disks}" | grep --quiet "^${disk}\b"; then
    return 0
  else
    return 1
  fi
}

is_country_valid() {
  local country="$1"
  local countries=''

  if ! countries="$(list_countries)"; then
    return 2
  fi

  if printf '%s' "${countries}" | grep --quiet "^${country}\$"; then
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
    declare -A color_codes=(
      [black]=30
      [red]=31
      [green]=32
      [yellow]=33
      [blue]=34
      [magenta]=35
      [cyan]=36
      [white]=37
    )

    local color_sequence=''
    local reset_sequence=''

    color_sequence="\\033[1;${color_codes[${color}]}m"
    reset_sequence='\033[0m'

    printf '%b' "${color_sequence}${message}${reset_sequence}"
  else
    printf '%b' "${message}"
  fi
}

get_vendor_id() {
  awk '/vendor_id/ { print $NF ; exit 1 }' /proc/cpuinfo
}

list_disks() {
  local disks=''
  local lsblk_options=('--nodeps' '--noheadings' '--output' 'PATH,MODEL')

  if ! disks="$(lsblk "${lsblk_options[@]}" 2>/dev/null)"; then
    return 1
  fi

  printf '%s' "${disks}" | awk '$1 ~ "^/dev/(sd|nvme|mmcblk)"'
}

list_countries() {
  local countries=''

  if ! countries="$(reflector --list-countries 2>/dev/null)"; then
    return 1
  fi

  printf '%s' "${countries}" |
    awk --field-separator='[ ]{2,}' 'FNR > 2 { print $1 }'
}

main
