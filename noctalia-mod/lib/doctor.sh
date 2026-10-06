# shellcheck shell=bash
# 体检与诊断导出（PLAN §11 阶段 E）。
#
# 输出是 TSV：<ok|warn|fail|info>\t<领域>\t<说明>。不用 ✓/!/✗ 图标——状态语义由第一列的
# 文本表达，图标留给终端，输出才能被 grep 和脚本直接吃。
#
# 与 `check` 的分工：`check` 判"仓库本身有没有缺陷"（悬空引用、没人声明的程序），那会
# 拦住部署；doctor 判"这台机器现在是什么状态"，缺失只报出来。两者不能混：机器状态不是
# 仓库缺陷，仓库缺陷也不是体检能修的。
#
# 退出码：有 fail 就是 1，否则 0。fail 只留给真正的坏消息（装着的模块目标没了、状态目录
# 不可写、仓库有缺陷），"没装这个程序"一律是 warn——目标机器之外的机器也能跑体检。

doctor_line() {
    printf '%s\t%s\t%s\n' "$1" "$2" "$3"
}

# 每个检查自己打行、不返回值；列表顺序就是输出顺序。
# 加一项 = 写一个 doctor_check_* 函数 + 在这里加一行。
DOCTOR_CHECKS=(
    doctor_check_environment
    doctor_check_repository
    doctor_check_modules
    doctor_check_permissions
    doctor_check_commands
    doctor_check_state
    doctor_check_theme
    doctor_check_wallpapers
    doctor_check_tools
    doctor_check_disk
)

