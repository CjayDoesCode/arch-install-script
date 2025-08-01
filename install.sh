#!/usr/bin/env bash

# ------------------------------------------------------------------------------
#       constants
# ------------------------------------------------------------------------------

readonly BASE_SYSTEM_PACKAGES=(
  'base' 'bash' 'bash-completion' 'linux' 'linux-firmware' 'man-db'
  'man-pages' 'networkmanager' 'pacman-contrib' 'reflector' 'sudo' 'texinfo'
)

readonly FILESYSTEM_UTILITY_PACKAGES=(
  'dosfstools' 'e2fsprogs'
  'exfatprogs' 'ntfs-3g'
)

readonly AMD_DRIVER_PACKAGES=('mesa' 'vulkan-radeon' 'xorg-server')
readonly INTEL_DRIVER_PACKAGES=('mesa' 'vulkan-intel' 'xorg-server')

readonly PIPEWIRE_PACKAGES=(
  'pipewire' 'pipewire-alsa' 'pipewire-audio'
  'pipewire-jack' 'pipewire-pulse' 'wireplumber'
)

readonly OPTIONAL_PACKAGES=('base-devel' 'git' 'openssh' 'sof-firmware')

readonly NTP_SERVERS=(
  '0.pool.ntp.org' '1.pool.ntp.org'
  '2.pool.ntp.org' '3.pool.ntp.org'
)

declare -Ar COLOR_CODES=(
  ['black']=30 ['red']=31 ['green']=32 ['yellow']=33
  ['blue']=34 ['magenta']=35 ['cyan']=36 ['white']=37
)

# ------------------------------------------------------------------------------
#       main function
# ------------------------------------------------------------------------------

main() {
  print '\n'

  # ----  variables  -----------------------------------------------------------

  local target_disk=''
  local partitions=()
  local root_partition=''
  local boot_partition=''
  local swap_size=''

  local reflector_country=''
  local reflector_options=()

  local microcode_package=''

  if ! microcode_package="$(get_microcode_package)"; then
    print_error 'unable to identify cpu vendor.\n\n'
    return 1
  fi

  local editor_package='nano'

  while [[ "$#" -gt 0 ]]; do
    case "$1" in
    --editor)
      if [[ -n "$2" ]]; then
        editor_package="$2"
        shift 2
      else
        print_error "missing argument.\n\n"
        return 1
      fi
      ;;
    *)
      print_error 'invalid option.\n\n'
      return 1
      ;;
    esac
  done

  local system_packages=(
    "${BASE_SYSTEM_PACKAGES[@]}"
    "${FILESYSTEM_UTILITY_PACKAGES[@]}"
    "${PIPEWIRE_PACKAGES[@]}"
    "${microcode_package}"
    "${editor_package}"
  )

  local driver_packages=()
  local optional_packages=()

  local time_zone=''
  local locale=''
  local hostname=''

  local user_name=''
  local user_password=''
  local root_password=''

  local passed_variables=()

  # ----  checks  --------------------------------------------------------------

  if ! is_uefi; then
    print_error 'system is not booted in uefi mode.\n\n'
    return 1
  fi

  if ! configure_script_exists; then
    print_error 'unable to find configure script.\n\n'
    return 1
  fi

  # ----  input  ---------------------------------------------------------------

  target_disk="$(input_target_disk)"
  mapfile -t partitions < <(get_partitions "${target_disk}")
  root_partition="${partitions[0]}"
  boot_partition="${partitions[1]}"
  swap_size="$(input_swap_size)"

  reflector_country="$(input_reflector_country)" || return 1
  mapfile -t reflector_options < <(get_reflector_options "${reflector_country}")

  mapfile -t driver_packages < <(input_driver_packages)
  system_packages+=("${driver_packages[@]}")

  mapfile -t optional_packages < <(input_optional_packages)
  system_packages+=("${optional_packages[@]}")

  time_zone="$(input_time_zone)"
  locale="$(input_locale)"
  hostname="$(input_hostname)"

  user_name="$(input_user_name)"
  user_password="$(input_user_password)"
  root_password="$(input_root_password)"

  passed_variables=(
    "${time_zone}" "${locale}" "${hostname}" "${user_name}" "${user_password}"
    "${root_password}" "${root_partition}" "${reflector_country}"
  )

  print --color yellow 'warning: installation will wipe target disk.\n\n'
  confirm 'proceed with installation?' >/dev/null || return

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

  print_info 'creating swap...\n\n'
  if ! create_swap "${swap_size}"; then
    print_error 'failed to create swap.\n\n'
    return 1
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
  if ! configure_system "${passed_variables[@]}"; then
    print_error 'failed to configure system.\n\n'
    return 1
  fi

  print_info 'installation completed.\n\n'
}

