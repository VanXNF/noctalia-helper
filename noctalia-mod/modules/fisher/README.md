# fisher

Installs the pinned fish plugins (fisher itself, `autopair.fish`, `fzf.fish`) and
remembers exactly which files it wrote.

| | |
|---|---|
| Kind | system module — `actions/*.sh`, no target tree |
| Packages | `fish`, `curl` |
| Actions | `install`, `status`, `uninstall` |

```bash
noctalia-mod install fisher
noctalia-mod status fisher
noctalia-mod uninstall fisher
```

## Pinned, verified, and scoped

The bootstrap script is fetched at a fixed commit from `jorgebucaran/fisher`,
checked against a sha256, and falls back through two mirrors
(`raw.githubusercontent` → jsDelivr → gh-proxy). Verification is not optional: a
download that does not match is discarded and the next mirror is tried.

Nothing is installed unless `~/.config/fish/fish_plugins` — deployed by the `fish`
module — is exactly the plugin list this module pins. A user who edits that
lockfile gets a refusal, not an overwrite. And a `functions/fisher.fish` that
exists without an ownership record means somebody else's fisher: this module
refuses to take it over.

Plugins install with `fisher_path` pointed at `~/.config/fish` and
`XDG_CONFIG_HOME` pointed at a throwaway directory, so fisher's own bookkeeping
does not land in the user's configuration.

## Ownership record

`$XDG_STATE_HOME/noctalia-mod/fisher.owned`:

```text
complete<TAB>0|1
functions/fisher.fish
conf/fzf.fish
...
```

It is written by the action itself, not by the engine: when an install fails
halfway, the files already on disk are still ours, and a retry has to know about
them. `complete` stays `0` until the plugin run succeeds. Uninstall removes only
paths from that list, and only if they are also in the module's managed-file
whitelist — a tampered record is refused rather than used as a delete list.

## What the `fish` module preserves for this

`~/.config/fish` is a target tree, so a `fish` deploy swaps the whole directory.
The `fish` module therefore preserves `functions/` plus the four plugin files it
does not ship (`conf.d/autopair.fish`, `conf.d/fzf.fish`,
`completions/fisher.fish`, `completions/fzf_configure_bindings.fish`) and declares
`fish_plugins` as a runtime write. Without that, installing `fish` again would
delete the plugins this module installed.
