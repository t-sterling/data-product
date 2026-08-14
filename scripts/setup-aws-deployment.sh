#!/usr/bin/env bash
set -euo pipefail

usage() {
    cat <<'USAGE'
Configure AWS and GitHub for immutable data-product publication.

Usage:
  ./scripts/setup-aws-deployment.sh \
    --bucket <bucket-name> \
    --region <aws-region> \
    --github-repo <owner/repository> \
    [--prefix <key-prefix>] \
    [--role-name <iam-role-name>] \
    [--environment <github-environment>] \
    [--profile <aws-profile>]

The command is idempotent. It configures the S3 bucket, GitHub OIDC provider,
IAM publishing role, GitHub environment, and GitHub Actions variables.

Prerequisites:
  - AWS CLI authenticated as an identity allowed to manage S3 and IAM
  - GitHub CLI authenticated with repository administration access
USAGE
}

BUCKET=''
REGION=''
GITHUB_REPO=''
PREFIX='data-products'
ROLE_NAME='data-product-github-publisher'
ENVIRONMENT='data-product-production'
AWS_PROFILE=''

while [[ $# -gt 0 ]]; do
    case $1 in
        --bucket) BUCKET=${2:-}; shift 2 ;;
        --region) REGION=${2:-}; shift 2 ;;
        --github-repo) GITHUB_REPO=${2:-}; shift 2 ;;
        --prefix) PREFIX=${2:-}; shift 2 ;;
        --role-name) ROLE_NAME=${2:-}; shift 2 ;;
        --environment) ENVIRONMENT=${2:-}; shift 2 ;;
        --profile) AWS_PROFILE=${2:-}; shift 2 ;;
        -h|--help) usage; exit 0 ;;
        *) echo "ERROR: unknown argument '$1'." >&2; usage >&2; exit 2 ;;
    esac
done

[[ -n $BUCKET && -n $REGION && -n $GITHUB_REPO ]] || { usage >&2; exit 2; }
[[ $GITHUB_REPO == */* ]] || { echo 'ERROR: --github-repo must be owner/repository.' >&2; exit 2; }
[[ $PREFIX != /* && $PREFIX != */ ]] || { echo 'ERROR: --prefix must not start or end with /.' >&2; exit 2; }
command -v aws >/dev/null 2>&1 || { echo 'ERROR: AWS CLI is required.' >&2; exit 2; }
command -v gh >/dev/null 2>&1 || { echo 'ERROR: GitHub CLI is required.' >&2; exit 2; }

AWS_ARGS=(--no-cli-pager)
[[ -z $AWS_PROFILE ]] || AWS_ARGS+=(--profile "$AWS_PROFILE")

echo 'Checking AWS and GitHub authentication...'
ACCOUNT_ID=$(aws "${AWS_ARGS[@]}" sts get-caller-identity --query Account --output text)
gh auth status >/dev/null

# GitHub repositories created after 2026-07-15 use immutable IDs in OIDC subjects.
read -r OWNER_ID REPO_ID < <(gh api "repos/$GITHUB_REPO" --jq '"\(.owner.id) \(.id)"')
OWNER=${GITHUB_REPO%%/*}
REPOSITORY=${GITHUB_REPO#*/}
OIDC_SUBJECT="repo:$OWNER@$OWNER_ID/$REPOSITORY@$REPO_ID:environment:$ENVIRONMENT"
OIDC_PROVIDER_ARN="arn:aws:iam::$ACCOUNT_ID:oidc-provider/token.actions.githubusercontent.com"
ROLE_ARN="arn:aws:iam::$ACCOUNT_ID:role/$ROLE_NAME"

echo "Configuring S3 bucket '$BUCKET' in '$REGION'..."
if ! aws "${AWS_ARGS[@]}" s3api head-bucket --bucket "$BUCKET" --expected-bucket-owner "$ACCOUNT_ID" >/dev/null 2>&1; then
    if [[ $REGION == us-east-1 ]]; then
        aws "${AWS_ARGS[@]}" s3api create-bucket --bucket "$BUCKET" --region "$REGION" --object-ownership BucketOwnerEnforced >/dev/null
    else
        aws "${AWS_ARGS[@]}" s3api create-bucket --bucket "$BUCKET" --region "$REGION" \
            --create-bucket-configuration "LocationConstraint=$REGION" --object-ownership BucketOwnerEnforced >/dev/null
    fi
fi

BUCKET_REGION=$(aws "${AWS_ARGS[@]}" s3api get-bucket-location --bucket "$BUCKET" --query LocationConstraint --output text)
[[ $BUCKET_REGION != None ]] || BUCKET_REGION=us-east-1
[[ $BUCKET_REGION == "$REGION" ]] || {
    echo "ERROR: bucket is in '$BUCKET_REGION', not requested region '$REGION'." >&2
    exit 1
}

