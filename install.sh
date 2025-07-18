#!/usr/bin/env bash

# ------------------------------------------------------------------------------
#       main function
# ------------------------------------------------------------------------------

main() {
  print '\n'

  # ----  configuration  -------------------------------------------------------

  local create_user='true'
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

  local reflector_country=''
  local reflector_options=()

  local system_packages=()
  local driver_packages=()
  local optional_packages=()

  local base_system_packages=(
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

  local filesystem_utility_packages=(
    'dosfstools'
    'e2fsprogs'
    'exfatprogs'
    'ntfs-3g'
  )

  local common_driver_packages=('mesa' 'xorg-server')

  local pipewire_packages=(
    'pipewire'
    'pipewire-alsa'
    'pipewire-audio'
    'pipewire-jack'
    'pipewire-pulse'
    'wireplumber'
  )

  local time_zone=''

  local locale=''
  local lang=''

  local hostname=''

  local user_name=''
  local user_password=''

  local root_password=''

  system_packages+=("${base_system_packages[@]}")

  case "$(get_vendor_id)" in
  AuthenticAMD)
    print_info 'detected amd cpu.\n\n'
    system_packages+=('amd-ucode')
    ;;
  GenuineIntel)
    print_info 'detected intel cpu.\n\n'
    system_packages+=('intel-ucode')
    ;;
  *)
    print_error 'unknown cpu vendor.\n\n'
    return 1
    ;;
  esac

  if [[ "${install_filesystem_utility_packages}" == 'true' ]]; then
    system_packages+=("${filesystem_utility_packages[@]}")
  fi

  system_packages+=("${editor_package}")

  if [[ "${install_driver_packages}" == 'true' ]]; then
    system_packages+=("${common_driver_packages[@]}")
  fi

  if [[ "${install_pipewire_packages}" == 'true' ]]; then
    system_packages+=("${pipewire_packages[@]}")
  fi

  # ----  checks  --------------------------------------------------------------

  if ! is_uefi; then
    print_error 'system not booted in uefi mode.\n\n'
    return 1
  fi

  if ! is_connected; then
    print_error 'unable to connect to the internet.\n\n'
    return 1
  fi

  if [[ ! -e "${BASH_SOURCE%/*}/configure.sh" ]]; then
    print_error "'configure.sh' not found.\n\n"
    return 1
  fi

  # ----  input  ---------------------------------------------------------------

  target_disk="$(input_target_disk)"

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
    print_error 'invalid disk.\n\n'
    return 1
    ;;
  esac

  [[ "${swap}" == 'true' ]] && swap_size="$(input_swap_size)"

  reflector_country="$(input_reflector_country)" || return 1

  reflector_options=(
    '--save' '/etc/pacman.d/mirrorlist'
    '--sort' 'score'
    '--country' "${reflector_country}"
  )

  if [[ "${install_driver_packages}" == 'true' ]]; then
    readarray -t driver_packages < <(input_driver_packages)
    system_packages+=("${driver_packages[@]}")
  fi

  readarray -t optional_packages < <(input_optional_packages)
  system_packages+=("${optional_packages[@]}")

  time_zone="$(input_time_zone)"

  locale="$(input_locale)"
  lang="${locale%%[[:space:]]*}"

  hostname="$(input_hostname)"

  if [[ "${create_user}" == 'true' ]]; then
    user_name="$(input_user_name)"
    user_password="$(input_user_password)"
  fi

  root_password="$(input_root_password)"

  declare -p

  print_warning 'installation will wipe target disk.\n\n'
  confirm 'proceed with installation?' || return

  # ----  installation  --------------------------------------------------------

  if ! is_clock_synced; then
    print_info 'attempting to sync system clock...\n\n'
    if ! sync_clock; then
      print_error 'failed to sync system clock.\n\n'
      return 1
    fi
  fi

  print_info 'partitioning disk...\n\n'
  if ! partition_disk "${target_disk}"; then
    print_error 'failed to partition disk.\n\n'
    return 1
  fi

  print_info 'formatting partitions...\n\n'
  if ! format_partitions "${root_partition}" "${boot_partition}"; then
    print_error 'failed to format partitions.\n\n'
    return 1
  fi

  print_info 'mounting file systems...\n\n'
  if ! mount_file_systems "${root_partition}" "${boot_partition}"; then
    print_error 'failed to mount file systems.\n\n'
    return 1
  fi

  if [[ "${swap}" == 'true' ]]; then
    print_info 'creating swap...\n\n'
    if ! create_swap "${swap_size}"; then
      print_error 'failed to create swap.\n\n'
      return 1
    fi
  fi

  print_info 'updating mirror list...\n\n'
  if ! update_mirror_list "${reflector_options[@]}"; then
    print_error 'failed to update mirror list.\n\n'
    return 1
  fi

  print_info 'installing system packages...\n\n'
  if ! install_system_packages "${system_packages[@]}"; then
    print_error 'failed to install system packages.\n\n'
    return 1
  fi

  print_info 'generating fstab...\n\n'
  if ! generate_fstab; then
    print_error 'failed to generate fstab.\n\n'
    return 1
  fi

  print_info 'configuring system...\n\n'
  if ! configure_system; then
    print_error 'failed to configure system.\n\n'
    return 1
  fi

  print_info 'installation completed.\n\n'
}

