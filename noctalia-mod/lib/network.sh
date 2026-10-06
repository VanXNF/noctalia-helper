# shellcheck shell=bash
# 受校验的下载（PLAN §11 阶段 F）。
#
# 这个项目只有一条路径会碰网络：fisher 的引导脚本。它按固定 commit 取、按 sha256 校验，
# 多个镜像依次回退——旧引擎同样这么做（raw.githubusercontent → jsDelivr → gh-proxy）。
# 每个 curl 调用都带显式超时：没有超时的网络调用会让一条命令永远挂着（AGENTS 铁律）。
#
# 校验不过就换下一个镜像，全都不行才算失败。**不做**"下不来就跳过校验"的降级：
# 从网上取一段会被 fish source 的代码，校验是这个功能唯一的信任来源。

# 镜像列表按可靠性排：官方 raw 最快、jsDelivr 在墙内更稳、gh-proxy 是最后的退路。
net_mirrors_for_raw() {
    local repo=$1 commit=$2 path=$3
    printf '%s\n' \
        "https://raw.githubusercontent.com/$repo/$commit/$path" \
        "https://fastly.jsdelivr.net/gh/$repo@$commit/$path" \
        "https://gh-proxy.org/https://raw.githubusercontent.com/$repo/$commit/$path"
}

# 下载并校验；成功后 destination 就是那份内容，失败时文件不会留下。
net_fetch_verified() {
    local destination=$1 expected=$2
    shift 2
    local url temp digest
    (($#)) || {
        error 'no mirror was given'
        return 1
    }
    command -v curl >/dev/null 2>&1 || {
        error 'curl is required to download files'
        return 1
    }
    command -v sha256sum >/dev/null 2>&1 || {
        error 'sha256sum is required to verify downloads'
        return 1
    }
    [[ $expected =~ ^[0-9a-f]{64}$ ]] || {
        error "invalid checksum: $expected"
        return 1
    }
    temp=$(mktemp) || return 1
    for url in "$@"; do
        if ! curl -sfL --connect-timeout 5 --max-time 60 -o "$temp" -- "$url"; then
            warn "download failed: $url"
            continue
        fi
        digest=$(sha256sum "$temp" | cut -d' ' -f1)
        if [[ $digest != "$expected" ]]; then
            warn "checksum mismatch: $url"
            continue
        fi
        mv -f -- "$temp" "$destination"
        return 0
    done
    rm -f -- "$temp"
    error 'could not download a verified copy from any mirror'
    return 1
}
