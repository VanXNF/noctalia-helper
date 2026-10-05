#!/usr/bin/env bash
# ==============================================================================
# Noctalia Mod shell action gateway (shell-action.sh)
# Unified dispatch gateway decoupling desktop shell actions from compositor keybinds.
# ==============================================================================

set -euo pipefail

action="${1:-}"

case "$action" in
    launcher)
        exec noctalia msg panel-toggle launcher
        ;;
    session)
        exec noctalia msg panel-toggle session
        ;;
    settings)
        exec noctalia msg settings-toggle
        ;;
    clipboard)
        exec noctalia msg panel-toggle clipboard
        ;;
    lock)
        exec noctalia msg session lock
        ;;
    wallpaper-random)
        exec noctalia msg wallpaper-random
        ;;
    wallpaper-picker)
        tools_dir="${XDG_CONFIG_HOME:-$HOME/.config}/noctalia/tools"
        if [ -x "$tools_dir/wallpaper-picker.py" ]; then
            exec "$tools_dir/wallpaper-picker.py"
        fi
        exec python3 "$tools_dir/wallpaper-picker.py"
        ;;
    radial-launcher)
        tools_dir="${XDG_CONFIG_HOME:-$HOME/.config}/noctalia/tools"
        if [ -x "$tools_dir/orbit-launcher.py" ]; then
            exec "$tools_dir/orbit-launcher.py"
        fi
        exec python3 "$tools_dir/orbit-launcher.py"
        ;;
    *)
        echo "Unknown shell action: $action" >&2
        echo "Usage: $0 {launcher|session|settings|clipboard|lock|wallpaper-random|wallpaper-picker|radial-launcher}" >&2
        exit 1
        ;;
esac
