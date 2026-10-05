#!/usr/bin/env bash
# ==============================================================================
# Noctalia Mod session shell gateway (session-shell.sh)
# Launches desktop shell and cleans up leftover compositor session scopes.
# ==============================================================================

set -euo pipefail

systemctl --user stop 'app-niri-noctalia-*.scope' >/dev/null 2>&1 || true

exec noctalia
