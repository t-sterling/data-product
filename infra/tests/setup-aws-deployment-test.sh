#!/usr/bin/env bash
set -euo pipefail

SOURCE_ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
TEST_ROOT=$(mktemp -d)
trap 'rm -rf "$TEST_ROOT"' EXIT
mkdir -p "$TEST_ROOT/bin"

cat > "$TEST_ROOT/bin/aws" <<'MOCK'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$SETUP_MOCK_LOG"
case "$*" in
    *'sts get-caller-identity'*) echo 123456789012 ;;
    *'s3api get-bucket-location'*) echo None ;;
esac
exit 0
MOCK

cat > "$TEST_ROOT/bin/gh" <<'MOCK'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$SETUP_MOCK_LOG"
if [[ $* == *'api repos/example/data-products --jq'* ]]; then
    echo '111 222'
fi
exit 0
MOCK
chmod +x "$TEST_ROOT/bin/aws" "$TEST_ROOT/bin/gh"

export SETUP_MOCK_LOG="$TEST_ROOT/setup.log"
PATH="$TEST_ROOT/bin:$PATH" "$SOURCE_ROOT/infra/setup-aws-deployment.sh" \
    --bucket example-bucket \
    --region us-east-1 \
    --github-repo example/data-products >/dev/null

grep -Fq 's3api put-public-access-block --bucket example-bucket' "$SETUP_MOCK_LOG"
grep -Fq 's3api put-bucket-versioning --bucket example-bucket' "$SETUP_MOCK_LOG"
grep -Fq 'iam put-role-policy --role-name data-product-github-publisher' "$SETUP_MOCK_LOG"
grep -Fq 'variable set AWS_ROLE_ARN --repo example/data-products --env data-product-production' "$SETUP_MOCK_LOG"

echo 'PASS: repeatable AWS/GitHub setup arguments'
