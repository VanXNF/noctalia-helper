# A non-blocking project lock prevents concurrent state writes and swaps.

with_project_lock() {
    local lock_file fd rc
    lock_file="$(state_root)/lock"
    mkdir -p "$(state_root)"
    if ! command -v flock >/dev/null 2>&1; then
        error 'flock is required to protect noctalia-mod state'
        return 1
    fi
    exec {fd}>"$lock_file"
    if ! flock -n "$fd"; then
        error 'another noctalia-mod operation is already running'
        return 1
    fi
    "$@"
    rc=$?
    flock -u "$fd" || true
    return "$rc"
}
