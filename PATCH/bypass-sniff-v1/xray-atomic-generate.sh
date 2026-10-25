#!/bin/sh
set -eu
umask 077

[ "$#" -eq 7 ] || exit 2
GEN=$1
TARGET=$2
shift 2

[ -f "$GEN" ] || exit 1
[ -d "${TARGET%/*}" ] || exit 1
[ ! -L "$TARGET" ] || exit 1

TMP=$(mktemp "${TARGET}.new.XXXXXX") || exit 1
LOG="${TMP}.log"
trap 'rm -f "$TMP" "$LOG"' 0

if ! lua "$GEN" "$@" > "$TMP"; then
    echo "FAIL: Lua generation" >&2
    exit 1
fi


if ! xray run -format json -c "$TMP" -test > "$LOG" 2>&1; then
    echo "FAIL: Xray validation" >&2
    sed -n '1,6p' "$LOG" >&2
    exit 1
fi

if ! mv -f "$TMP" "$TARGET"; then
    echo "FAIL: Atomic replacement" >&2
    exit 1
fi

echo "PASS: Validated JSON installed"
