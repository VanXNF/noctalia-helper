# fastfetch

| | |
|---|---|
| Target | `~/.config/fastfetch/` |
| Packages | `fastfetch` |
| Required | `fastfetch` |

A single file, `config.jsonc`, read by the `fastfetch` binary. The config spawns
nothing and references no other `~/.config` path, so the module has no
`MODULE_EXTERNAL_REFS` and no parts or presets.

`fastfetch` is declared as a required program even though no shipped config
spawns it: the file is only meaningful with the binary present, and declaring it
is what makes `deps fastfetch` self-sufficient instead of reporting "nothing to
install" over a config nobody can read.

## Migration note

The `rice` line used to print `Nyxuri`, the old project's name. It now prints
`Noctalia Mod`, following the same rename applied to every other migrated file.
Change it back in `files/config.jsonc` if that label should stay yours.