aws "${AWS_ARGS[@]}" s3api put-public-access-block --bucket "$BUCKET" \
    --public-access-block-configuration 'BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true'
aws "${AWS_ARGS[@]}" s3api put-bucket-ownership-controls --bucket "$BUCKET" \
    --ownership-controls 'Rules=[{ObjectOwnership=BucketOwnerEnforced}]'
aws "${AWS_ARGS[@]}" s3api put-bucket-versioning --bucket "$BUCKET" \
    --versioning-configuration Status=Enabled
aws "${AWS_ARGS[@]}" s3api put-bucket-encryption --bucket "$BUCKET" \
    --server-side-encryption-configuration '{"Rules":[{"ApplyServerSideEncryptionByDefault":{"SSEAlgorithm":"AES256"}}]}'

echo 'Configuring the GitHub Actions OIDC provider...'
if ! aws "${AWS_ARGS[@]}" iam get-open-id-connect-provider \
    --open-id-connect-provider-arn "$OIDC_PROVIDER_ARN" >/dev/null 2>&1; then
    aws "${AWS_ARGS[@]}" iam create-open-id-connect-provider \
        --url https://token.actions.githubusercontent.com \
        --client-id-list sts.amazonaws.com \
        --tags Key=ManagedBy,Value=dp-devops >/dev/null
fi

TEMP_DIR=$(mktemp -d)
trap 'rm -rf "$TEMP_DIR"' EXIT
TRUST_POLICY="$TEMP_DIR/trust-policy.json"
PERMISSIONS_POLICY="$TEMP_DIR/permissions-policy.json"

cat > "$TRUST_POLICY" <<JSON
{
  "Version": "2012-10-17",
  "Statement": [{
    "Effect": "Allow",
    "Principal": {"Federated": "$OIDC_PROVIDER_ARN"},
    "Action": "sts:AssumeRoleWithWebIdentity",
    "Condition": {
      "StringEquals": {
        "token.actions.githubusercontent.com:aud": "sts.amazonaws.com",
        "token.actions.githubusercontent.com:sub": "$OIDC_SUBJECT"
      }
    }
  }]
}
JSON

cat > "$PERMISSIONS_POLICY" <<JSON
{
  "Version": "2012-10-17",
  "Statement": [{
    "Sid": "PublishImmutableDataProducts",
    "Effect": "Allow",
    "Action": ["s3:PutObject"],
    "Resource": "arn:aws:s3:::$BUCKET/$PREFIX/*"
  }]
}
JSON

echo "Configuring IAM role '$ROLE_NAME'..."
if aws "${AWS_ARGS[@]}" iam get-role --role-name "$ROLE_NAME" >/dev/null 2>&1; then
    aws "${AWS_ARGS[@]}" iam update-assume-role-policy --role-name "$ROLE_NAME" \
        --policy-document "$(<"$TRUST_POLICY")"
else
    aws "${AWS_ARGS[@]}" iam create-role --role-name "$ROLE_NAME" \
        --assume-role-policy-document "$(<"$TRUST_POLICY")" \
        --description 'Publishes immutable data-product releases from GitHub Actions' \
        --tags Key=ManagedBy,Value=dp-devops >/dev/null
fi
aws "${AWS_ARGS[@]}" iam put-role-policy --role-name "$ROLE_NAME" \
    --policy-name DataProductS3Publisher --policy-document "$(<"$PERMISSIONS_POLICY")"

echo "Configuring GitHub environment '$ENVIRONMENT' and Actions variables..."
gh api --method PUT "repos/$GITHUB_REPO/environments/$ENVIRONMENT" >/dev/null
gh variable set AWS_REGION --repo "$GITHUB_REPO" --env "$ENVIRONMENT" --body "$REGION"
gh variable set AWS_ROLE_ARN --repo "$GITHUB_REPO" --env "$ENVIRONMENT" --body "$ROLE_ARN"
gh variable set DATA_PRODUCT_BUCKET --repo "$GITHUB_REPO" --env "$ENVIRONMENT" --body "$BUCKET"
gh variable set DATA_PRODUCT_PREFIX --repo "$GITHUB_REPO" --env "$ENVIRONMENT" --body "$PREFIX"

cat <<SUMMARY

AWS deployment setup complete.

  Account:            $ACCOUNT_ID
  Bucket:             s3://$BUCKET/$PREFIX/
  Region:             $REGION
  IAM role:           $ROLE_ARN
  GitHub repository:  $GITHUB_REPO
  GitHub environment: $ENVIRONMENT
  OIDC subject:       $OIDC_SUBJECT

The command is safe to rerun to reconcile this configuration.
SUMMARY
