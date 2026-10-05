# Noctalia Mod

`noctalia-mod` is the configuration manager being extracted out of the existing
Nyxuri engine, targeting CachyOS + niri + Noctalia V5. It is Bash-only and
carries its own modules, tests, and documentation.

This is a work in progress. [PLAN.md](PLAN.md) is the source of truth for what
actually works, what is still missing, and the order the rest gets migrated in.
Do not treat the current tree as feature-complete: the base still has open
defects listed there.

## Setting up a fresh machine

`setup` is the guided path: one checklist covering packages and configuration,
one confirmation, then it runs quietly. It defaults to the core set — `niri` and
`noctalia`, plus everything the shipped configuration actually spawns — because
that is what it takes to reach a desktop.

```bash
noctalia-mod/bin/noctalia-mod setup                  # checklist, then confirm
noctalia-mod/bin/noctalia-mod setup --yes            # no prompts
noctalia-mod/bin/noctalia-mod setup --with fcitx5    # add a declared optional program
```

Optional programs — `fcitx5`, `ddcutil`, `mpvpaper` and friends — show up as
`optional` lines only when this machine lacks them, and only the ones you name
with `--with` get installed. A run ends with a short summary of what was
installed, where the configuration landed, and how to undo it. Re-running
converges: nothing is duplicated and no staging directory is left behind.

The two stages are also usable on their own, and neither needs the other to have
run first. `deps` only touches packages; `install` only touches `~/.config`.
Unlike `setup`, an argument-less `install` means every module:

```bash
# 1. packages
noctalia-mod/bin/noctalia-mod deps                    # show what is missing
noctalia-mod/bin/noctalia-mod deps niri noctalia --yes

# 2. configuration
noctalia-mod/bin/noctalia-mod install niri noctalia   # pre-flight, then confirm
noctalia-mod/bin/noctalia-mod install --yes           # every module, no prompts
```

`deps` verifies an AUR helper exists and primes `sudo` before installing
anything, so the install loop never stops to ask again. Re-running either stage
converges.

Everything else:

```bash
noctalia-mod/bin/noctalia-mod list
noctalia-mod/bin/noctalia-mod check
noctalia-mod/bin/noctalia-mod plan niri noctalia
noctalia-mod/bin/noctalia-mod preset kitty apply transparent --yes
noctalia-mod/bin/noctalia-mod part niri glow apply glow --yes
noctalia-mod/bin/noctalia-mod snapshot "before edit"
noctalia-mod/bin/noctalia-mod rollback
noctalia-mod/bin/noctalia-mod status
noctalia-mod/bin/noctalia-mod uninstall niri --yes
```

Five modules are wired up so far: `niri`, `noctalia`, `kitty`, `fish`, and
`starship`. Module metadata lives in `modules/<id>/module.conf`; default files,
presets, and parts stay inside that module directory.

## Reference check

A module ships the files its configuration actually references, and declares the
programs it spawns. `check` verifies both, statically:

- `~/.config/...` paths referenced in module sources must exist after deployment,
  either because a module provides them or because they are listed in that
  module's `MODULE_EXTERNAL_REFS` (runtime output, or something the user or
  another package provides).
- Programs spawned by module KDL must be declared in
  `MODULE_REQUIRED_COMMANDS` (`command:package`), `MODULE_OPTIONAL_COMMANDS`, or
  `MODULE_EXTERNAL_COMMANDS`. A required program's package must be declared by
  the same module, so `deps <module>` is self-sufficient.

Problems are reported as `unresolved-ref`, `undeclared-command`, or
`unbound-command`. `check` exits non-zero, `install` refuses to deploy, and
`plan` prints the same lines. At runtime, `deps`, `plan`, and `setup`
additionally report `missing-required` / `missing-optional` for programs not on
`PATH`, scoped to the modules you actually asked about; those never block a
deployment, since they describe the machine rather than the repository.
This is what keeps a fresh install from shipping shortcuts that point at files
nobody provides or programs nobody installs.

```bash
noctalia-mod/bin/noctalia-mod check
```

Before a deployment, the command prints the target, preserved paths, missing
dependencies, and reload actions. Directory deployments are staged next to the
target and swapped as a unit, so the swap stays on one filesystem. Paths
containing `__custom__` and module-declared preserve paths are copied into the
staged tree before the swap. Snapshots and the state ledger live under the XDG
state directory. Uninstall restores the pre-install snapshot when it is still
available and never removes system packages.

## Drift and the package ledger

After a successful deploy each module records a fingerprint of the files this
project manages — everything except `__custom__` paths and declared preserve
files. `plan` recomputes it, so editing a managed file directly shows up as
`drift <module> changed`, and a target that disappeared shows as `missing`.
Editing `__custom__` files, or files a module declared as preserve (runtime
state like `niri/monitor.kdl` or the EyeCare symlink), is expected and is not
drift. Drift never blocks a deploy; it just makes sure you are not overwriting
someone else's changes without seeing it.

`deps` and `install` also record which packages they actually installed in
`$XDG_STATE_HOME/noctalia-mod/packages.tsv`. Packages that were already on the
system are not recorded — the ledger answers "what did this project put here",
which is what a future cleanup would need.

## Tests

The suite is plain `unittest` and runs in a temporary `HOME` with fake
`pacman`, `sudo`, `niri`, `noctalia`, and `pkill` on `PATH`. It never touches the
real `~/.config`.

```bash
python3 -m unittest discover -s noctalia-mod/tests -q
```

The suite lives inside this directory and imports nothing from the sibling
Nyxuri engine, so the sub-project can be checked out and tested on its own.
`utils.py` only hands out a temporary `HOME`.
