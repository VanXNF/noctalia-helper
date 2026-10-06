# fcitx5

The NyxMellow input-method skin (dynamic, follows the current Noctalia palette) and
the Rime Ice schema setup.

| | |
|---|---|
| Kind | system module — `actions/*.sh`, no target tree |
| Packages | `fcitx5`, `fcitx5-gtk`, `fcitx5-qt`, `fcitx5-configtool`, `fcitx5-rime` |
| AUR | `rime-ice-git` (the schema data) |
| Actions | `install`, `status`, `uninstall` + `deploy`, `activate`, `rime` |

```bash
noctalia-mod install fcitx5                 # assets + Rime Ice + set as default theme
noctalia-mod action fcitx5 deploy           # assets only, current theme untouched
noctalia-mod action fcitx5 activate         # only switch the active theme
noctalia-mod action fcitx5 rime             # only (re)configure Rime Ice
noctalia-mod status fcitx5
noctalia-mod uninstall fcitx5
```

## What it touches

| Path | Why |
|---|---|
| `~/.local/share/fcitx5/themes/nyxmellow/templates/` | the shipped skin templates (atomic swap) |
| `~/.local/share/fcitx5/rime/default.custom.yaml` | mounts `rime_ice`, keeps the user's other patches |
| `~/.config/fcitx5/profile` | adds `Name=rime` to the input-method list |
| `~/.config/fcitx5/conf/classicui.conf` | `Theme` / `DarkTheme` — only in `activate` |

Everything lives under `$HOME`; this module needs no root and declares no
systemd units.

## Deploy and activate are separate

Deploying assets does not change which theme fcitx5 uses. `install` does both
because that is what "install this skin" means, and `classicui.conf` is listed in
the pre-flight either way. The old values are recorded once in
`$XDG_STATE_HOME/noctalia-mod/fcitx5-nyxmellow-theme.prev`; uninstall restores a
value only if it is still ours, and removes a key that did not exist before.

## Noctalia template registration lives with `noctalia`

The three `theme.templates.user.nyxmellow_*` sections ship inside the `noctalia`
module's configuration, with `requires_path` pointing at the templates this module
deploys. Noctalia skips them while they are absent, so this module never rewrites
another module's file, and uninstalling the skin cannot leave a registration
behind that points at nothing.

## Rime Ice

`rime-ice-git` is an AUR package, so this module needs `paru` or `yay`.
`install`/`rime` writes the `rime_ice` selection into `default.custom.yaml`
(keeping whatever else is in the patch), precompiles with `rime_deployer` when it
and `/usr/share/rime-data` are both present, and adds `Name=rime` to the fcitx5
profile. Uninstall removes only the lines it added and leaves the profile entry
alone — that list belongs to the user, who can drop it in `fcitx5-configtool`.
