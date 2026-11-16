# killswitch

Lock or shut down a Mac from an iPhone Shortcut over Tailscale.

`install.sh` also installs a strict sshd policy as
`/etc/ssh/sshd_config.d/010-local.conf`: SSH logins only for you, only over
Tailscale, only with an ed25519 key, no forwarding. It stops if a different
`010-local.conf` already exists. Add `--no-sshd-policy` as the last argument to
keep the Mac's existing sshd configuration, e.g. on a home server reached over
LAN SSH.

## Requirements

- Mac and iPhone on the same tailnet
- Admin account on the Mac
- Tailscale CLI on the Mac (Tailscale app → Settings → CLI integration)
- Tested on macOS 27 and iOS 26

## Setup

1. **Mac:** System Settings → General → Sharing → **Remote Login** on.
2. **Mac:** System Settings → Lock Screen → Require password after screen saver
   begins or display is off → **Immediately**.
3. **iPhone:** Shortcuts → create **Lock Mac** and **Shut Down Mac**, each with
   one **Run Script Over SSH** action:
   - Script: `lock` or `shutdown`
   - Host: `<mac>.<tailnet>.ts.net`
   - Port: `22`
   - User: output of `id -un` on the Mac
   - Authentication: SSH Key (ed25519)
   - Input: leave empty
4. **iPhone:** tap the key → **Copy Public Key**. Universal Clipboard carries it
   to the Mac. If the key isn't ed25519, use **Generate New Key** → ED25519
   first; this replaces the key used by every SSH shortcut on the iPhone.
5. **Mac:**

   ```sh
   ./install.sh "$(pbpaste)" <iphone-tailscale-name>
   ```

   The key then works only from that iPhone's Tailscale addresses. Rerun after
   the iPhone is re-added to the tailnet.

## Uninstall

```sh
./uninstall.sh
```