# ------------------------------------------------------------------------------
#       input functions
# ------------------------------------------------------------------------------

# usage: scan [--password] prompt
scan() {
  local prompt="$1"
  local input=''
  local password='false'

  while [[ "$#" -gt 0 ]]; do
    case "$1" in
    --password)
      password='true'
      shift
      ;;
    *)
      prompt="$1"
      shift
      ;;
    esac
  done

  print --color cyan "${prompt}" >&2
  if [[ "${password}" == 'true' ]]; then
    read -rs input
    print '\n\n' >&2
  else
    read -r input
    print '\n' >&2
  fi

  print "${input}"
}

input_target_disk() {
  local target_disk=''

  list_disks >&2

  while true; do
    target_disk="$(scan 'enter target disk (e.g., "/dev/sda"): ')"
    target_disk="$(is_disk_valid "${target_disk}")" && break
    print_error 'invalid disk. try again.\n\n'
  done

  print "${target_disk}"
}

input_swap_size() {
  local swap_size=''
  local number=''
  local suffix=''

  while true; do
    swap_size="$(scan 'enter swap size (e.g., "8g"): ')"
    number="${swap_size%%[^[:digit:]]*}"
    suffix="${swap_size##*[[:digit:]]}"

    if [[ "${swap_size}" =~ ^[[:digit:]]+[[:alpha:]]+$ ]]; then
      case "${suffix,,}" in
      g | gb | gib)
        suffix="GiB"
        break
        ;;
      m | mb | mib)
        suffix="MiB"
        break
        ;;
      *)
        print_error 'invalid suffix. try again.\n\n'
        ;;
      esac
    else
      print_error 'invalid swap size. try again.\n\n'
    fi
  done

  swap_size="${number}${suffix}"

  print "${swap_size}"
}

input_reflector_country() {
  local country=''

  local countries=''
  countries="$(list_countries)" || return 1

  print_info 'enter a country to use as filter for reflector.\n' >&2
  print_info "enter 'l' to list countries. enter 'q' to return.\n\n" >&2

  while true; do
    country="$(scan 'enter a country (e.g., "japan"): ')"

    if [[ "${country}" == 'l' ]]; then
      column <<<"${countries}" | less --clear-screen --tilde >&2
    else
      country="$(is_country_valid "${country}" "${countries}")" && break
      print_error 'invalid country. try again.\n\n'
    fi
  done

  [[ "${country}" == *[[:space:]]* ]] && country="'${country}'"

  print "${country}"
}

confirm() {
  local prompt="$1"
  local input=''

  while true; do
    input="$(scan "${prompt} [y/n]: ")"

    case "${input,,}" in
    y | yes) return 0 ;;
    n | no) return 1 ;;
    *) print_error 'invalid input. try again.\n\n' ;;
    esac
  done
}

