# niri

The compositor configuration, its session scripts, and the two visual part slots.

| | |
|---|---|
| Target | `~/.config/niri/` |
| Packages | `niri`, `kitty`, `nautilus`, `wireplumber`, `libnotify`, `python`, `noctalia` |
| Reload | `niri msg action reload-config` |
| chmod | `scripts/*.sh`, `scripts/*.py` |

## Why those packages

They are the programs the shipped configuration actually invokes, so `deps niri`
is self-sufficient: `kitty` (Mod+Return), `nautilus` (Mod+E), `wpctl`
(volume and mute keys), `noctalia` (session startup and the action gateway),
`notify-send` (EyeCare notification), `python3` (scratchpad wrapper). The
declaration lives in `MODULE_REQUIRED_COMMANDS`, and `check` refuses a `spawn`
that nobody declared.

## Optional programs

Declared in `MODULE_OPTIONAL_COMMANDS`, each one behind its own `command -v`
guard, so a missing binary costs one feature instead of a working desktop.
`setup` lists the ones this machine lacks; only the ones you name get installed:

```bash
noctalia-mod setup --with fcitx5 --with ddcutil
```

| Program | What it carries |
|---|---|
| `wlsunset` | the process `toggle-eyecare.sh` reconciles `effects.kdl` against |
| `ddcutil` | brightness on external monitors over DDC/CI (`niri-brightness.sh`) |
| `tmux` | keeps the scratchpad terminal session alive (`niri-scratch-toggle.sh`) |
| `flatpak` | Mission Center scratchpad entry from a flatpak install |
| `fcitx5` | input method, spawned at startup from `config.kdl` |

## Preserved files

`monitor.kdl`, `effects.kdl`, `effects_normal.kdl`, `glow.kdl`, `colors.kdl`

These are written at runtime, not by the repo:

- `monitor.kdl` — `nwg-displays`
- `colors.kdl` — rendered by Noctalia from the Material You palette
- `effects.kdl` — a symlink whose target encodes EyeCare state. The module ships
  an initial `effects.kdl -> effects_normal.kdl` so a fresh install resolves
  `include "effects.kdl"` before `toggle-eyecare.sh` has ever run
- `effects_normal.kdl`, `glow.kdl` — carry the selected part variant across deploys

Because they are declared preserve they are also excluded from the drift
fingerprint: repointing `effects.kdl` is expected behaviour, not drift.

## Parts

| Slot | Target file | Options |
|---|---|---|
| `effects` | `effects_normal.kdl` | `default`, `xray-blur` |
| `glow` | `glow.kdl` | `default`, `glow`, `glow-material-you` |

A part switch overwrites its own target on purpose — that target is excluded
from the preserve copy for the slot — while everything else is preserved as usual.

## Custom files

`__custom__.kdl` and `input__custom__.kdl` are included by `config.kdl` and are
never overwritten.
