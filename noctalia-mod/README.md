# Noctalia Mod

`noctalia-mod` is a standalone first-stage Bash configuration manager for the
CachyOS + niri + Noctalia V5 setup.

```bash
noctalia-mod/bin/noctalia-mod list
noctalia-mod/bin/noctalia-mod plan niri noctalia
noctalia-mod/bin/noctalia-mod install niri noctalia --yes
noctalia-mod/bin/noctalia-mod snapshot
noctalia-mod/bin/noctalia-mod rollback
```

The first stage owns five modules: `niri`, `noctalia`, `kitty`, `fish`, and
`starship`. Module metadata is kept in `modules/<id>/module.conf`; default
files, presets, and parts stay inside that module directory.

Before a deployment, the command prints the target and preserved paths. Directory
deployments are staged and swapped as a unit. Paths containing `__custom__` and
module-declared preserve paths are copied into the staged tree before the swap.
Snapshots and the state ledger live under the XDG state directory. Uninstall
restores the pre-install snapshot when available and never removes system
packages.

For an isolated smoke run, provide fake `pacman`, `sudo`, `niri`, `noctalia`,
and `pkill` commands earlier in `PATH`, then set `HOME` and the XDG directories
to a temporary tree. The repository test suite does this automatically.
