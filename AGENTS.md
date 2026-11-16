# killswitch

## Design

The kill path has the fewest possible moving parts because it is used in an
emergency: iPhone Shortcuts → Tailscale → macOS's launchd-activated sshd → a
forced command in `~/.ssh/authorized_keys`. No daemon, dispatcher file, or build
step. `install.sh` and `uninstall.sh` are the whole implementation; the README
owns the manual steps (Remote Login toggle, Shortcut setup).

## Invariants

- The forced command is the only thing between the Shortcuts key and a shell.
  Shortcuts has one SSH key per device, shared by every SSH action, so the key's
  line must always carry `restrict`, `from=`, and `command=`.
- Unknown input exits 1. Verbs match the whole `$SSH_ORIGINAL_COMMAND`, so
  `lock; whoami` falls through to `*`.
- The forced command runs in the user's login shell (often zsh); keep it valid
  in both bash and zsh, and free of double quotes (it sits inside
  `command="…"`).
- `sudo -n /sbin/shutdown -h now` in the forced command must match the sudoers
  rule character for character.
- `010-local.conf` is the host's whole sshd policy, rendered with `@USER@` → the
  installing user. Remote Login is only safe with it in place, so `uninstall.sh`
  leaves it installed; it goes with Remote Login.
- The sshd policy is deliberately opinionated (one user, Tailscale only, ed25519
  only, no forwarding). `install.sh` installs it when no `010-local.conf` exists
  or the installed one matches, and stops otherwise.
- `010-local.conf` accepts only ed25519 keys; `install.sh` rejects other key
  types.
- Install converges: each run writes the full content of every file and replaces
  the line ending in ` killswitch`.

## Gotchas

- sshd keeps the first value it reads for each option, and
  `/etc/ssh/sshd_config` includes `sshd_config.d/*` in lexical order; `010-`
  sorts before macOS's `100-macos.conf`.
- macOS launches sshd per connection, so config changes take effect without a
  reload.
- `systemsetup -setremotelogin` requires Full Disk Access for the terminal; the
  System Settings toggle is the supported path.
- `shutdown` runs under `nohup … &` with closed fds so the SSH session returns
  and the Shortcut reports success before the Mac goes down.
- `lock` only locks when the Lock Screen password setting is **Immediately**;
  macOS ignores the legacy `askForPassword` defaults keys.
