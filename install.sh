#!/usr/bin/env bash
# Authorize an iPhone Shortcuts SSH key to lock or shut down this Mac over Tailscale, and harden sshd.

set -euo pipefail

USAGE="usage: install.sh 'ssh-ed25519 AAAA...' IPHONE_TAILSCALE_NAME [--no-sshd-policy]"
PUBLIC_KEY="${1:?${USAGE}}"
IPHONE_NAME="${2:?${USAGE}}"
# --no-sshd-policy leaves sshd as configured, for hosts with their own SSH access policy.
SSHD_POLICY_OPTION="${3:-}"
USER_NAME="$(id -un)"
REPO_DIRECTORY="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SSHD_TEMPLATE_PATH="${REPO_DIRECTORY}/sshd.conf"
SSHD_DROPIN_PATH="/etc/ssh/sshd_config.d/010-local.conf"
SUDOERS_PATH="/etc/sudoers.d/killswitch"
AUTHORIZED_KEYS_PATH="${HOME}/.ssh/authorized_keys"
FORCED_COMMAND_PATH="${REPO_DIRECTORY}/command.sh"
readonly USAGE PUBLIC_KEY IPHONE_NAME SSHD_POLICY_OPTION USER_NAME REPO_DIRECTORY SSHD_TEMPLATE_PATH SSHD_DROPIN_PATH SUDOERS_PATH AUTHORIZED_KEYS_PATH FORCED_COMMAND_PATH

WORK_DIRECTORY="$(mktemp -d)"
readonly WORK_DIRECTORY
trap 'rm -rf "${WORK_DIRECTORY}"' EXIT

require_remote_login() {
	if ! nc -z localhost 22 2>/dev/null; then
		printf 'Remote Login is off. Turn it on in System Settings > General > Sharing, then rerun.\n' >&2
		exit 1
	fi
}

# lock only darkens the display; macOS locks after the screen-lock delay.
require_immediate_screen_lock() {
	local status
	status="$(sysadminctl -screenLock status 2>&1)"
	if [[ "${status}" != *immediate* ]]; then
		printf 'Screen lock is not immediate (%s).\n' "${status##*] }" >&2
		printf 'Set System Settings > Lock Screen > Require password after screen saver begins or display is off to Immediately, then rerun.\n' >&2
		exit 1
	fi
}

read_key() {
	printf '%s\n' "${PUBLIC_KEY}" >"${WORK_DIRECTORY}/key.pub"
	ssh-keygen -l -f "${WORK_DIRECTORY}/key.pub" >/dev/null
	read -r KEY_TYPE KEY_BODY _ <<<"${PUBLIC_KEY}"
	# Shortcuts keys are plain ssh-ed25519 or RSA; sshd.conf accepts only the former.
	if [[ "${KEY_TYPE}" != "ssh-ed25519" ]]; then
		printf 'Expected an ssh-ed25519 key, got %s.\n' "${KEY_TYPE}" >&2
		exit 1
	fi
}

# The key is accepted only from the iPhone's own Tailscale addresses.
resolve_iphone_sources() {
	local ipv4 ipv6
	ipv4="$(tailscale ip -4 "${IPHONE_NAME}")"
	ipv6="$(tailscale ip -6 "${IPHONE_NAME}")"
	IPHONE_SOURCES="${ipv4},${ipv6}"
}

install_sshd_dropin() {
	if [[ "${SSHD_POLICY_OPTION}" == "--no-sshd-policy" ]]; then
		return
	fi
	sed "s/@USER@/${USER_NAME}/g" "${SSHD_TEMPLATE_PATH}" >"${WORK_DIRECTORY}/010-local.conf"
	if [[ -e "${SSHD_DROPIN_PATH}" ]] && ! cmp -s "${WORK_DIRECTORY}/010-local.conf" "${SSHD_DROPIN_PATH}"; then
		printf '%s exists with different settings. Move it aside or merge it into %s, then rerun.\n' \
			"${SSHD_DROPIN_PATH}" "${SSHD_TEMPLATE_PATH}" >&2
		exit 1
	fi
	# Validate the candidate ahead of the live config: sshd starts per connection, so a bad drop-in breaks every login.
	printf 'Include %s\nInclude /etc/ssh/sshd_config\n' "${WORK_DIRECTORY}/010-local.conf" >"${WORK_DIRECTORY}/sshd_config"
	sudo sshd -t -f "${WORK_DIRECTORY}/sshd_config"
	sudo install -m 644 -o root -g wheel "${WORK_DIRECTORY}/010-local.conf" "${SSHD_DROPIN_PATH}"
	printf 'INSTALL %s\n' "${SSHD_DROPIN_PATH}"
}

# sshd runs the forced command in the login shell for every connection with this key.
# authorized_keys holds it on one line inside command="…", where sshd treats " and \ specially,
# so the file's lines are unindented and joined with spaces, then parsed as the login shell will.
read_forced_command() {
	FORCED_COMMAND="$(sed 's/^[[:space:]]*//' "${FORCED_COMMAND_PATH}" | tr '\n' ' ')"
	FORCED_COMMAND="${FORCED_COMMAND% }"
	[[ "${FORCED_COMMAND}" != *[\"\\]* ]] || exit 1
	bash -n -c "${FORCED_COMMAND}"
	zsh -n -c "${FORCED_COMMAND}"
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
	sed '/^restrict,from=.* killswitch$/d' "${AUTHORIZED_KEYS_PATH}" >"${WORK_DIRECTORY}/authorized_keys"
	printf 'restrict,from="%s",command="%s" %s %s killswitch\n' \
		"${IPHONE_SOURCES}" "${FORCED_COMMAND}" "${KEY_TYPE}" "${KEY_BODY}" >>"${WORK_DIRECTORY}/authorized_keys"
	install -m 600 "${WORK_DIRECTORY}/authorized_keys" "${AUTHORIZED_KEYS_PATH}"
	printf 'INSTALL %s (from %s)\n' "${AUTHORIZED_KEYS_PATH}" "${IPHONE_SOURCES}"
}

main() {
	require_remote_login
	require_immediate_screen_lock
	read_key
	read_forced_command
	resolve_iphone_sources
	install_sshd_dropin
	install_sudoers_rule
	install_key_line
}

main
