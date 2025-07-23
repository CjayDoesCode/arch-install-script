#!/usr/bin/env bash

# ------------------------------------------------------------------------------
#       constants
# ------------------------------------------------------------------------------

readonly NTP_SERVERS=(
  '0.pool.ntp.org' '1.pool.ntp.org'
  '2.pool.ntp.org' '3.pool.ntp.org'
)

readonly MKINITCPIO_HOOKS=(
  'systemd' 'autodetect' 'microcode'
  'modconf' 'kms' 'block' 'filesystems'
)

declare -Ar COLOR_CODES=(
  [black]=30 [red]=31 [green]=32 [yellow]=33
  [blue]=34 [magenta]=35 [cyan]=36 [white]=37
)

# ------------------------------------------------------------------------------
#       main function
# ------------------------------------------------------------------------------

main() {
  # ----  variables  -----------------------------------------------------------

  local time_zone="$1"
  local locale="$2"
  local lang="${locale%% *}"
  local hostname="$3"

  local user_name="$4"
  local user_password="$5"
  local root_password="$6"

  local root_partition="$7"
  local root_partition_uuid=''

  if ! root_partition_uuid="$(get_root_partition_uuid)"; then
    print_error 'failed to get root partition uuid.\n\n'
    return 1
  fi

  local kernel_parameters=(
    "root=UUID=${root_partition_uuid}"
    "rw"
    "quiet"
    "loglevel=3"
    "systemd.show_status=auto"
    "rd.udev.log_level=3"
  )

  local reflector_country="$8"
  local reflector_options=(
    '--save' '/etc/pacman.d/mirrorlist'
    '--sort' 'age'
    '--latest' '5'
    '--protocol' 'https'
    '--country' "${reflector_country}"
  )

  # ----  configuration  -------------------------------------------------------

  print_info 'setting time zone...\n\n'
  if ! set_time_zone "${time_zone}"; then
    print_error 'failed to set time zone.\n\n'
    return 1
  fi

  print_info 'setting hardware clock...\n\n'
  if ! set_hardware_clock; then
    print_error 'failed to set hardware clock.\n\n'
    return 1
  fi

  print_info 'setting up time synchronization...\n\n'
  if ! set_up_time_synchronization; then
    print_error 'failed to set up time synchronization.\n\n'
    return 1
  fi

  print_info 'generating locale...\n\n'
  if ! generate_locale "${locale}"; then
    print_error 'failed to generate locale.\n\n'
    return 1
  fi

  print_info 'setting locale...\n\n'
  if ! set_locale "${lang}"; then
    print_error 'failed to set locale.\n\n'
    return 1
  fi

  print_info 'setting hostname...\n\n'
  if ! set_hostname "${hostname}"; then
    print_error 'failed to set hostname.\n\n'
    return 1
  fi

  print_info 'enabling network manager...\n\n'
  if ! enable_network_manager; then
    print_error 'failed to enable network manager.\n\n'
    return 1
  fi

  print_info 'regenerating initramfs image...\n\n'
  if ! regenerating_initramfs_image; then
    print_error 'failed to regenerate initramfs image.\n\n'
    return 1
  fi

  print_info 'configuring mkinitcpio...\n\n'
  if ! configure_mkinitcpio; then
    print_error 'failed to configure mkinitcpio.\n\n'
    return 1
  fi

  print_info 'creating user...\n\n'
  if ! create_user "${user_name}" "${user_password}"; then
    print_error 'failed to create user.\n\n'
    return 1
  fi

  print_info 'setting root password...\n\n'
  if ! set_root_password "${root_password}"; then
    print_error 'failed to set root password.\n\n'
    return 1
  fi

  print_info 'configuring sudo...\n\n'
  if ! configure_sudo; then
    print_error 'failed to configure sudo.\n\n'
    return 1
  fi

  print_info 'installing boot loader...\n\n'
  if ! install_boot_loader; then
    print_error 'failed to install boot loader.\n\n'
    return 1
  fi

  print_info 'configuring boot loader...\n\n'
  if ! configure_boot_loader "${kernel_parameters[@]}"; then
    print_error 'failed to configure boot loader.\n\n'
    return 1
  fi

  print_info 'configuring pacman...\n\n'
  if ! configure_pacman; then
    print_error 'failed to configure pacman.\n\n'
    return 1
  fi

  print_info 'setting up reflector...\n\n'
  if ! set_up_reflector "${reflector_options[@]}"; then
    print_error 'failed to set up reflector.\n\n'
    return 1
  fi

  print_info 'enabling paccache timer...\n\n'
  if ! enable_paccache_timer; then
    print_error 'failed to enable paccache timer.\n\n'
    return 1
  fi
}