input_driver_packages() {
  local amd_driver_packages=('vulkan-radeon')
  local intel_driver_packages=('vulkan-intel')
  local driver_packages=()

  if confirm 'install amd driver packages?'; then
    driver_packages+=("${amd_driver_packages[@]}")
  fi

  if confirm 'install intel driver packages?'; then
    driver_packages+=("${intel_driver_packages[@]}")
  fi

  local package=''
  for package in "${driver_packages[@]}"; do
    print "${package}\n"
  done
}

input_optional_packages() {
  local optional_packages=('base-devel' 'git' 'openssh' 'sof-firmware')
  local packages=()
  local package=''

  for package in "${optional_packages[@]}"; do
    confirm "install ${package}?" && packages+=("${package}")
  done

  for package in "${packages[@]}"; do
    print "${package}\n"
  done
}

input_time_zone() {
  local time_zone=''

  print_info "enter 'l' to list time zones. enter 'q' to exit.\n\n" >&2

  while true; do
    time_zone="$(scan 'enter time zone (e.g., "asia/tokyo"): ')"

    if [[ "${time_zone}" == 'l' ]]; then
      get_time_zones | column | less --clear-screen --tilde >&2
    else
      time_zone="$(is_time_zone_valid "${time_zone}")" && break
      print_error 'invalid time zone. try again.\n\n'
    fi
  done

  print "${time_zone}"
}

input_locale() {
  local locale=''

  print_info "enter 'l' to list locales. enter 'q' to exit.\n\n" >&2

  while true; do
    locale="$(scan 'enter locale (e.g., "en_us.utf-8 utf-8"): ')"

    if [[ "${locale}" == 'l' ]]; then
      get_locales | column | less --clear-screen --tilde >&2
    else
      locale="$(is_locale_valid "${locale}")" && break
      print_error 'invalid locale. try again.\n\n'
    fi
  done

  print "${locale}"
}

input_hostname() {
  local hostname=''

  while true; do
    hostname="$(scan 'enter hostname (e.g., archlinux): ')"
    [[ -n "${hostname}" ]] && break
    print_error 'invalid hostname. try again.\n\n'
  done

  print "${hostname}"
}

input_user_name() {
  local user_name=''

  while true; do
    user_name="$(scan 'enter user name: ')"
    [[ -n "${user_name}" ]] && break
    print_error 'invalid user name. try again.\n\n'
  done

  print "${user_name}"
}

input_user_password() {
  local user_password=''
  local reentered_password=''

  while true; do
    user_password="$(scan --password 'enter user password: ')"
    reentered_password="$(scan --password 'reenter user password: ')"

    [[ "${user_password}" == "${reentered_password}" ]] && break
    print_error 'passwords do not match. try again.\n\n'
  done

  print "${user_password}"
}

input_root_password() {
  local root_password=''
  local reentered_password=''

  while true; do
    root_password="$(scan --password 'enter root password: ')"
    reentered_password="$(scan --password 'reenter user password: ')"

    [[ "${root_password}" == "${reentered_password}" ]] && break
    print_error 'passwords do not match. try again.\n\n'
  done

  print "${root_password}"
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
  print "[Time]\nNTP=${ntp_servers[*]}\n" >"${config_path}" || return 1
  systemctl restart systemd-timesyncd.service || return 1

  local retries=0
  local max_retries=3
  local interval=5

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
  local interval=5

  until reflector "${reflector_options[@]}"; do
    ((++retries > max_retries)) && return 1
    print_error 'failed to update mirror list. retrying...\n\n'
    sleep "${interval}"
  done
}

install_system_packages() {
  local system_packages=("$@")

  pacman -Sy --needed --noconfirm archlinux-keyring

  local retries=0
  local max_retries=3
  local interval=5

  until pacstrap -K /mnt "${system_packages[@]}"; do
    ((++retries > max_retries)) && return 1
    print_error 'failed to install system packages. retrying...\n\n'
    sleep "${interval}"
  done
}

generate_fstab() {
  genfstab -U /mnt >>/mnt/etc/fstab || return 1
}

