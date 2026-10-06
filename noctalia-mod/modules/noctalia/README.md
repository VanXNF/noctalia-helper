# noctalia

Noctalia V5 configuration, the theme templates it renders from, and the two
companion tools its configuration points at.

| | |
|---|---|
| Target | `~/.config/noctalia/` |
| Packages | `noctalia`, `python`, `python-gobject`, `python-cairo`, `gtk-layer-shell` |
| chmod | `tools/*.py`, `wallpaper-hook.sh` |

## What ships and why

Everything here is referenced by the deployed configuration, so it travels with
the module:

- `noctalia-config.toml` — paths under `/home/user` are placeholders the deploy
  rewrites to the real `$HOME`
- `templates/` — inputs for Noctalia's own template renderer; this project
  deploys the sources and never renders them itself
- `tools/orbit-launcher.py` + `tools/orbit/` — Orbit launcher, reached from
  `Mod+A` through niri's `shell-action.sh`
- `tools/wallpaper-picker.py` + `tools/wallpaper_picker/` — wallpaper picker,
  reached from `Mod+W`
- `wallpaper-hook.sh` — registered as the `wallpaper_changed` hook
- `mpv-hook.lua` — referenced from the mpvpaper plugin settings

`python-cairo` is a real dependency of `tools/orbit/renderer.py` (`import cairo`);
`python-gobject` does not pull it in.

## Optional programs

Both are declared in `MODULE_OPTIONAL_COMMANDS` and guarded by `command -v`.
They only matter for live video wallpapers, so they stay opt-in:

```bash
noctalia-mod setup --with ffmpeg --with mpvpaper
```

| Program | What it carries |
|---|---|
| `ffmpeg` | the video thumbnail `wallpaper-hook.sh` and the picker show |
| `mpvpaper` | the plugin `noctalia-config.toml` enables to play those wallpapers |

## Wallpaper paths and GTK theming

`[wallpaper] directory` / `video_directory` are written with the `@XDG_PICTURES@`
placeholder, which the deploy engine resolves to the real XDG Pictures directory (PLAN §4).
The old engine rewrote those two lines after deploying; a placeholder keeps the engine from
having to know which key of which module needs fixing, and keeps a Chinese-locale path out
of the repository.

Two things this module deliberately does **not** do:

- **Render** the files under `templates/`. Noctalia's own TemplateEngine reads them through
  the `[theme.templates.user.*]` registrations in `noctalia-config.toml` and writes
  `gtk-{3,4}.0/gtk.css`, `niri/colors.kdl` and the palette. This project only ships the
  sources.
- **Sync GTK dark/light state.** `theme sync` (engine-level, PLAN §10 P1-8) writes
  `gtk-{3,4}.0/settings.ini` and `gsettings … gtk-theme`; Noctalia only sets
  `color-scheme`.

## Referenced but not provided

Listed in `MODULE_EXTERNAL_REFS` so `check` stays honest:

| Path | Who provides it |
|---|---|
| `gtk-3.0/gtk.css`, `gtk-4.0/gtk.css` | Noctalia renders them at runtime |
| `noctalia/tools/orbit-items.toml` | optional user override; the module ships the `__custom__` default |
| `niri/scratchpad-items*` | optional user overrides; Orbit falls back to its built-in menu tree |
| `user-dirs.dirs`, `Wallpapers` | `xdg-user-dirs` and the user |

## Runtime state

`wallpaper-hook.sh` keeps its thumbnail in `$XDG_RUNTIME_DIR`; the tools read the
Material You palette from `~/.cache/noctalia-mod/palette.toml`, which is where
`noctalia-config.toml` tells Noctalia to render it.

This module declares neither `MODULE_PRESERVE` nor `MODULE_RUNTIME_WRITES`: everything
Noctalia writes back at runtime (`gtk-{3,4}.0/gtk.css`, `niri/colors.kdl`, the palette)
lands outside `~/.config/noctalia/`, so nothing inside its own target is rewritten. The
wallpaper directory is outside `~/.config` entirely and is handled by the engine
(`wallpapers deploy`, PLAN §4).
