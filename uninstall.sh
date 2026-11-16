#!/usr/bin/env bash
# Remove the killswitch key line and sudoers rule from this Mac.

set -euo pipefail

SUDOERS_PATH="/etc/sudoers.d/killswitch"
AUTHORIZED_KEYS_PATH="${HOME}/.ssh/authorized_keys"
readonly SUDOERS_PATH AUTHORIZED_KEYS_PATH

WORK_DIRECTORY="$(mktemp -d)"
readonly WORK_DIRECTORY
trap 'rm -rf "${WORK_DIRECTORY}"' EXIT

remove_key_line() {
	touch "${AUTHORIZED_KEYS_PATH}"
	sed '/^restrict,from=.* killswitch$/d' "${AUTHORIZED_KEYS_PATH}" >"${WORK_DIRECTORY}/authorized_keys"
	install -m 600 "${WORK_DIRECTORY}/authorized_keys" "${AUTHORIZED_KEYS_PATH}"
	printf 'REMOVE killswitch line from %s\n' "${AUTHORIZED_KEYS_PATH}"
}

remove_sudoers_rule() {
	sudo rm -f -- "${SUDOERS_PATH}"
	printf 'REMOVE %s\n' "${SUDOERS_PATH}"
}

main() {
	remove_key_line
	remove_sudoers_rule
	# Removing 010-local.conf while Remote Login is on re-enables password logins; remove both together.
	printf 'Remote Login and /etc/ssh/sshd_config.d/010-local.conf are unchanged; remove them together.\n'
}

main
