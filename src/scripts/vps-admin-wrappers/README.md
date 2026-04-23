# VPS admin wrappers — scoped sudo for `openclaw`

Narrowly-scoped root wrappers that let the `openclaw` user install and operate
the Gregor gateway **without** breaching the isolation boundary around the
`demos` / `demos-node` account.

## Design

Every wrapper in `sbin/`:

- Is owned by `root:root`, mode `0755`, in `/usr/local/sbin/`.
- Takes **zero user-controlled arguments** — all targets are hardcoded.
- Accepts no path, package, or unit-name input.
- Never invokes a shell, `sh -c`, editor, or generic `systemctl`/`journalctl`/`apt` command.

The two file-installing wrappers (`openclaw-install-unit`,
`openclaw-install-hardening`) only copy **from** a fixed staging path under
`/home/openclaw/staging/` **to** a single hardcoded destination under
`/etc/systemd/system/`. They reject:

- symlinks at the staging path (TOCTOU defence)
- wrong owner on the staging file
- group- or world-writable staging files
- (for `-install-unit`) staging files that fail `systemd-analyze verify`

This means `openclaw` cannot cause a wrapper to write anywhere outside the one
intended destination, even with a malicious staging file.

## Why not just grant `NOPASSWD: ALL`?

Sudo deny-lists are not a security boundary:

- editors (`sudo vi /some/file` → `:!sh`) give a root shell
- `sudo cp $SYMLINK_TO_DEMOS /tmp/out && cat /tmp/out` reads anywhere
- `sudo bash -c "..."` is a root shell
- loadable kernel modules, `/proc/1/root` indirection, etc.

Scoped wrappers with hardcoded commands are the only approach that preserves
the isolation guarantee against an adversary (or a compromised bot) running
as `openclaw`.

## Installation

From a **root** shell on the VPS:

```bash
cd <path-to-this-repo>/src/scripts/vps-admin-wrappers
./install-wrappers.sh
```

The installer:

1. Copies each `sbin/openclaw-*` to `/usr/local/sbin/` (mode 0755, root:root).
2. Validates the proposed sudoers file with `visudo -c` **before** replacing
   the live file — so a syntax error never locks you out.
3. Swaps in `/etc/sudoers.d/openclaw-restricted-admin`.
4. Prints `sudo -l -U openclaw` so you can verify the final privilege list.

## Wrapper inventory

### Pre-existing (not managed by this installer — leave as-is)

| Wrapper | Purpose |
|---|---|
| `openclaw-system-status` | Read host state |
| `openclaw-demos-node-{start,stop,restart,logs}` | Operate the demos node service |
| `openclaw-firewall-status` | Read-only `ufw status` |
| `openclaw-system-upgrade` | `apt-get update && upgrade` |

### New — install-phase (revokable after Gregor is set up)

| Wrapper | Purpose |
|---|---|
| `openclaw-install-nodejs` | Install Node.js 22 LTS from NodeSource |
| `openclaw-install-ufw` | `apt install ufw` |

### New — firewall (ongoing)

| Wrapper | Purpose |
|---|---|
| `openclaw-ufw-allow-ssh` | `ufw allow 22/tcp` |
| `openclaw-ufw-default-deny` | default-deny incoming + enable |

### New — systemd / Gregor (ongoing)

| Wrapper | Purpose |
|---|---|
| `openclaw-install-unit` | Install `/etc/systemd/system/openclaw.service` from validated staging |
| `openclaw-install-hardening` | Install `openclaw.service.d/hardening.conf` from validated staging |
| `openclaw-gateway-start` | `systemctl start openclaw` |
| `openclaw-gateway-stop` | `systemctl stop openclaw` |
| `openclaw-gateway-restart` | `systemctl restart openclaw` |
| `openclaw-gateway-enable` | `systemctl enable openclaw` |
| `openclaw-gateway-logs` | `journalctl -u openclaw -n 200` (filter is hardcoded) |

## Revoking install-phase wrappers

After Gregor is up and stable, you can remove the install-phase entries from
the sudoers file and delete the scripts:

```bash
# edit /etc/sudoers.d/openclaw-restricted-admin, remove the two
#   openclaw-install-{nodejs,ufw}
# lines, then:
visudo -c
rm /usr/local/sbin/openclaw-install-nodejs /usr/local/sbin/openclaw-install-ufw
```

The repo's sudoers template keeps them in place because re-running
`install-wrappers.sh` should always produce a complete working state. If you
want the installer to stop shipping them, delete the lines and the two scripts
from the repo.

## Adding Dismas later

Not in scope for this installer. When Dismas is added, follow the same
pattern: a parallel set of `dismas-*` wrappers and a parallel sudoers entry
for a separate `dismas` user. Keep the two users' privilege sets disjoint.
