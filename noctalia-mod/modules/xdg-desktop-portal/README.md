# xdg-desktop-portal

| | |
|---|---|
| Target | `~/.config/xdg-desktop-portal/` |
| Packages | `xdg-desktop-portal`, `xdg-desktop-portal-gtk`, `xdg-desktop-portal-gnome`, `gnome-keyring` |

Two routing files, identical in content:

- `niri-portals.conf` — used when the session reports `XDG_CURRENT_DESKTOP=niri`
- `portals.conf` — the fallback for everything else

Both say `default=gnome;gtk;`, send Settings, Access, Notification and FileChooser
to those backends, and name `gnome-keyring` for the Secret interface.

## Why the backends are packages of this module

The old engine declared only `xdg-desktop-portal` and left the backends to the
system. That reads as "dependencies are complete" on a machine where the routing
file points at two backends that are not installed — file pickers and screencasts
break while `deps` says nothing is missing. Since the shipped config names those
backends, this module installs them.

The portal binaries live in `/usr/lib` (`/usr/lib/xdg-desktop-portal`,
`/usr/lib/xdg-desktop-portal-gtk`, …) and are D-Bus activated, so they are
**not** declared in `MODULE_REQUIRED_COMMANDS`: `command -v` cannot see them, and
the runtime report would warn forever about programs that are actually there.

`portals.conf` and `niri-portals.conf` carry no reload command. The service picks
the routing up when it next starts; restarting a running session's portals is not
this module's business.
