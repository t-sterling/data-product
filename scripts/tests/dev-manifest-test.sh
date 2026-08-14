#!/usr/bin/env bash
set -euo pipefail

SOURCE_ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
TEST_ROOT=$(mktemp -d)
trap 'rm -rf "$TEST_ROOT"' EXIT
mkdir -p "$TEST_ROOT/artifacts" "$TEST_ROOT/deployments"

printf 'zip-bytes' > "$TEST_ROOT/artifacts/orders-1.2.3.zip"
cat > "$TEST_ROOT/artifacts/orders-1.2.3.artifact.json" <<'JSON'
{
  "product": "orders",
  "version": "1.2.3",
  "gitCommit": "0123456789abcdef",
  "gitBranch": "feature/orders",
  "file": "orders-1.2.3.zip",
  "sha256": "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
  "contentSha256": "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"
}
JSON

GITHUB_REPOSITORY=example/source bash "$SOURCE_ROOT/.github/scripts/write-dev-manifests.sh" \
    "$TEST_ROOT/artifacts" "$TEST_ROOT/deployments" candidate s3://prototype/data-products >/dev/null

manifest="$TEST_ROOT/deployments/environments/dev/products/orders.yml"
grep -Fq 'releaseStatus: candidate' "$manifest"
grep -Fq 'repository: example/source' "$manifest"
grep -Fq 'uri: s3://prototype/data-products/candidates/orders/1.2.3/0123456789abcdef/orders-1.2.3.zip' "$manifest"
grep -Fq 'sha256: aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa' "$manifest"

echo 'PASS: pinned DEV candidate manifest'
