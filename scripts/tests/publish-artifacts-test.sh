#!/usr/bin/env bash
set -euo pipefail

SOURCE_ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
TEST_ROOT=$(mktemp -d)
trap 'rm -rf "$TEST_ROOT"' EXIT
mkdir -p "$TEST_ROOT/bin" "$TEST_ROOT/artifacts"

printf 'zip-bytes' > "$TEST_ROOT/artifacts/orders-1.2.3.zip"
printf 'checksum  orders-1.2.3.zip\n' > "$TEST_ROOT/artifacts/orders-1.2.3.zip.sha256"
printf '{"product":"orders"}\n' > "$TEST_ROOT/artifacts/orders-1.2.3.artifact.json"

cat > "$TEST_ROOT/bin/aws" <<'MOCK'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$AWS_MOCK_LOG"
MOCK
chmod +x "$TEST_ROOT/bin/aws"

export AWS_MOCK_LOG="$TEST_ROOT/aws.log"
PATH="$TEST_ROOT/bin:$PATH" \
    "$SOURCE_ROOT/.github/scripts/publish-artifacts-to-s3.sh" "$TEST_ROOT/artifacts" prototype-bucket candidate data-products abc123 >/dev/null

[[ $(wc -l < "$AWS_MOCK_LOG") -eq 3 ]]
grep -Fq -- '--key data-products/candidates/orders/1.2.3/abc123/orders-1.2.3.zip ' "$AWS_MOCK_LOG"
grep -Fq -- '--key data-products/candidates/orders/1.2.3/abc123/orders-1.2.3.zip.sha256 ' "$AWS_MOCK_LOG"
grep -Fq -- '--key data-products/candidates/orders/1.2.3/abc123/orders-1.2.3.artifact.json ' "$AWS_MOCK_LOG"
[[ $(grep -Fc -- '--if-none-match *' "$AWS_MOCK_LOG") -eq 3 ]]

echo 'PASS: immutable S3 publication arguments'
