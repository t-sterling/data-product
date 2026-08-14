#!/usr/bin/env bash
set -euo pipefail

[[ $# -eq 2 ]] || { echo "Usage: $0 <base-sha> <target-sha>" >&2; exit 2; }
BASE=$1
TARGET=$2
SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
REPO_ROOT=$(git rev-parse --show-toplevel)

mapfile -t PRODUCTS < <("$SCRIPT_DIR/changed-products.sh" "$BASE" "$TARGET")
"$SCRIPT_DIR/validate-product-versions.sh" "$BASE" "$TARGET"

if [[ ${#PRODUCTS[@]} -eq 0 ]]; then
    echo "No changed data-products; nothing to build."
    exit 0
fi

declare -a MODULES=()
declare -a VERSIONS=()
printf '\nChanged data-products:\n\n'
for product in "${PRODUCTS[@]}"; do
    old_version=$(git show "$BASE:data-products/$product/product.yml" | sed -n 's/^version:[[:space:]]*//p')
    new_version=$(git show "$TARGET:data-products/$product/product.yml" | sed -n 's/^version:[[:space:]]*//p')
    printf '  %-12s %s -> %s\n' "$product" "$old_version" "$new_version"
    MODULES+=("data-products/$product")
    VERSIONS+=("$new_version")
done

printf '\nBuilding:\n'
printf '  %s\n' "${MODULES[@]}"
module_list=$(IFS=,; echo "${MODULES[*]}")
(cd "$REPO_ROOT" && mvn -pl "$module_list" -am clean verify)

printf '\nWould publish:\n'
for index in "${!PRODUCTS[@]}"; do
    printf '  %s:%s\n' "${PRODUCTS[$index]}" "${VERSIONS[$index]}"
done