doctor_check_environment() {
    local program desktop
    local -a missing=()
    if [[ -f ${NOCTALIA_MOD_CACHYOS_MARKER:-/etc/cachyos-release} ]]; then
        doctor_line ok environment 'CachyOS marker found'
    else
        doctor_line warn environment 'CachyOS marker not found; this project targets CachyOS'
    fi
    for program in niri noctalia; do
        if ! command -v "$program" >/dev/null 2>&1; then
            missing+=("$program")
        fi
    done
    if ((${#missing[@]})); then
        doctor_line warn environment "not on PATH: $(join_by ' ' "${missing[@]}")"
    else
        doctor_line ok environment 'niri and noctalia are on PATH'
    fi
    desktop=${XDG_CURRENT_DESKTOP-}
    if [[ ${desktop,,} == *niri* ]]; then
        doctor_line ok session "desktop session: $desktop"
    else
        doctor_line warn session "not inside a niri session (XDG_CURRENT_DESKTOP=${desktop:-unset})"
    fi
    return 0
}

# 静态自洽走的是 check 那三个函数，判据只有一处，不在这里重复实现。
doctor_check_repository() {
    local unresolved undeclared unbound item
    unresolved=$(reference_check_unresolved) || true
    undeclared=$(command_check_undeclared) || true
    unbound=$(command_check_unbound) || true
    if [[ -z $unresolved && -z $undeclared && -z $unbound ]]; then
        doctor_line ok repository 'every reference and program declaration resolves'
        return 0
    fi
    while IFS= read -r item; do
        [[ -n $item ]] && doctor_line fail repository "unresolved-ref: $item"
    done <<< "$unresolved"
    while IFS= read -r item; do
        [[ -n $item ]] && doctor_line fail repository "undeclared-command: $item"
    done <<< "$undeclared"
    while IFS= read -r item; do
        [[ -n $item ]] && doctor_line fail repository "unbound-command: $item"
    done <<< "$unbound"
    return 0
}

doctor_check_modules() {
    local id target recorded relative preset mode
    local -a enabled=()
    mapfile -t enabled < <(state_enabled_modules)
    if ((${#enabled[@]} == 0)); then
        doctor_line info modules 'nothing is deployed yet'
        return 0
    fi
    for id in "${enabled[@]}"; do
        if ! module_load "$id"; then
            doctor_line fail modules "$id: the module no longer loads"
            continue
        fi
        target=$(safe_target_path "$MODULE_TARGET") || {
            doctor_line fail modules "$id: unsafe target"
            continue
        }
        if [[ ! -e $target && ! -L $target ]]; then
            doctor_line fail modules "$id: target $target is missing"
            continue
        fi
        recorded=$(module_state_get "$id" fingerprint 2>/dev/null || true)
        if [[ -n $recorded && $(module_fingerprint "$target") != "$recorded" ]]; then
            doctor_line warn modules "$id: managed files changed since the last deploy"
        else
            doctor_line ok modules "$id: $target"
        fi
        for relative in "${MODULE_VALIDATE_PATHS[@]}"; do
            [[ -e $target/$relative || -L $target/$relative ]] ||
                doctor_line fail modules "$id: $relative is missing after the deploy"
        done
        preset=$(module_state_get "$id" preset 2>/dev/null || true)
        if [[ -n $preset ]]; then
            mode=$(preset_deploy_mode "$id")
            [[ $mode == ok ]] || doctor_line warn modules "$id: preset '$preset' is $mode"
        fi
    done
    return 0
}

doctor_check_permissions() {
    local id target pattern path checked=0
    local -a enabled=()
    mapfile -t enabled < <(state_enabled_modules)
    shopt -s nullglob
    for id in "${enabled[@]}"; do
        module_load "$id" || continue
        target=$(safe_target_path "$MODULE_TARGET") || continue
        for pattern in "${MODULE_CHMOD[@]}"; do
            for path in "$target"/$pattern; do
                checked=$((checked + 1))
                [[ -x $path ]] || doctor_line warn permissions "$id: $path lacks its executable bit"
            done
        done
    done
    shopt -u nullglob
    if ((checked == 0)); then
        doctor_line info permissions 'no declared executable path is present'
    else
        doctor_line ok permissions "$checked declared path(s) checked"
    fi
    return 0
}

doctor_check_commands() {
    local module program package kind
    local -a enabled=() missing_required=() missing_optional=()
    mapfile -t enabled < <(state_enabled_modules)
    if ((${#enabled[@]} == 0)); then
        doctor_line info commands 'nothing is deployed yet'
        return 0
    fi
    while IFS=$'\t' read -r module program package kind; do
        if [[ $kind == required ]]; then
            missing_required+=("$program ($package, $module)")
        else
            missing_optional+=("$program")
        fi
    done < <(runtime_command_report "${enabled[@]}")
    if ((${#missing_required[@]})); then
        doctor_line warn commands "missing required: $(join_by ', ' "${missing_required[@]}")"
    else
        doctor_line ok commands 'every required program of the deployed modules is on PATH'
    fi
    ((${#missing_optional[@]})) &&
        doctor_line info commands "missing optional: $(join_by ' ' "${missing_optional[@]}")"
    return 0
}

doctor_check_state() {
    local root audit snapshots residue
    root=$(state_root)
    if [[ -d $root && -w $root ]]; then
        doctor_line ok state "$root is writable"
    else
        doctor_line fail state "$root is missing or not writable"
    fi
    audit="$root/audit.log"
    if [[ -f $audit ]]; then
        doctor_line info state "audit log: $(wc -l < "$audit" | tr -d ' ') entries"
    else
        doctor_line info state 'no audit log yet'
    fi
    snapshots=$(snapshot_list | wc -l | tr -d ' ')
    doctor_line info state "snapshots kept: $snapshots (limit $NOCTALIA_MOD_SNAPSHOT_LIMIT normal ones)"
    mapfile -t residue < <(clean_staging_paths)
    if ((${#residue[@]})); then
        doctor_line warn state "${#residue[@]} leftover staging path(s); run: noctalia-mod clean"
    fi
    return 0
}

doctor_check_theme() {
    local report mode expected actual
    report=$(theme_status)
    mode=$(printf '%s\n' "$report" | awk -F '\t' '$1 == "mode" {print $2}')
    expected=$(printf '%s\n' "$report" | awk -F '\t' '$1 == "expected-gtk-theme" {print $2}')
    actual=$(printf '%s\n' "$report" | awk -F '\t' '$1 == "gtk-theme" {print $2}')
    doctor_line info theme "current mode: ${mode:-unknown}"
    if [[ -z $actual || $actual == unknown ]]; then
        doctor_line warn theme 'gsettings is unavailable, so GTK apps cannot follow the mode'
    elif [[ $actual != "$expected" ]]; then
        doctor_line warn theme "gsettings gtk-theme is $actual, expected $expected for this mode"
    else
        doctor_line ok theme "gsettings gtk-theme is $actual"
    fi
    return 0
}

doctor_check_wallpapers() {
    local -a entries=()
    local dir
    dir=$(wallpaper_dir)
    if [[ -d $dir ]]; then
        doctor_line ok wallpapers "$dir"
    else
        doctor_line warn wallpapers "$dir is missing; setup deploys the offline pack"
        return 0
    fi
    mapfile -t entries < <(wallpaper_managed_entries)
    doctor_line info wallpapers "managed by this project: ${#entries[@]}"
    return 0
}

# 随包发布的 Python 工具（Orbit、壁纸选择器）的 import 与模块包清单之间没有自动校验
# （PLAN §3 已知边界）。这里就是那条校验：真去 import 一次。
doctor_check_tools() {
    if ! command -v python3 >/dev/null 2>&1; then
        doctor_line info tools 'python3 is not on PATH'
        return 0
    fi
    if timeout 20 python3 -c '
import gi
import cairo
gi.require_version("Gtk", "3.0")
gi.require_version("GtkLayerShell", "0.1")
' >/dev/null 2>&1; then
        doctor_line ok tools 'the shipped Python tools can import gi, cairo and GtkLayerShell'
    else
        doctor_line warn tools 'missing python-gobject, gtk-layer-shell or python-cairo'
    fi
    return 0
}

doctor_human_kib() {
    local value=$1
    if ((value >= 1048576)); then
        printf '%s GiB\n' "$((value / 1048576))"
    elif ((value >= 1024)); then
        printf '%s MiB\n' "$((value / 1024))"
    else
        printf '%s KiB\n' "$value"
    fi
}

doctor_check_disk() {
    local available
    available=$(df -Pk "$(home_dir)" 2>/dev/null | awk 'NR == 2 {print $4}') || available=''
    [[ $available =~ ^[0-9]+$ ]] || return 0
    if ((available < 10 * 1024 * 1024)); then
        doctor_line warn disk "\$HOME has only $(doctor_human_kib "$available") free"
    else
        doctor_line ok disk "\$HOME has $(doctor_human_kib "$available") free"
    fi
    return 0
}

# 逐项跑一遍，只打行、不做判定：doctor 与 bug 报告用的是同一份输出。
doctor_lines() {
    local check
    for check in "${DOCTOR_CHECKS[@]}"; do
        "$check" || doctor_line fail internal "$check did not finish"
    done
    return 0
}

doctor_run() {
    local line status ok=0 warn=0 fail=0 info=0
    printf 'Noctalia Mod doctor\n'
    printf 'status\tarea\tdetail\n'
    while IFS= read -r line; do
        printf '%s\n' "$line"
        status=${line%%$'\t'*}
        case $status in
            ok) ok=$((ok + 1)) ;;
            warn) warn=$((warn + 1)) ;;
            fail) fail=$((fail + 1)) ;;
            info) info=$((info + 1)) ;;
        esac
    done < <(doctor_lines)
    printf 'summary\t%s ok, %s warn, %s fail, %s info\n' "$ok" "$warn" "$fail" "$info"
    ((fail == 0)) || return 1
    return 0
}

# 诊断导出：把体检、账本、审计尾部收进一份 Markdown，方便贴给别人看。
# 只读本项目自己的状态与几个基础命令，不收集系统日志——那不是这个项目的领地。
bug_report_path() {
    printf '%s/bug-report-%s.md\n' "$(state_root)" "$(date -u +%Y%m%dT%H%M%SZ)"
}

# Markdown 的代码围栏是三个反引号，写在单引号里就是字面量——这里要的正是字面量，
# 所以关掉"单引号里不会展开"的提示。
# shellcheck disable=SC2016
bug_report_write() {
    local path root id preset target
    root=$(state_root)
    mkdir -p "$root" || return 1
    path=$(bug_report_path)
    {
        printf '# Noctalia Mod diagnostic report\n\n'
        printf -- '- generated: %s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
        printf -- '- version: %s\n' "$(state_project_version)"
        printf -- '- project root: %s\n' "$(project_root)"
        printf -- '- config root: %s\n' "$(config_root)"
        printf -- '- state root: %s\n' "$root"
        printf -- '- host: %s, kernel %s, %s\n' \
            "$(doctor_os_name)" "$(uname -r)" "$(uname -m)"
        printf -- '- session: %s / %s\n' \
            "${XDG_CURRENT_DESKTOP:-unset}" "${XDG_SESSION_TYPE:-unset}"
        printf '\n## Deployed modules\n\n```text\n'
        while IFS= read -r id; do
            module_load "$id" || continue
            preset=$(module_state_get "$id" preset 2>/dev/null || printf '%s' "$MODULE_PRESET_DEFAULT")
            target=$(safe_target_path "$MODULE_TARGET") || target='(unsafe target)'
            printf '%s\t%s\t%s\n' "$id" "$preset" "$target"
        done < <(state_enabled_modules)
        printf '```\n\n## Packages this project installed\n\n```text\n'
        state_installed_packages
        printf '```\n\n## Doctor\n\n```text\n'
        doctor_lines
        printf '```\n\n## Snapshots\n\n```text\n'
        snapshot_list
        printf '```\n\n## Audit log (last 20)\n\n```text\n'
        if [[ -f $root/audit.log ]]; then
            tail -n 20 -- "$root/audit.log"
        else
            printf 'no audit log yet\n'
        fi
        printf '```\n'
    } > "$path" || return 1
    printf '%s\n' "$path"
    return 0
}

doctor_os_name() {
    local line
    if [[ -r /etc/os-release ]]; then
        while IFS= read -r line; do
            [[ $line == PRETTY_NAME=* ]] || continue
            line=${line#PRETTY_NAME=}
            printf '%s\n' "${line//\"/}"
            return 0
        done < /etc/os-release
    fi
    printf 'Linux\n'
    return 0
}
