#!/usr/bin/env bash
set -euo pipefail

[[ $# -eq 2 ]] || { echo "Usage: $0 <base-sha> <target-sha>" >&2; exit 2; }
BASE=$1
TARGET=$2
SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
REPO_ROOT=$(git rev-parse --show-toplevel)
TARGET_COMMIT=$(git rev-parse "${TARGET}^{commit}")

mapfile -t PRODUCTS < <(bash "$SCRIPT_DIR/changed-products.sh" "$BASE" "$TARGET")
bash "$SCRIPT_DIR/validate-product-versions.sh" "$BASE" "$TARGET"

if [[ ${#PRODUCTS[@]} -eq 0 ]]; then
    echo "No changed data-products; nothing to build."
    exit 0
fi

declare -a MODULES=()
declare -a VERSIONS=()
ARTIFACT_DIR="$REPO_ROOT/target/data-product-artifacts"
rm -rf "$ARTIFACT_DIR"
mkdir -p "$ARTIFACT_DIR"
printf '\nChanged data-products:\n\n'
for product in "${PRODUCTS[@]}"; do
    old_version=$(git show "$BASE:data-products/$product/product.yml" | sed -n 's/^version:[[:space:]]*//p')
    new_version=$(git show "$TARGET:data-products/$product/product.yml" | sed -n 's/^version:[[:space:]]*//p')
    printf '  %-12s %s -> %s\n' "$product" "$old_version" "$new_version"
    MODULES+=("data-products/$product")
    VERSIONS+=("$new_version")
done

printf '\nBuilding:\n'
for index in "${!PRODUCTS[@]}"; do
    product=${PRODUCTS[$index]}
    version=${VERSIONS[$index]}
    module=${MODULES[$index]}
    printf '  %s\n' "$module"
    (cd "$REPO_ROOT" && mvn -pl "$module" -Dproduct.release.version="$version" clean package)

    zip="$REPO_ROOT/$module/target/$product-$version.zip"
    [[ -f $zip ]] || { echo "ERROR: expected build output '$zip' was not created." >&2; exit 1; }
    cp "$zip" "$ARTIFACT_DIR/"
    (cd "$ARTIFACT_DIR" && sha256sum "$product-$version.zip" > "$product-$version.zip.sha256")
    checksum=$(awk '{ print $1 }' "$ARTIFACT_DIR/$product-$version.zip.sha256")
    content_checksum=$(git ls-tree -r "$TARGET_COMMIT" -- "data-products/$product" | sha256sum | awk '{ print $1 }')
    cat > "$ARTIFACT_DIR/$product-$version.artifact.json" <<JSON
{
  "product": "$product",
  "version": "$version",
  "gitCommit": "$TARGET_COMMIT",
  "gitBranch": "${GITHUB_REF_NAME:-local}",
  "file": "$product-$version.zip",
  "sha256": "$checksum",
  "contentSha256": "$content_checksum"
}
JSON
done

printf '\nCreated artifacts:\n'
for index in "${!PRODUCTS[@]}"; do
    printf '  %s:%s -> target/data-product-artifacts/%s-%s.zip\n' \
        "${PRODUCTS[$index]}" "${VERSIONS[$index]}" "${PRODUCTS[$index]}" "${VERSIONS[$index]}"
done
