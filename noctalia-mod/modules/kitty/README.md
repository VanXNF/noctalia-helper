# kitty

| | |
|---|---|
| Target | `~/.config/kitty/` |
| Packages | `kitty` |
| Reload | `pkill -SIGUSR1 -x kitty` |

## Files

- `kitty.conf` — the base configuration; `include current-theme.conf` at the top
- `current-theme.conf` — a symlink to `themes/noctalia.conf`, shipped as a link so
  the theme can be swapped without rewriting `kitty.conf`
- `themes/noctalia.conf` — the colour scheme
- `__custom__.conf` — user overrides, included by `kitty.conf`, never overwritten

## Preset

`transparent` is a sparse overlay: it ships only the files that differ from the
base, and everything else is inherited from `files/`.

```bash
noctalia-mod preset kitty apply transparent --yes
noctalia-mod preset kitty apply default --yes
```

The reload signal is sent after a successful deploy; if kitty is not running the
`pkill` result is ignored on purpose.
