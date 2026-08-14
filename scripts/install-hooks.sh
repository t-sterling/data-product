#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT=$(git rev-parse --show-toplevel)
cd "$REPO_ROOT"
git config core.hooksPath .githooks
echo "Installed repository hooks from .githooks."
