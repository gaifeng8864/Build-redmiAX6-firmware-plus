#!/bin/sh
set -eu
umask 077

WORK=/var/run/bypass-preflight
GEN="${TEST_GEN:-/usr/share/bypass/gen_config}"
OUTDIR="$WORK/preflight-v4-output"

mkdir -p "$OUTDIR"
test -s "$GEN"

get() {
    uci -q get "$1" 2>/dev/null || true
}

fail() {
    echo "PREFLIGHT FAILED: $*" >&2
    exit 1
}

node_address() {
    host=$(get "bypass.$1.server")
    [ -n "$host" ] || fail "Node server missing"

    if printf '%s\n' "$host" |
        grep -Eq '^[0-9]{1,3}(\.[0-9]{1,3}){3}$'
    then
        printf '%s\n' "$host"
        return 0
    fi

    resolved=$(nslookup "$host" 2>/dev/null | awk '
        /^[[:space:]]*Name:/ { answer=1; next }
        answer && /^[[:space:]]*Address([[:space:]]+[0-9]+)?:/ {
            ip=$NF
            if (ip ~ /^[0-9.]+$/ && split(ip, a, ".") == 4) {
                print ip
                exit
            }
        }
    ')

    [ -n "$resolved" ] ||
        fail "Cannot resolve IPv4 for node hostname"

    printf '%s\n' "$resolved"
}

check_node() {
    type=$(get "bypass.$1.type")
    [ "$type" = v2ray ] ||
        fail "Unsupported node type: $type"
}

validate_config() {
    mode="$1"
    node="$2"
    port="$3"
    socks="$4"
    addr="$5"

    output="$OUTDIR/$mode.json"
    logfile="$OUTDIR/$mode.log"

    if ! lua "$GEN" "$node" "$mode" \
        "$port" "$socks" "$addr" > "$output"
    then
        fail "$mode generation error"
    fi

    if ! xray run -c "$output" -test \
        > "$logfile" 2>&1
    then
        fail "$mode Xray validation error: $logfile"
    fi

    echo "$mode: PASS"
}

TCP_NODE=$(get 'bypass.@global[0].global_server')
UDP_NODE=$(get 'bypass.@global[0].udp_relay_server')
SO_NODE=$(get 'bypass.socks5_proxy.server')

[ -n "$TCP_NODE" ] || fail "TCP node missing"

[ "$UDP_NODE" = same ] && UDP_NODE="$TCP_NODE"
[ "$SO_NODE" = same ] && SO_NODE="$TCP_NODE"

check_node "$TCP_NODE"

TCP_PORT=$(get "bypass.$TCP_NODE.local_port")
TCP_PORT=${TCP_PORT:-1234}

TCP_ADDR=$(node_address "$TCP_NODE")

if [ "$(get "bypass.$TCP_NODE.kcp_enable")" = 1 ]; then
    fail "KCPTUN TCP preflight not implemented"
fi

SOCKS_PORT=0
if [ "$SO_NODE" = "$TCP_NODE" ]; then
    SOCKS_PORT=$(get 'bypass.socks5_proxy.local_port')
    SOCKS_PORT=${SOCKS_PORT:-1080}
fi

validate_config tcp "$TCP_NODE" \
    "$TCP_PORT" "$SOCKS_PORT" "$TCP_ADDR"

if [ -n "$UDP_NODE" ]; then
    check_node "$UDP_NODE"

    [ "$(get "bypass.$UDP_NODE.kcp_enable")" != 1 ] ||
        fail "UDP node uses unsupported KCPTUN"

    UDP_PORT=$(get "bypass.$UDP_NODE.local_port")
    UDP_PORT=${UDP_PORT:-1234}

    UDP_ADDR=$(node_address "$UDP_NODE")

    validate_config udp "$UDP_NODE" \
        "$UDP_PORT" 0 "$UDP_ADDR"
fi

echo "PREFLIGHT V4 PASSED"
