# killswitch

## Design

The kill path has the fewest possible moving parts because it is used in an
emergency: iPhone Shortcuts → Tailscale → macOS's launchd-activated sshd → a
forced command in `~/.ssh/authorized_keys`. No daemon, dispatcher file, or build
step. `install.sh` and `uninstall.sh` are the whole implementation; the README
owns the manual steps (Remote Login toggle, lock setting, Shortcut setup).

## Invariants

- The forced command is the only thing between the Shortcuts key and a shell.
  Shortcuts has one SSH key per device, shared by every SSH action, so the key's
  line must always carry `restrict`, `from=`, and `command=`.
- `from=` holds the iPhone's own Tailscale IPv4 and IPv6 addresses, resolved at
  install time with `tailscale ip -4/-6 <name>`. Both are needed because
  MagicDNS returns both and iOS may connect over either.
- Unknown input exits 1. Verbs match the whole `$SSH_ORIGINAL_COMMAND`, so
  `lock; whoami` falls through to `*`.
- The Shortcut reports success only when the action can run: `shutdown` first
  checks the sudoers rule with `sudo -n -l` and exits 1 if it is missing.
- The forced command runs in the user's login shell (often zsh); keep it valid
  in both bash and zsh, and free of double quotes (it sits inside
  `command="…"`).
- `/sbin/shutdown -h now` in the forced command (both the `-l` check and the
  real call) must match the sudoers rule character for character.
- `sshd.conf` is the host's whole sshd policy, rendered with `@USER@` → the
  installing user and installed as `/etc/ssh/sshd_config.d/010-local.conf`.
  Remote Login is only safe with it in place, so `uninstall.sh` leaves it
  installed; it goes with Remote Login.
- The sshd policy is deliberately opinionated (one user, Tailscale only, ed25519
  only, no forwarding). `install.sh` installs it when no `010-local.conf` exists
  or the installed one matches, and stops otherwise.
- `sshd.conf` accepts only ed25519 keys; `install.sh` rejects other key types.
- Install converges: each run writes the full content of every file and replaces
  the `restrict,from=…` line ending in ` killswitch`.

## Gotchas

- `lock` runs `pmset displaysleepnow`, which only darkens the display; macOS
  locks after the screen-lock delay. Any delay leaves a window in which someone
  at the keyboard wakes the Mac unlocked, so `install.sh` requires
  `sysadminctl -screenLock status` to report immediate. sysadminctl writes that
  status through NSLog, to stderr. The wording for a non-zero delay is
  `screenLock delay is 5 seconds`; the check matches `immediate` for the
  Immediately setting.
- The Tailscale addresses are stable per node. A re-added iPhone gets new ones;
  rerun `install.sh`.
- sshd keeps the first value it reads for each option, and
  `/etc/ssh/sshd_config` includes `sshd_config.d/*` in lexical order; `010-`
  sorts before macOS's `100-macos.conf`.
- macOS launches sshd per connection, so config changes take effect without a
  reload.
- `systemsetup -setremotelogin` requires Full Disk Access for the terminal; the
  System Settings toggle is the supported path.
- `shutdown` runs under `nohup … &` with stdin, stdout, and stderr on
  `/dev/null` so the SSH session returns and the Shortcut reports success before
  the Mac goes down.
- macOS ignores the legacy `askForPassword` defaults keys; the lock setting is
  changed in System Settings only.
