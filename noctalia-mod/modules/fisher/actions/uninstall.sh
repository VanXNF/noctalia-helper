#!/usr/bin/env bash
# shellcheck source-path=SCRIPTDIR
# 卸：只删账本里记着的那几个文件，别的（用户自己写的函数、别处装的插件）一个都不碰。
#
# 账本坏了（出现白名单之外的名字）就拒绝执行：那种账本不能当删除清单用。拒绝不是遗忘，
# 账本原样留着，下次还会再报一次（和壁纸账本同一条规矩）。
source "$(dirname -- "${BASH_SOURCE[0]}")/_common.sh"

record=$(fisher_record_path)

if ! fisher_load_ownership "$record"; then
    if [[ -f $record ]]; then
        error "refusing to remove anything: $record does not look like a record this project wrote"
        exit 1
    fi
    warn "no fisher ownership record; nothing was installed by this project, so nothing is removed"
    exit 0
fi

removed=0
for relative in "${FISHER_OWNED_FILES[@]}"; do
    path="$FISHER_DIR/$relative"
    [[ -f $path || -L $path ]] || continue
    rm -f -- "$path" || exit 1
    removed=$((removed + 1))
done
rm -f -- "$record" || exit 1
# 目录是我们建的还是 fisher 建的说不准，所以只在空了的时候收掉——留一个空目录无害，
# 删掉一个用户正要用的目录有害。
rmdir -- "$FISHER_DIR/functions" "$FISHER_DIR/completions" "$FISHER_DIR/conf.d" 2>/dev/null || true
printf 'fisher\tremoved\t%s file(s) from %s\n' "$removed" "$FISHER_DIR"
exit 0
