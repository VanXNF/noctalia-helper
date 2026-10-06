# starship

| | |
|---|---|
| Target | `~/.config/starship.toml` |
| Packages | `starship` |

A single-file target, so this module exercises the narrowest deploy path: no
directory staging, and therefore no `MODULE_PRESERVE` entries and no
`__custom__` inheritance. The whole file is replaced on every deploy.

Two consequences are deliberate:

- `/home/user` placeholders are **not** substituted for single-file targets; the
  rewrite runs over staged directories only. `/home/user` is not used in
  `starship.toml`.
- `MODULE_VALIDATE_PATHS` is empty, because validation paths are resolved
  relative to the target and a file target has no children to check.

Noctalia's starship template injects a `# >>> NOCTALIA STARSHIP PALETTE >>>` block into
this same file, so `MODULE_RUNTIME_WRITES=(starship.toml)` declares it as runtime-written:
the module still owns and overwrites the file, the fingerprint just ignores it. A file
target has no child paths, which is why the declaration names the file itself (PLAN §1).
