#!/usr/bin/env bash
set -euo pipefail

[[ $# -eq 3 ]] || { echo "Usage: $0 <base-sha> <target-sha> <deployment-repo>" >&2; exit 2; }
BASE=$1
TARGET=$2
DEPLOYMENT_REPO=$3
SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
failures=0

mapfile -t PRODUCTS < <(bash "$SCRIPT_DIR/changed-products.sh" "$BASE" "$TARGET")
for product in "${PRODUCTS[@]}"; do
    manifest="$DEPLOYMENT_REPO/environments/dev/products/$product.yml"
    if [[ ! -f $manifest ]]; then
        echo "ERROR: '$product' has no DEV-tested candidate manifest." >&2
        failures=$((failures + 1))
        continue
    fi
    status=$(sed -n 's/^  releaseStatus:[[:space:]]*//p' "$manifest")
    tested_digest=$(sed -n 's/^    contentSha256:[[:space:]]*//p' "$manifest")
    target_digest=$(git ls-tree -r "${TARGET}^{commit}" -- "data-products/$product" | sha256sum | awk '{ print $1 }')
    if [[ $status != candidate ]]; then
        echo "ERROR: DEV desired state for '$product' is not a candidate." >&2
        failures=$((failures + 1))
    elif [[ $tested_digest != "$target_digest" ]]; then
        echo "ERROR: merged content for '$product' does not match the candidate deployed to DEV." >&2
        echo "  DEV candidate: $tested_digest" >&2
        echo "  merged source: $target_digest" >&2
        failures=$((failures + 1))
    else
        echo "OK: '$product' matches its DEV-tested candidate."
    fi
done
(( failures == 0 ))
