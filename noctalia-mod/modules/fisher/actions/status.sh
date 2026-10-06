#!/usr/bin/env bash
# shellcheck source-path=SCRIPTDIR
# 查：只读探测。fisher 装好了（账本完整、文件都在）退 0，否则退 1 并说明差在哪。
source "$(dirname -- "${BASH_SOURCE[0]}")/_common.sh"

record=$(fisher_record_path)
failed=0

if fisher_load_ownership "$record"; then
    printf 'ownership\tpresent\t%s\n' "$record"
    missing=()
    for relative in "${FISHER_OWNED_FILES[@]}"; do
        [[ -f $FISHER_DIR/$relative || -L $FISHER_DIR/$relative ]] || missing+=("$relative")
    done
    if ((${#missing[@]})); then
        printf 'files\tmissing\t%s\n' "$(join_by ' ' "${missing[@]}")"
        failed=1
    else
        printf 'files\tpresent\t%s owned\n' "${#FISHER_OWNED_FILES[@]}"
    fi
    if [[ $FISHER_COMPLETE == yes ]]; then
        printf 'install\tcomplete\t%s\n' "$FISHER_DIR"
    else
        printf 'install\tincomplete\tthe previous run did not finish; re-run: noctalia-mod install fisher\n'
        failed=1
    fi
else
    printf 'ownership\tabsent\t%s\n' "$record"
    failed=1
fi

if fisher_lockfile_matches; then
    printf 'lockfile\tmatches\t%s\n' "$FISHER_DIR/fish_plugins"
else
    printf 'lockfile\tdiffers\t%s is not the plugin list this module pins\n' "$FISHER_DIR/fish_plugins"
    failed=1
fi

if command -v fish >/dev/null 2>&1; then
    printf 'fish\tinstalled\t%s\n' "$(command -v fish)"
else
    printf 'fish\tnot-on-path\trun: noctalia-mod deps fisher\n'
fi

exit "$failed"
