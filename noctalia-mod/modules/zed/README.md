# zed

| | |
|---|---|
| Target | `~/.config/zed/` |
| Packages | `zed` |
| Required | `zed` |

`settings.json` (editor preferences, fonts, panel layout) and `keymap.json`. No
preserve entries, no parts, no presets: nothing writes back into the deployed
tree at runtime.

The editor is named `zed` everywhere — package, binary, config directory — so the
module has no exceptions to declare beyond the two files it validates.

## Optional in the old engine, a normal module here

The old engine also listed Zed in `configs/.optional-apps.toml`, which put it in
the software menu and in the PKGBUILD's `optdepends`: the config deployed, the
package did not. The new project has no "optional software" axis — a module
either declares its packages or it does not — so `zed` is declared and
`deps zed` installs the editor.

Consequence worth knowing: `deps --yes` / `install --yes` (every module) will
install Zed. The guided `setup` path does not, because its default set is only
`niri` and `noctalia`.