# ------------------------------------------------------------------------------
#       helper functions
# ------------------------------------------------------------------------------

get_root_partition_uuid() {
  lsblk --noheadings --output UUID "${root_partition}" || return 1
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

# ------------------------------------------------------------------------------
#       configuration functions
# ------------------------------------------------------------------------------

set_time_zone() {
  local time_zone="$1"

  local target="/usr/share/zoneinfo/${time_zone}"
  local directory='/etc/localtime'

  ln --force --symbolic "${target}" "${directory}" || return 1
}

set_hardware_clock() {
  hwclock --systohc || return 1
}

set_up_time_synchronization() {
  local config_directory='/etc/systemd/timesyncd.conf.d'
  local config="${config_directory}/ntp.org"

  mkdir --parents "${config_directory}" || return 1
  printf '[Time]\nNTP=%s\n' "${NTP_SERVERS[*]}" >"${config}" || return 1
  systemctl enable systemd-timesyncd.service || return 1
}

generate_locale() {
  local locale="$1"
  sed -i "/^#${locale}/s/^#//" /etc/locale.gen || return 1
  locale-gen || return 1
}

set_locale() {
  local lang="$1"
  printf 'LANG=%s\n' "${lang}" >/etc/locale.conf || return 1
}

set_hostname() {
  local hostname="$1"
  printf '%s\n' "${hostname}" >/etc/hostname || return 1
}

enable_network_manager() {
  systemctl enable NetworkManager.service || return 1
}

configure_mkinitcpio() {
  local config='/etc/mkinitcpio.conf.d/hooks.conf'
  printf 'HOOKS=(%s)\n' "${MKINITCPIO_HOOKS[*]}" >"${config}" || return 1
}

regenerating_initramfs_image() {
  mkinitcpio --allpresets || return 1
}

create_user() {
  local user_name="$1"
  local user_password="$2"

  useradd --create-home --groups wheel "${user_name}" || return 1
  passwd --stdin "${user_name}" <<<"${user_password}" || return 1
}

set_root_password() {
  local root_password="$1"
  passwd --stdin root <<<"${root_password}" || return 1
}

configure_sudo() {
  printf '%%wheel ALL=(ALL) ALL\n' >/etc/sudoers.d/wheel || return 1
  chmod 0440 /etc/sudoers.d/wheel || return 1
}

install_boot_loader() {
  bootctl install || return 1
}

configure_boot_loader() {
  local kernel_parameters=("$@")

  cat <<-LOADER >/boot/loader/loader.conf || return 1
		default       arch.conf
		timeout       0
		console-mode  max
		editor        no
	LOADER

  cat <<-ENTRY >/boot/loader/entries/arch.conf || return 1
		title    Arch Linux
		linux    /vmlinuz-linux
		initrd   /initramfs-linux.img
		options  ${kernel_parameters[*]}
	ENTRY

  cat <<-ENTRY >/boot/loader/entries/arch-fallback.conf || return 1
		title    Arch Linux (fallback)
		linux    /vmlinuz-linux
		initrd   /initramfs-linux-fallback.img
		options  ${kernel_parameters[*]}
	ENTRY
}

configure_pacman() {
  sed -i "/^#\(Color\|VerbosePkgLists\)/s/^#//" /etc/pacman.conf || return 1
}

set_up_reflector() {
  local reflector_options=("$@")
  local config='/etc/xdg/reflector/reflector.conf'

  printf "%s\n" "${reflector_options[*]}" >"${config}" || return 1
  systemctl enable reflector.timer || return 1
}

enable_paccache_timer() {
  systemctl enable paccache.timer || return 1
}

main "$@"
