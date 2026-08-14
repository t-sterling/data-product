#!/usr/bin/env bash
set -euo pipefail

usage() {
    echo "Usage: $0 <base-sha> <target-sha>" >&2
    exit 2
}

[[ $# -eq 2 ]] || usage
BASE=$1
TARGET=$2

git rev-parse --verify "${BASE}^{commit}" >/dev/null 2>&1 || {
    echo "ERROR: base revision '$BASE' is not a commit." >&2
    exit 2
}
git rev-parse --verify "${TARGET}^{commit}" >/dev/null 2>&1 || {
    echo "ERROR: target revision '$TARGET' is not a commit." >&2
    exit 2
}

git diff --name-only "$BASE" "$TARGET" -- data-products/ |
    awk -F/ 'NF >= 3 && $1 == "data-products" && $2 != "" { print $2 }' |
    sort -u
