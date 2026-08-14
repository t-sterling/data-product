#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT=$(git rev-parse --show-toplevel)
cd "$REPO_ROOT"
git config core.hooksPath .githooks

if git rev-parse --verify 'origin/develop^{commit}' >/dev/null 2>&1; then
    BASE_REF=origin/develop
elif git rev-parse --verify 'origin/main^{commit}' >/dev/null 2>&1; then
    BASE_REF=origin/main
else
    BASE_REF=origin/develop
    echo "WARNING: neither origin/develop nor origin/main exists locally." >&2
fi

git config productVersions.baseRef "$BASE_REF"
echo "Installed repository hooks from .githooks."
echo "Product version comparison base: $BASE_REF"
