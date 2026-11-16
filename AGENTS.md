# killswitch

## Design

The kill path has the fewest possible moving parts because it is used in an
emergency: iPhone Shortcuts → Tailscale → macOS's launchd-activated sshd → a
forced command in `~/.ssh/authorized_keys`. That key line is the only installed
piece on the kill path. `command.sh` holds the verb logic; `install.sh` joins
its lines into the key line's `command="…"`. The README owns the manual steps
(Remote Login toggle, lock setting, Shortcut setup).

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
  checks the sudoers rule with `sudo -n -l` and exits 1 if it is missing. sudo's
  error message passes through to the Shortcut, which shows it as the failure
  reason.
- `command.sh` stays valid once its lines are joined: `install.sh` strips each
  line's leading indentation, joins lines with a single space, rejects double
  quotes and backslashes (sshd treats both specially inside `command="…"`), and
  runs `bash -n -c` and `zsh -n -c` on the result before installing. Every line
  ends in `in`, `;;`, or `esac`, and comments are invalid (a `#` swallows the
  rest of the joined line).
- It runs in the user's login shell (often zsh): keep it valid in bash and zsh.
  Lint with `shellcheck --shell=bash command.sh` and `zsh -n command.sh`. shfmt
  rewrites it into one-statement-per-line form, which no longer joins, so
  `command.sh` is formatted by hand.
- Tests of `command.sh` on a Mac with killswitch installed exercise `lock` and
  invalid input only: the sudoers rule makes `shutdown` real.
- `/sbin/shutdown -h now` in `command.sh` (both the `-l` check and the real
  call) must match the sudoers rule character for character.
- `sshd.conf` is the host's whole sshd policy, rendered with `@USER@` → the
  installing user and installed as `/etc/ssh/sshd_config.d/010-local.conf`.
  Remote Login is only safe with it in place, so `uninstall.sh` leaves it
  installed; it goes with Remote Login.
- The sshd policy is deliberately opinionated (one user, Tailscale only, ed25519
  only, no forwarding). `install.sh` installs it when no `010-local.conf` exists
  or the installed one matches, and stops otherwise. `--no-sshd-policy` skips it
  for hosts that own their SSH access policy (a home server reached over LAN
  SSH); the key line's `restrict`, `from=`, and `command=` protect the kill path
  either way.
- `sshd.conf` accepts only ed25519 keys; `install.sh` rejects other key types.
- Install converges: each run writes the full content of every file and replaces
  the `restrict,from=…` line ending in ` killswitch`.

## Gotchas

- `lock` runs `pmset displaysleepnow`, which only darkens the display; macOS
  locks after the screen-lock delay. Any delay leaves a window in which someone
  at the keyboard wakes the Mac unlocked, so `install.sh` requires
  `sysadminctl -screenLock status` to report immediate, and `lock` in
  `command.sh` checks it again after darkening the display and exits 1 if the
  setting has drifted. sysadminctl reports the real setting from an SSH session.
  sysadminctl writes that status through NSLog, to stderr:
  `screenLock delay is immediate` or `screenLock delay is 5 seconds`.
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
