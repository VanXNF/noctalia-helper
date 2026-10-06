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

## Runtime writers

Noctalia's built-in kitty template has a `post_hook` that rewrites two of these files in
place: it deletes the `# BEGIN_KITTY_THEME … # END_KITTY_THEME` block from `kitty.conf`
(the `include current-theme.conf` line lives in that block), appends
`include themes/noctalia.conf` instead, and rewrites `themes/noctalia.conf` with the
current palette.

Both are declared in `MODULE_RUNTIME_WRITES`, so they are still overwritten on every
deploy but do not count as drift (PLAN §1, §10 P1-9). Declaring them as `MODULE_PRESERVE`
instead would have been wrong: preserve copies the live version back into the staged tree,
so the module could never update them again.

One consequence is worth knowing: after Noctalia has run once, `current-theme.conf` is no
longer included by `kitty.conf`, so the symlink sits unused until the next deploy restores
the block.
