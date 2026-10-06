# greeter

Turns Noctalia Greeter into the login screen: writes the greetd session, the
polkit rule, the service switch.

| | |
|---|---|
| Kind | system module — `actions/*.sh`, no target tree |
| Needs root | yes — the engine primes `sudo` once before any action runs |
| Packages | `greetd` |
| AUR | `noctalia-greeter` |
| Actions | `install`, `status`, `uninstall` |

```bash
noctalia-mod install greeter
noctalia-mod status greeter
noctalia-mod uninstall greeter
```

This module is never selected implicitly: `install --yes` installs every
configuration module, and you have to name `greeter` to let it touch `/etc` and
the display manager.

## What it writes

| Path | Content |
|---|---|
| `/etc/greetd/config.toml` | the `noctalia-greeter-session` command, `user = "greeter"` |
| `/etc/polkit-1/rules.d/50-noctalia-greeter.rules` | lets group `wheel` sync the greeter's appearance |
| `/var/lib/noctalia-greeter` | owned by `greeter:greeter`, mode 755 |
| `/etc/greetd/noctalia-mod-display-manager` | which display manager was enabled before, mode 600 |

Every file is written with `sudo install` from a private temporary file — the
content never passes through a shell. Before anything is written, the previous
content of the two files that may already exist is captured, and `cp -n` backups
are made. Uninstall restores a backup when there is one, and otherwise removes a
file only after confirming it is the one this module wrote.

## The session argument must be trusted

`noctalia-greeter-session` is written into a root-owned file and executed as root,
so it has to be a regular executable owned by root inside `/usr/bin` or
`/usr/local/bin`, with every ancestor directory root-owned and not group- or
world-writable. Anything else is refused before a single privileged command runs.
`-- --session niri` is added only when `noctalia-greeter sessions` actually lists
niri.

## Switching the display manager

`greetd` is enabled first and the conflicting manager (`sddm`, `lightdm`, `gdm`,
`ly` — whichever is enabled) is disabled. The previous manager is recorded before
the switch, so a failed `systemctl enable greetd` puts it back and rolls the files
away. If greetd is already enabled, a re-run only refreshes the configuration and
leaves the record alone. Nothing is started or restarted: the change takes effect
at the next login.

Uninstall disables greetd, re-enables the recorded manager (`enable --force`,
because the `display-manager.service` alias has to be taken back) and then restores
or removes the files. Unlike the old engine it still disables greetd when no
previous manager was recorded — refusing there would leave the user stuck, and it
says plainly that there is nothing to re-enable. Packages are never removed.
