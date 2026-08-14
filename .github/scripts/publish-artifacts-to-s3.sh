#!/usr/bin/env bash
set -euo pipefail

[[ $# -ge 3 && $# -le 5 ]] || {
    echo "Usage: $0 <artifact-directory> <bucket> <candidate|release> [key-prefix] [git-sha]" >&2
    exit 2
}

ARTIFACT_DIR=$1
BUCKET=$2
CHANNEL=$3
PREFIX=${4:-data-products}
GIT_SHA=${5:-}

[[ $CHANNEL == candidate || $CHANNEL == release ]] || { echo "ERROR: channel must be candidate or release." >&2; exit 2; }
if [[ $CHANNEL == candidate && -z $GIT_SHA ]]; then
    echo 'ERROR: candidate publication requires a Git SHA.' >&2
    exit 2
fi

[[ -d $ARTIFACT_DIR ]] || { echo "ERROR: artifact directory '$ARTIFACT_DIR' does not exist." >&2; exit 2; }
command -v aws >/dev/null 2>&1 || { echo "ERROR: AWS CLI is required." >&2; exit 2; }

shopt -s nullglob
zips=("$ARTIFACT_DIR"/*.zip)
[[ ${#zips[@]} -gt 0 ]] || { echo "ERROR: no ZIP artifacts found in '$ARTIFACT_DIR'." >&2; exit 2; }

for zip in "${zips[@]}"; do
    filename=$(basename "$zip")
    identity=${filename%.zip}
    version=${identity##*-}
    product=${identity%-$version}
    if [[ $CHANNEL == candidate ]]; then
        key_root="$PREFIX/candidates/$product/$version/$GIT_SHA"
    else
        key_root="$PREFIX/releases/$product/$version"
    fi
    key="$key_root/$filename"

    echo "Publishing s3://$BUCKET/$key"
    aws s3api put-object \
        --bucket "$BUCKET" \
        --key "$key" \
        --body "$zip" \
        --content-type application/zip \
        --metadata "product=$product,version=$version" \
        --if-none-match '*'

    for sidecar in "$ARTIFACT_DIR/$identity.zip.sha256" "$ARTIFACT_DIR/$identity.artifact.json"; do
        sidecar_name=$(basename "$sidecar")
        aws s3api put-object \
            --bucket "$BUCKET" \
            --key "$key_root/$sidecar_name" \
            --body "$sidecar" \
            --if-none-match '*'
    done
done