# ------------------------------------------------------------------------------
#       helper functions
# ------------------------------------------------------------------------------

get_vendor_id() {
  local vendor_id=''

  local line=''
  while read -r line; do
    if [[ "${line}" == vendor_id* ]]; then
      vendor_id="${line##* }"
      break
    fi
  done </proc/cpuinfo

  printf '%s' "${vendor_id}"
}

get_microcode_package() {
  local microcode_package=''

  case "$(get_vendor_id)" in
  AuthenticAMD)
    microcode_package='amd-ucode'
    ;;
  GenuineIntel)
    microcode_package='intel-ucode'
    ;;
  esac

  printf '%s' "${microcode_package}"
}

is_uefi() {
  [[ -e /sys/firmware/efi/fw_platform_size ]] || return 1
}

get_configure_script() {
  local configure_script=''

  if [[ "${BASH_SOURCE[0]}" == */* ]]; then
    configure_script="${BASH_SOURCE[0]%/*}/configure.sh"
  else
    configure_script='./configure.sh'
  fi

  printf '%s' "${configure_script}"
}

configure_script_exists() {
  [[ -e "$(get_configure_script)" ]] || return 1
}

get_partitions() {
  local disk="$1"

  local root_partition=''
  local boot_partition=''

  case "${disk}" in
  /dev/sd*)
    root_partition="${disk}2"
    boot_partition="${disk}1"
    ;;
  /dev/nvme*)
    root_partition="${disk}p2"
    boot_partition="${disk}p1"
    ;;
  /dev/mmcblk*)
    root_partition="${disk}p2"
    boot_partition="${disk}p1"
    ;;
  esac

  printf '%s\n' "${root_partition}" "${boot_partition}"
}

get_reflector_options() {
  local reflector_country="$1"

  local reflector_options=(
    '--save' '/etc/pacman.d/mirrorlist'
    '--sort' 'age'
    '--latest' '5'
    '--protocol' 'https'
    '--country' "${reflector_country}"
  )

  printf '%s\n' "${reflector_options[@]}"
}

is_clock_synced() {
  [[ "$(timedatectl show -P NTPSynchronized)" == 'yes' ]] || return 1
}

get_disks() {
  local disks=()

  local line=''
  while read -r line; do
    [[ "${line}" =~ ^/dev/(sd|nvme|mmcblk) ]] && disks+=("${line}")
  done < <(lsblk --nodeps --noheadings --output PATH,MODEL)

  printf "%s\n" "${disks[@]}"
}

is_disk_valid() {
  local target_disk="$1"
  local disks=()

  mapfile -t disks < <(get_disks)

  local disk=''
  for disk in "${disks[@]}"; do
    disk="${disk%% *}"
    if [[ "${disk,,}" == "${target_disk,,}" ]]; then
      printf '%s' "${disk}"
      return 0
    fi
  done

  return 1
}

get_countries() {
  local countries=''

  local retries=0
  local max_retries=3
  local interval=5

  until countries=$(reflector --list-countries 2>/dev/null); do
    ((++retries > max_retries)) && return 1
    print_error 'failed to get countries. retrying...\n\n'
    sleep "${interval}"
  done

  local line=''
  local count=0

  while read -r line; do
    ((++count <= 2)) && continue
    printf '%s\n' "${line%%  *}"
  done <<<"${countries}"
}

is_country_valid() {
  local country="$1"
  local countries="$2"

  local line=''
  while read -r line; do
    if [[ "${line,,}" == "${country,,}" ]]; then
      printf '%s' "${line}"
      return 0
    fi
  done <<<"${countries}"

  return 1
}

get_time_zones() {
  timedatectl list-timezones
}

is_time_zone_valid() {
  local time_zone="$1"

  local line=''
  while read -r line; do
    if [[ "${line,,}" == "${time_zone,,}" ]]; then
      printf '%s' "${line}"
      return 0
    fi
  done < <(get_time_zones)

  return 1
}

get_locales() {
  cat /usr/share/i18n/SUPPORTED
}

is_locale_valid() {
  local locale="$1"

  local line=''
  while read -r line; do
    if [[ "${line,,}" == "${locale,,}" ]]; then
      printf '%s' "${line}"
      return 0
    fi
  done < <(get_locales)

  return 1
}

is_hostname_valid() {
  local hostname="$1"
  [[ "${hostname}" =~ ^[[:lower:][:digit:]-]{1,64}$ ]] || return 1
}

is_username_valid() {
  local username="$1"

  if [[ "${username}" != -* ]] &&
    [[ "${#username}" -le 256 ]] &&
    [[ ! "${username}" =~ ^[[:digit:]]+$ ]] &&
    [[ "${username}" =~ ^[[:alnum:]_-]+\$?$ ]]; then
    return 0
  else
    return 1
  fi
}

is_password_valid() {
  local password="$1"
  [[ -n "${password}" ]] || return 1
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

print_info() {
  local message="$1"
  print --color green "info: ${message}"
}

print_error() {
  local message="$1"
  print --color red "error: ${message}" >&2
}

list_disks() {
  local disks=()

  mapfile -t disks < <(get_disks)
  [[ "${#disks[@]}" -eq 0 ]] && return 1

  print --color green 'available disks: \n'
  local disk=''
  for disk in "${disks[@]}"; do
    print "  - ${disk}\n"
  done
  print '\n'
}

# ------------------------------------------------------------------------------
#       input functions
# ------------------------------------------------------------------------------

# usage: scan [--password] prompt
scan() {
  local prompt=''
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

  print --color blue "${prompt}" >&2

  if [[ "${password}" == 'true' ]]; then
    read -rs input
    print '\n\n' >&2
  else
    read -r input
    print '\n' >&2
  fi

  printf '%s' "${input}"
}

input_target_disk() {
  local target_disk=''

  print --color green "enter 'l' to list disks.\n\n" >&2

  while true; do
    target_disk="$(scan 'enter target disk (e.g., /dev/nvme0n1): ')"

    if [[ "${target_disk}" == 'l' ]]; then
      list_disks >&2 || print_error 'no available disks found.\n\n'
    else
      target_disk="$(is_disk_valid "${target_disk}")" && break
      print_error 'invalid disk. try again.\n\n'
    fi
  done

  printf '%s' "${target_disk}"
}

input_swap_size() {
  local swap_size=''

  local number=''
  local suffix=''

  while true; do
    swap_size="$(scan 'enter swap size (e.g., 8g): ')"

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

    print_error 'invalid swap size. try again.\n\n'
  done

  printf '%s' "${swap_size}"
}

input_reflector_country() {
  local country=''
  local countries=''

  if ! countries="$(get_countries)"; then
    print_error 'failed to get countries.\n\n'
    return 1
  fi

  print --color green 'enter a country to use as filter for reflector.\n' >&2
  print --color green "enter 'l' to list countries. " >&2
  print --color green "enter 'q' to return.\n\n" >&2

  while true; do
    country="$(scan 'enter a country (e.g., japan): ')"

    if [[ "${country}" == 'l' ]]; then
      column <<<"${countries}" | less --tilde >&2
    else
      country="$(is_country_valid "${country}" "${countries}")" && break
      print_error 'invalid country. try again.\n\n'
    fi
  done

  [[ "${country}" == *' '* ]] && country="'${country}'"

  printf '%s' "${country}"
}

confirm() {
  local prompt="$1"
  local input=''

  while true; do
    input="$(scan "${prompt} [Y/n]: ")"

    if [[ -z "${input}" ]]; then
      printf 'true'
      return 0
    fi

    case "${input,,}" in
    y | yes)
      printf 'true'
      return 0
      ;;
    n | no)
      printf 'false'
      return 1
      ;;
    *)
      print_error 'invalid input. try again.\n\n'
      ;;
    esac
  done
}

input_driver_packages() {
  local driver_packages=()

  if confirm 'install amd driver packages?' >/dev/null; then
    driver_packages+=("${AMD_DRIVER_PACKAGES[@]}")
  fi

  if confirm 'install intel driver packages?' >/dev/null; then
    driver_packages+=("${INTEL_DRIVER_PACKAGES[@]}")
  fi

  printf '%s\n' "${driver_packages[@]}"
}

input_optional_packages() {
  local optional_packages=()

  local package=''
  for package in "${OPTIONAL_PACKAGES[@]}"; do
    if confirm "install ${package}?" >/dev/null; then
      optional_packages+=("${package}")
    fi
  done

  printf '%s\n' "${optional_packages[@]}"
}

input_time_zone() {
  local time_zone=''

  print --color green "enter 'l' to list time zones. " >&2
  print --color green "enter 'q' to return.\n\n" >&2

  while true; do
    time_zone="$(scan 'enter time zone (e.g., asia/tokyo): ')"

    if [[ "${time_zone}" == 'l' ]]; then
      get_time_zones | column | less --tilde >&2
    else
      time_zone="$(is_time_zone_valid "${time_zone}")" && break
      print_error 'invalid time zone. try again.\n\n'
    fi
  done

  printf '%s' "${time_zone}"
}

input_locale() {
  local locale=''

  print --color green "enter 'l' to list locales. enter 'q' to return.\n\n" >&2

  while true; do
    locale="$(scan 'enter locale (e.g., en_us.utf-8 utf-8): ')"

    if [[ "${locale}" == 'l' ]]; then
      get_locales | column | less --tilde >&2
    else
      locale="$(is_locale_valid "${locale}")" && break
      print_error 'invalid locale. try again.\n\n'
    fi
  done

  printf '%s' "${locale}"
}

input_hostname() {
  local hostname=''

  while true; do
    hostname="$(scan 'enter hostname (e.g., archlinux): ')"
    is_hostname_valid "${hostname}" && break
    print_error 'invalid hostname. try again.\n\n'
  done

  printf '%s' "${hostname}"
}

input_user_name() {
  local user_name=''

  while true; do
    user_name="$(scan 'enter user name: ')"
    is_username_valid "${user_name}" && break
    print_error 'invalid user name. try again.\n\n'
  done

  printf '%s' "${user_name}"
}

input_user_password() {
  local user_password=''
  local reentered_password=''

  while true; do
    user_password="$(scan --password 'enter user password: ')"

    if ! is_password_valid "${user_password}"; then
      print_error 'invalid password. try again.\n\n'
      continue
    fi

    reentered_password="$(scan --password 'reenter user password: ')"
    [[ "${user_password}" == "${reentered_password}" ]] && break
    print_error 'passwords do not match. try again.\n\n'
  done

  printf '%s' "${user_password}"
}

input_root_password() {
  local root_password=''
  local reentered_password=''

  while true; do
    root_password="$(scan --password 'enter root password: ')"

    if ! is_password_valid "${root_password}"; then
      print_error 'invalid password. try again.\n\n'
      continue
    fi

    reentered_password="$(scan --password 'reenter root password: ')"
    [[ "${root_password}" == "${reentered_password}" ]] && break
    print_error 'passwords do not match. try again.\n\n'
  done

  printf '%s' "${root_password}"
}

# ------------------------------------------------------------------------------
#       install functions
# ------------------------------------------------------------------------------

sync_clock() {
  local config_directory='/etc/systemd/timesyncd.conf.d'
  local config="${config_directory}/ntp.conf"

  mkdir --parents "${config_directory}" || return 1
  printf '[Time]\nNTP=%s\n' "${NTP_SERVERS[*]}" >"${config}" || return 1
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

  local layout='size=1GiB, type=uefi\n type=linux\n'
  local sfdisk_options=(
    '--label' 'gpt'
    '--wipe' 'always'
    '--wipe-partitions' 'always'
  )

  printf '%b' "${layout}" | sfdisk "${sfdisk_options[@]}" "${disk}" || return 1
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

  local mkswap_options=(
    '--file' '/mnt/swapfile'
    '--size' "${swap_size}"
    '--uuid' 'clear'
  )

  mkswap "${mkswap_options[@]}" || return 1
  swapon /mnt/swapfile || return 1
}

update_mirror_list() {
  local reflector_options=("$@")

  local retries=0
  local max_retries=3
  local interval=5

  until reflector "${reflector_options[@]}" 2>/dev/null; do
    ((++retries > max_retries)) && return 1
    print_error 'failed to update mirror list. retrying...\n\n'
    sleep "${interval}"
  done
}

install_system_packages() {
  local system_packages=("$@")

  pacman -Sy --needed --noconfirm archlinux-keyring || return 1

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
  local passed_variables=("$@")

  local source_script=''
  local script='/root/configure.sh'

  source_script="$(get_configure_script)"

  cp --force "${source_script}" "/mnt/${script}" || return 1
  arch-chroot /mnt /bin/bash "${script}" "${passed_variables[@]}" || return 1
  rm --force "/mnt/${script}" || return 1
}

main "$@"
