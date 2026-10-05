# fish

| | |
|---|---|
| Target | `~/.config/fish/` |
| Packages | `fish` |

## Files

- `config.fish` — interactive shell setup
- `conf.d/local-path.fish` — puts `~/.local/bin` on `PATH`
- `conf.d/__custom__.fish` — user drop-in; also sources every `*.fish` under
  `~/.config/fish/__custom__/`, which the module does not create
- `completions/noctalia-mod.fish` — completion for this CLI
- `fish_plugins` — the pinned plugin list read by `fisher`

## External reference

`fish/__custom__` is declared in `MODULE_EXTERNAL_REFS`: the drop-in scans that
user-owned directory, so the path is referenced but deliberately not shipped.

## Deliberately not here

The previous engine shipped aliases, helper functions and a state-bridging
`nyxuri-path.fish` under this target. None of it was migrated — the sub-project
does not read the old state and does not keep compatibility names.
