#!/usr/bin/env bash
set -uo pipefail

SOURCE_ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
TEST_ROOT=$(mktemp -d)
trap 'rm -rf "$TEST_ROOT"' EXIT
PASS=0
FAIL=0

new_repo() {
    REPO="$TEST_ROOT/repo-$RANDOM-$RANDOM"
    mkdir -p "$REPO/scripts" "$REPO/data-products/orders" "$REPO/data-products/customers"
    cp "$SOURCE_ROOT/scripts/changed-products.sh" "$SOURCE_ROOT/scripts/validate-product-versions.sh" "$REPO/scripts/"
    chmod +x "$REPO/scripts/"*.sh
    cat > "$REPO/data-products/orders/product.yml" <<'YAML'
name: orders
version: 1.0.0
YAML
    cat > "$REPO/data-products/customers/product.yml" <<'YAML'
name: customers
version: 1.0.0
YAML
    echo initial > "$REPO/data-products/orders/content.txt"
    echo initial > "$REPO/data-products/customers/content.txt"
    (cd "$REPO" && git init -q && git config user.name Test && git config user.email test@example.invalid && git add . && git commit -qm initial)
    BASE=$(cd "$REPO" && git rev-parse HEAD)
}

commit_all() {
    (cd "$REPO" && git add . && git commit -qm test-change)
    TARGET=$(cd "$REPO" && git rev-parse HEAD)
}

expect_status() {
    local name=$1 expected=$2 actual
    shift 2
    (cd "$REPO" && "$@") >/dev/null 2>&1
    actual=$?
    if { [[ $expected == pass ]] && [[ $actual -eq 0 ]]; } || { [[ $expected == fail ]] && [[ $actual -ne 0 ]]; }; then
        printf 'PASS: %s\n' "$name"
        PASS=$((PASS + 1))
    else
        printf 'FAIL: %s (exit %d, expected %s)\n' "$name" "$actual" "$expected" >&2
        FAIL=$((FAIL + 1))
    fi
}

set_version() {
    local product=$1 version=$2
    sed -i "s/^version:.*/version: $version/" "$REPO/data-products/$product/product.yml"
}

change_product() {
    echo changed >> "$REPO/data-products/$1/content.txt"
}

run_validation() {
    "$REPO/scripts/validate-product-versions.sh" "$BASE" "$TARGET"
}

new_repo; echo docs > "$REPO/README.md"; commit_all
expect_status "non-product change" pass run_validation

new_repo; change_product orders; commit_all
expect_status "changed product, unchanged version" fail run_validation

for case in 'patch:1.0.1' 'minor:1.1.0' 'major:2.0.0'; do
    name=${case%%:*}; version=${case#*:}
    new_repo; change_product orders; set_version orders "$version"; commit_all
    expect_status "$name increment" pass run_validation
done

new_repo; set_version orders 0.9.9; commit_all
expect_status "version downgrade" fail run_validation

new_repo; set_version orders 1.1; commit_all
expect_status "invalid SemVer" fail run_validation

new_repo; sed -i '/^version:/d' "$REPO/data-products/orders/product.yml"; commit_all
expect_status "missing version" fail run_validation

new_repo; echo 'version: 1.0.1' >> "$REPO/data-products/orders/product.yml"; commit_all
expect_status "duplicate top-level version entries" fail run_validation

new_repo; change_product orders; change_product customers; set_version orders 1.0.1; set_version customers 1.1.0; commit_all
expect_status "two changed products, both valid" pass run_validation

new_repo; change_product orders; change_product customers; set_version orders 1.0.1; commit_all
expect_status "two changed products, one invalid" fail run_validation

printf '\n%d passed, %d failed\n' "$PASS" "$FAIL"
[[ $FAIL -eq 0 ]]
