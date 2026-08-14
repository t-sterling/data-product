#!/usr/bin/env bash
set -euo pipefail

[[ $# -eq 4 ]] || {
    echo "Usage: $0 <artifact-directory> <deployment-repo> <candidate|release> <s3-base-uri>" >&2
    exit 2
}

ARTIFACT_DIR=$1
DEPLOYMENT_REPO=$2
CHANNEL=$3
S3_BASE=${4%/}
[[ $CHANNEL == candidate || $CHANNEL == release ]] || { echo 'ERROR: invalid channel.' >&2; exit 2; }
mkdir -p "$DEPLOYMENT_REPO/environments/dev/products"

json_value() {
    local key=$1 file=$2
    sed -n "s/^[[:space:]]*\"$key\":[[:space:]]*\"\([^\"]*\)\"[,]\{0,1\}$/\1/p" "$file"
}

shopt -s nullglob
manifests=("$ARTIFACT_DIR"/*.artifact.json)
[[ ${#manifests[@]} -gt 0 ]] || { echo 'ERROR: no artifact manifests found.' >&2; exit 2; }

for artifact_manifest in "${manifests[@]}"; do
    product=$(json_value product "$artifact_manifest")
    version=$(json_value version "$artifact_manifest")
    commit=$(json_value gitCommit "$artifact_manifest")
    branch=$(json_value gitBranch "$artifact_manifest")
    checksum=$(json_value sha256 "$artifact_manifest")
    content_checksum=$(json_value contentSha256 "$artifact_manifest")
    filename=$(json_value file "$artifact_manifest")
    [[ -n $product && -n $version && -n $commit && -n $checksum && -n $content_checksum && -n $filename ]] || {
        echo "ERROR: malformed artifact manifest '$artifact_manifest'." >&2
        exit 1
    }

    if [[ $CHANNEL == candidate ]]; then
        uri="$S3_BASE/candidates/$product/$version/$commit/$filename"
    else
        uri="$S3_BASE/releases/$product/$version/$filename"
    fi

    cat > "$DEPLOYMENT_REPO/environments/dev/products/$product.yml" <<YAML
apiVersion: platform.example.io/v1alpha1
kind: DataProductDeployment
metadata:
  name: $product
spec:
  environment: dev
  product: $product
  version: $version
  releaseStatus: $CHANNEL
  source:
    repository: ${GITHUB_REPOSITORY:-local}
    branch: $branch
    commit: $commit
    contentSha256: $content_checksum
  artifact:
    uri: $uri
    sha256: $checksum
YAML
    echo "Updated DEV desired state for $product:$version ($CHANNEL, $commit)."
done
