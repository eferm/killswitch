#!/usr/bin/env bash
# Harden sshd and authorize an iPhone Shortcuts SSH key to lock or shut down this Mac over Tailscale.

set -euo pipefail

PUBLIC_KEY="${1:?usage: install.sh 'ssh-ed25519 AAAA...'}"
USER_NAME="$(id -un)"
REPO_DIRECTORY="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SSHD_TEMPLATE_PATH="${REPO_DIRECTORY}/010-local.conf"
SSHD_DROPIN_PATH="/etc/ssh/sshd_config.d/010-local.conf"
SUDOERS_PATH="/etc/sudoers.d/killswitch"
AUTHORIZED_KEYS_PATH="${HOME}/.ssh/authorized_keys"
# Tailscale's IPv4 CGNAT range and IPv6 ULA prefix.
TAILSCALE_SOURCES="100.64.0.0/10,fd7a:115c:a1e0::/48"
# Runs in the login shell for every connection with this key, whatever the client asks for.
# shellcheck disable=SC2016 # $SSH_ORIGINAL_COMMAND is expanded by the login shell at connection time.
FORCED_COMMAND='case $SSH_ORIGINAL_COMMAND in lock) pmset displaysleepnow ;; shutdown) nohup sudo -n /sbin/shutdown -h now >/dev/null 2>&1 & ;; *) exit 1 ;; esac'
readonly PUBLIC_KEY USER_NAME REPO_DIRECTORY SSHD_TEMPLATE_PATH SSHD_DROPIN_PATH SUDOERS_PATH AUTHORIZED_KEYS_PATH TAILSCALE_SOURCES FORCED_COMMAND

WORK_DIRECTORY="$(mktemp -d)"
readonly WORK_DIRECTORY
trap 'rm -rf "${WORK_DIRECTORY}"' EXIT

require_remote_login() {
  if ! nc -z localhost 22; then
    printf 'Remote Login is off. Turn it on in System Settings > General > Sharing, then rerun.\n' >&2
    exit 1
  fi
}

read_key() {
  printf '%s\n' "${PUBLIC_KEY}" >"${WORK_DIRECTORY}/key.pub"
  ssh-keygen -l -f "${WORK_DIRECTORY}/key.pub" >/dev/null
  read -r KEY_TYPE KEY_BODY _ <<<"${PUBLIC_KEY}"
  # 010-local.conf accepts only ed25519 keys.
  if [[ "${KEY_TYPE}" != "ssh-ed25519" ]]; then
    printf 'Expected an ssh-ed25519 key, got %s.\n' "${KEY_TYPE}" >&2
    exit 1
  fi
}

install_sshd_dropin() {
  sed "s/@USER@/${USER_NAME}/g" "${SSHD_TEMPLATE_PATH}" >"${WORK_DIRECTORY}/010-local.conf"
  if [[ -e "${SSHD_DROPIN_PATH}" ]] && ! cmp -s "${WORK_DIRECTORY}/010-local.conf" "${SSHD_DROPIN_PATH}"; then
    printf '%s exists with different settings. Move it aside or merge it into %s, then rerun.\n' \
      "${SSHD_DROPIN_PATH}" "${SSHD_TEMPLATE_PATH}" >&2
    exit 1
  fi
  sudo install -m 644 -o root -g wheel "${WORK_DIRECTORY}/010-local.conf" "${SSHD_DROPIN_PATH}"
  sudo sshd -t
  printf 'INSTALL %s\n' "${SSHD_DROPIN_PATH}"
}

install_sudoers_rule() {
  printf '%s ALL=(root) NOPASSWD: /sbin/shutdown -h now\n' "${USER_NAME}" >"${WORK_DIRECTORY}/sudoers"
  visudo -cqf "${WORK_DIRECTORY}/sudoers"
  sudo install -m 440 -o root -g wheel "${WORK_DIRECTORY}/sudoers" "${SUDOERS_PATH}"
  printf 'INSTALL %s\n' "${SUDOERS_PATH}"
}

install_key_line() {
  install -d -m 700 "${HOME}/.ssh"
  touch "${AUTHORIZED_KEYS_PATH}"
  sed '/ killswitch$/d' "${AUTHORIZED_KEYS_PATH}" >"${WORK_DIRECTORY}/authorized_keys"
  printf 'restrict,from="%s",command="%s" %s %s killswitch\n' \
    "${TAILSCALE_SOURCES}" "${FORCED_COMMAND}" "${KEY_TYPE}" "${KEY_BODY}" >>"${WORK_DIRECTORY}/authorized_keys"
  install -m 600 "${WORK_DIRECTORY}/authorized_keys" "${AUTHORIZED_KEYS_PATH}"
  printf 'INSTALL %s\n' "${AUTHORIZED_KEYS_PATH}"
}

main() {
  require_remote_login
  read_key
  install_sshd_dropin
  install_sudoers_rule
  install_key_line
}

main
