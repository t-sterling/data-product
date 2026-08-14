#!/usr/bin/env bash
set -euo pipefail

[[ $# -ge 2 && $# -le 3 ]] || {
    echo "Usage: $0 <artifact-directory> <bucket> [key-prefix]" >&2
    exit 2
}

ARTIFACT_DIR=$1
BUCKET=$2
PREFIX=${3:-data-products}

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
    key="$PREFIX/$product/$version/$filename"

    echo "Publishing s3://$BUCKET/$key"
    aws s3api put-object \
        --bucket "$BUCKET" \
        --key "$key" \
        --body "$zip" \
        --content-type application/zip \
        --metadata "product=$product,version=$version" \
        --if-none-match '*'

    for sidecar in "$ARTIFACT_DIR/$identity.zip.sha256" "$ARTIFACT_DIR/$identity.release.json"; do
        sidecar_name=$(basename "$sidecar")
        aws s3api put-object \
            --bucket "$BUCKET" \
            --key "$PREFIX/$product/$version/$sidecar_name" \
            --body "$sidecar" \
            --if-none-match '*'
    done
done