configure_system() {
  local source_script_path="${BASH_SOURCE%/*}/configure.sh"
  local copied_script_path='/root/configure.sh'
  local exit_status=0

  cp --force "${source_script_path}" "/mnt/${copied_script_path}" || return 1
  arch-chroot /mnt /bin/bash "${copied_script_path}" || exit_status=1
  rm --force "/mnt/${copied_script_path}" || return 1

  return "${exit_status}"
}

# ------------------------------------------------------------------------------
#       check functions
# ------------------------------------------------------------------------------

is_uefi() {
  ls /sys/firmware/efi/efivars &>/dev/null || return 1
}

is_connected() {
  ping -c 1 -W 5 archlinux.org &>/dev/null || return 1
}

is_clock_synced() {
  [[ "$(timedatectl show -P NTPSynchronized)" == 'yes' ]] || return 1
}

is_disk_valid() {
  local disk="$1"
  local match=''

  match="$(awk -v disk="${disk}" '
    BEGIN { IGNORECASE = 1 }
    $1 == disk { print $1 ; exit }
  ' <<<"$(get_disks)")"

  [[ "${match}" =~ ^/dev/(sd|nvme|mmcblk) ]] && print "${match}" || return 1
}

is_country_valid() {
  local country="$1"
  local countries="$2"
  local match=''

  match="$(awk -v country="${country}" '
    BEGIN { IGNORECASE = 1 }
    $0 == country { print $0 ; exit }
  ' <<<"${countries}")"

  [[ -n "${match}" ]] && print "${match}" || return 1
}

is_time_zone_valid() {
  local time_zone="$1"
  local match

  match="$(awk -v time_zone="${time_zone}" '
    BEGIN { IGNORECASE = 1 }
    $0 == time_zone { print $0 ; exit }
  ' <<<"$(get_time_zones)")"

  [[ -n "${match}" ]] && print "${match}" || return 1
}

is_locale_valid() {
  local locale="$1"

  match="$(awk -v locale="${locale}" '
    BEGIN { IGNORECASE = 1 }
    $0 == locale { print $0 ; exit }
  ' <<<"$(get_locales)")"

  [[ -n "${match}" ]] && print "${match}" || return 1
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
    declare -Ar color_codes=(
      [black]=30
      [red]=31
      [green]=32
      [yellow]=33
      [blue]=34
      [magenta]=35
      [cyan]=36
      [white]=37
    )

    local color_code="${color_codes[${color}]}"
    local color_sequence="\\033[1;${color_code}m"
    local reset_sequence='\033[0m'

    printf '%b' "${color_sequence}${message}${reset_sequence}"
  else
    printf '%b' "${message}"
  fi
}

print_info() {
  local message="$1"
  print --color cyan "info: ${message}"
}

print_warning() {
  local message="$1"
  print --color yellow "warning: ${message}"
}

print_error() {
  local message="$1"
  print --color red "error: ${message}" >&2
}

get_vendor_id() {
  awk '/vendor_id/ { print $NF ; exit }' /proc/cpuinfo
}

get_disks() {
  local disks=''
  local lsblk_options=('--nodeps' '--noheadings' '--output' 'PATH,MODEL')

  disks="$(lsblk "${lsblk_options[@]}")"

  awk '$1 ~ "^/dev/(sd|nvme|mmcblk)"' <<<"${disks}"
}

list_disks() {
  local disk=''

  print --color cyan 'disks:\n'

  while read -r disk; do
    print "  - ${disk}\n"
  done <<<"$(get_disks)"

  print '\n'
}

list_countries() {
  local countries=''

  if ! countries="$(reflector --list-countries 2>/dev/null)"; then
    print_error 'failed to get countries.\n\n'
    return 1
  fi

  awk '
    BEGIN { FS="[[:space:]]{2,}" }
    FNR > 2 { print $1 }
  ' <<<"${countries}"
}

get_time_zones() {
  timedatectl list-timezones
}

get_locales() {
  cat /usr/share/i18n/SUPPORTED
}

main
