# Git-Native Data-Product Versioning Prototype

This repository demonstrates independently versioned data-products in one Maven monorepo. The repository is a shared source and build container, but **each directory immediately below `data-products/` is its own release unit**. For example, the same commit can describe `orders:2.3.1` and `customers:5.1.0`.

The invariant is simple: if files belonging to a data-product change between two commits, that product's `product.yml` version must also change to a strictly greater numeric SemVer. Git commits, refs, diffs, and repository contents are the entire validation interface; no GitHub API or CI-provider feature is involved.

## Layout

```text
.
|-- pom.xml                         Maven parent and aggregator
|-- data-products/
|   |-- orders/                     product.yml + config/schema/sql/meta
|   `-- customers/                  product.yml + config/schema/sql/meta
|-- src/assembly/data-product.xml   Shared ZIP layout
|-- .github/workflows/              Merge-to-main build and S3 publication
|-- scripts/
|   |-- changed-products.sh
|   |-- validate-product-versions.sh
|   |-- build-changed-products.sh
|   |-- publish-artifacts-to-s3.sh
|   `-- install-hooks.sh
|-- .githooks/pre-push              Early local feedback
|-- examples/hooks/pre-receive      Authoritative server example
`-- tests/shell-tools-test.sh
```

All Maven projects deliberately inherit the parent version `0.0.1-SNAPSHOT`. That coordinate is a build implementation detail, not a product's release identity. The authoritative identity is the top-level field in its metadata:

```yaml
name: orders
version: 1.0.0
owner: orders-team
description: Dummy orders data-product
```

The format is intentionally constrained to exactly one unquoted top-level `version: MAJOR.MINOR.PATCH` line. Standard `sed`, `awk`, and Bash can therefore parse it transparently; a general YAML parser would add complexity without helping this prototype.

Each product module has Maven packaging type `pom`; it contains no Java application. Maven is the common build orchestrator, and the Assembly Plugin packages `product.yml`, `config/`, `schema/`, `sql/`, and `meta/` using the shared descriptor. The release ZIP contains those entries at its root so a future Argo workflow can extract and deploy them directly.

## Build and test

Requirements are Git, Bash, JDK 17 or later, and Maven.

```bash
./tests/shell-tools-test.sh
./tests/publish-artifacts-test.sh
./scripts/build-changed-products.sh origin/main HEAD
```

Install the local hook once after cloning:

```bash
./scripts/install-hooks.sh
```

This sets the repository-local `core.hooksPath` to `.githooks`; no manual copying into `.git/hooks` is needed. It also records `productVersions.baseRef`, preferring `origin/develop` and falling back to `origin/main` when that is the repository's integration branch. Override it explicitly when needed:

```bash
git config productVersions.baseRef origin/release
```

## Validation and changed builds

`changed-products.sh` diffs two commits, keeps paths shaped like `data-products/<product>/...`, extracts the immediate child directory, and deduplicates the names:

```bash
./scripts/changed-products.sh origin/main HEAD
./scripts/validate-product-versions.sh origin/main HEAD
```

The validator reads both historical `product.yml` files directly with `git show`. It reports all affected invalid products it can, including unchanged versions, downgrades, invalid SemVer, missing fields, and duplicate fields. It never checks out or mutates either commit.

After a merge, CI can validate and build only affected reactor modules:

```bash
./scripts/build-changed-products.sh <previous-main-sha> <new-main-sha>
```

For every changed product, the script passes the authoritative `product.yml` version into Maven only as the ZIP filename, for example `mvn -pl data-products/orders -Dproduct.release.version=1.3.0 clean package`. It copies the resulting `orders-1.3.0.zip`, SHA-256 sidecar, and JSON release manifest into `target/data-product-artifacts/`.

## GitHub Actions and S3 publication

`.github/workflows/publish-data-products.yml` runs after a commit reaches `main` (normally through a protected-branch PR merge). It checks out full history, compares the push event's before/after SHAs, validates and builds only changed products, retains the outputs as GitHub run artifacts, assumes an AWS role using GitHub OIDC, and conditionally creates immutable S3 objects. A documentation-only merge succeeds without attempting an upload.

Create the GitHub environment `data-product-production` and define these Actions variables at repository or environment scope:

| Variable | Example | Purpose |
|---|---|---|
| `AWS_REGION` | `us-east-1` | AWS region used for OIDC and S3 |
| `AWS_ROLE_ARN` | `arn:aws:iam::123456789012:role/dp-github-publisher` | Role assumed by the workflow |
| `DATA_PRODUCT_BUCKET` | `company-data-product-artifacts` | Destination bucket |
| `DATA_PRODUCT_PREFIX` | `data-products` | Optional key prefix |

Configure AWS IAM to trust GitHub's OIDC provider and restrict the role's subject to this repository's `data-product-production` environment. The role needs `s3:PutObject` for:

```text
arn:aws:s3:::<bucket>/<prefix>/*
```

The publisher uses S3 `If-None-Match: *`; attempting to reuse an existing product/version key fails rather than overwriting a release. Objects are laid out as:

```text
s3://<bucket>/<prefix>/orders/1.3.0/orders-1.3.0.zip
s3://<bucket>/<prefix>/orders/1.3.0/orders-1.3.0.zip.sha256
s3://<bucket>/<prefix>/orders/1.3.0/orders-1.3.0.release.json
```

## Developer workflow

1. Branch from `main` and change, for example, `data-products/orders/**`.
2. Decide explicitly whether the product change is PATCH, MINOR, or MAJOR. Automation cannot know its business compatibility.
3. Edit `data-products/orders/product.yml`, for example `1.2.3 -> 1.3.0`, and commit source and version together.
4. Run the validator or changed-product build, then `git push`.
5. The local pre-push hook validates the configured integration branch against `HEAD`. A forgotten or invalid bump rejects the push and tells the developer what to fix; it never modifies files or chooses a version.
6. Raise and merge the GitHub PR into protected `main`.
7. GitHub Actions compares the previous and new `main` SHAs, creates ZIPs for changed products, and publishes each immutable release to S3.

CI does not create a post-merge bump commit. Checking out the merge commit must reconstruct the exact source and product version that was released.

## Walkthrough with real commits

Starting from a commit where both products are `1.0.0`:

```bash
# Successful minor orders change
git switch -c demo/orders-minor
echo 'deployment.mode=expanded' >> data-products/orders/config/orders.properties
sed -i 's/version: 1.0.0/version: 1.1.0/' data-products/orders/product.yml
git add data-products/orders && git commit -m "Add orders capability (1.1.0)"
./scripts/validate-product-versions.sh main HEAD          # passes

# Forgotten customers version
git switch -c demo/customers-patch main
echo '-- customer fix' >> data-products/customers/sql/load-customers.sql
git add data-products/customers && git commit -m "Fix customers"
./scripts/validate-product-versions.sh main HEAD          # fails: still 1.0.0
sed -i 's/version: 1.0.0/version: 1.0.1/' data-products/customers/product.yml
git add data-products/customers/product.yml && git commit -m "Release customers 1.0.1"
./scripts/validate-product-versions.sh main HEAD          # passes
```

For a two-product commit, change orders `1.1.0 -> 2.0.0` and customers `1.0.1 -> 1.1.0`; the validator reports and accepts both. The test harness creates temporary repositories and exercises this case plus all failure modes without rewriting this repository's history.

## Local versus authoritative enforcement

The local `.githooks/pre-push` hook is early developer feedback. It compares against the base selected during installation (`origin/develop` by default, or `origin/main` for repositories like this one); fetch that ref before pushing.

`examples/hooks/pre-receive` shows authoritative enforcement on a Git server that supports repository pre-receive hooks. It consumes `<old-sha> <new-sha> <ref-name>`, validates updates to `refs/heads/develop`, and ignores other refs. When deploying it into a bare server repository, deploy the core scripts too and set `PRODUCT_VERSION_VALIDATOR` to the executable validator's absolute path. GitHub does not allow arbitrary per-repository pre-receive hooks in the same way as a self-hosted Git server, but the core validator remains hosting-provider-independent and can be invoked by any enforcement environment.

## Lifecycle and boundaries

```text
PR merged to main
        -> changed data-product detected
        -> version read from product.yml
        -> selected module assembled into a ZIP
        -> immutable data-product ZIP published to S3
        -> artifact promoted through environments
```

Argo execution, automatic bumping, automatic SemVer classification, schema compatibility analysis, and production deployment behavior remain out of scope. The ZIP and release manifest are the handoff to that future deployment phase.
