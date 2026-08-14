#!/usr/bin/env bash
set -uo pipefail

usage() {
    echo "Usage: $0 <base-sha> <target-sha>" >&2
    exit 2
}

[[ $# -eq 2 ]] || usage
BASE=$1
TARGET=$2
SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
SEMVER_REGEX='^[0-9]+\.[0-9]+\.[0-9]+$'

git rev-parse --verify "${BASE}^{commit}" >/dev/null 2>&1 || {
    echo "ERROR: base revision '$BASE' is not a commit." >&2
    exit 2
}
git rev-parse --verify "${TARGET}^{commit}" >/dev/null 2>&1 || {
    echo "ERROR: target revision '$TARGET' is not a commit." >&2
    exit 2
}

extract_version() {
    sed -n 's/^version:[[:space:]]*//p'
}

read_version() {
    local revision=$1 product=$2 content versions count
    content=$(git show "$revision:data-products/$product/product.yml" 2>/dev/null) || return 10
    versions=$(printf '%s\n' "$content" | extract_version)
    count=$(printf '%s\n' "$versions" | awk 'NF { count++ } END { print count+0 }')
    [[ $count -eq 1 ]] || return $((20 + count))
    printf '%s\n' "$versions"
}

is_greater() {
    local new=$1 old=$2 new_major new_minor new_patch old_major old_minor old_patch
    IFS='.' read -r new_major new_minor new_patch <<< "$new"
    IFS='.' read -r old_major old_minor old_patch <<< "$old"
    (( 10#$new_major > 10#$old_major )) && return 0
    (( 10#$new_major < 10#$old_major )) && return 1
    (( 10#$new_minor > 10#$old_minor )) && return 0
    (( 10#$new_minor < 10#$old_minor )) && return 1
    (( 10#$new_patch > 10#$old_patch ))
}

invalid_structure() {
    local product=$1 revision_label=$2 detail=$3
    printf "ERROR: invalid product.yml for '%s' at %s\n\n%s\n\n" "$product" "$revision_label" "$detail" >&2
    printf '%s\n' "Expected exactly one top-level line:" "  version: MAJOR.MINOR.PATCH" >&2
}

failures=0
mapfile -t PRODUCTS < <(bash "$SCRIPT_DIR/changed-products.sh" "$BASE" "$TARGET") || exit $?

for product in "${PRODUCTS[@]}"; do
    old_version=$(read_version "$BASE" "$product")
    old_status=$?
    new_version=$(read_version "$TARGET" "$product")
    new_status=$?

    if [[ $old_status -eq 10 ]]; then
        invalid_structure "$product" "$BASE" "Missing data-products/$product/product.yml. New/deleted products are outside this prototype's lifecycle."
        failures=$((failures + 1))
        continue
    elif [[ $old_status -ge 20 ]]; then
        invalid_structure "$product" "$BASE" "Found $((old_status - 20)) top-level version entries."
        failures=$((failures + 1))
        continue
    fi
    if [[ $new_status -eq 10 ]]; then
        invalid_structure "$product" "$TARGET" "Missing data-products/$product/product.yml."
        failures=$((failures + 1))
        continue
    elif [[ $new_status -ge 20 ]]; then
        invalid_structure "$product" "$TARGET" "Found $((new_status - 20)) top-level version entries."
        failures=$((failures + 1))
        continue
    fi

    if [[ ! $old_version =~ $SEMVER_REGEX ]]; then
        printf "ERROR: invalid previous product version for '%s'\n\nFound:\n  %s\n\nExpected:\n  MAJOR.MINOR.PATCH\n\n" "$product" "$old_version" >&2
        failures=$((failures + 1))
        continue
    fi
    if [[ ! $new_version =~ $SEMVER_REGEX ]]; then
        printf "ERROR: invalid product version for '%s'\n\nFound:\n  %s\n\nExpected:\n  MAJOR.MINOR.PATCH\n\nExample:\n  2.4.0\n\n" "$product" "$new_version" >&2
        failures=$((failures + 1))
        continue
    fi

    if [[ $new_version == "$old_version" ]]; then
        printf "ERROR: data-product '%s' has changed but its version has not.\n\nPrevious version: %s\nCurrent version:  %s\n\nUpdate:\n  data-products/%s/product.yml\n\nChoose the appropriate SemVer change:\n  PATCH - backwards-compatible correction\n  MINOR - backwards-compatible addition\n  MAJOR - breaking change\n\n" "$product" "$old_version" "$new_version" "$product" >&2
        failures=$((failures + 1))
    elif ! is_greater "$new_version" "$old_version"; then
        printf "ERROR: invalid version change for data-product '%s'\n\nPrevious version: %s\nCurrent version:  %s\n\nThe data-product version must increase.\n\n" "$product" "$old_version" "$new_version" >&2
        failures=$((failures + 1))
    else
        printf "OK: %s %s -> %s\n" "$product" "$old_version" "$new_version"
    fi
done

if (( failures > 0 )); then
    printf 'Validation failed for %d data-product(s).\n' "$failures" >&2
    exit 1
fi

printf 'All changed data-product versions are valid.\n'
