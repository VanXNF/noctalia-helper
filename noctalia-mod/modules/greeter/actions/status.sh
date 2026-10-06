#!/usr/bin/env bash
# shellcheck source-path=SCRIPTDIR
# 查：只读探测。装好并已接管登录界面退 0，否则退 1 并说明差在哪。
source "$(dirname -- "${BASH_SOURCE[0]}")/_common.sh"

failed=0

if [[ -f $GREETER_CONFIG ]]; then
    if grep -q 'noctalia-greeter-session' "$GREETER_CONFIG"; then
        printf 'config\tusing noctalia-greeter\t%s\n' "$GREETER_CONFIG"
    else
        printf 'config\tpresent but not ours\t%s\n' "$GREETER_CONFIG"
        failed=1
    fi
else
    printf 'config\tmissing\t%s\n' "$GREETER_CONFIG"
    failed=1
fi

if [[ -f $GREETER_POLKIT_RULE ]]; then
    printf 'polkit\tpresent\t%s\n' "$GREETER_POLKIT_RULE"
else
    printf 'polkit\tmissing\t%s\n' "$GREETER_POLKIT_RULE"
    failed=1
fi

if [[ -d $GREETER_STATE_DIR ]]; then
    printf 'state-dir\tpresent\t%s\n' "$GREETER_STATE_DIR"
else
    printf 'state-dir\tmissing\t%s\n' "$GREETER_STATE_DIR"
    failed=1
fi

if command -v systemctl >/dev/null 2>&1; then
    if system_unit_enabled greetd; then
        printf 'greetd\tenabled\tlogin manager\n'
    else
        printf 'greetd\tdisabled\tenable it with: noctalia-mod install greeter\n'
        failed=1
    fi
else
    printf 'greetd\tunknown\tsystemctl is not available\n'
fi

if recorded=$(greeter_recorded_dm); then
    printf 'previous-display-manager\t%s\t%s\n' "$recorded" "$GREETER_DM_RECORD"
elif [[ -e $GREETER_DM_RECORD ]]; then
    printf 'previous-display-manager\tunreadable\t%s\n' "$GREETER_DM_RECORD"
else
    printf 'previous-display-manager\tnone\tnothing to restore on uninstall\n'
fi

if session=$(system_trusted_executable "$(command -v noctalia-greeter-session 2>/dev/null || true)"); then
    printf 'session\t%s\ttrusted\n' "$session"
else
    printf 'session\tmissing or untrusted\trun: noctalia-mod deps greeter\n'
    failed=1
fi

exit "$failed"
