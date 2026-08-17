# Data products

This repository contains independently versioned data-products and the automation that packages them as immutable artifacts. A data-product contains metadata and deployable content—not Java application code.

The separate [`data-product-deployment`](https://github.com/t-sterling/data-product-deployment) repository owns environment desired state and Argo orchestration.

## How the repositories fit together

```text
data-product feature push
  -> validate changed product versions
  -> build ZIPs for changed products only
  -> publish SHA-addressed candidates to S3
  -> update DEV desired state in data-product-deployment
  -> Argo deploys the candidate to DEV

pull request merged to main
  -> verify merged content matches the DEV-tested candidate
  -> publish an immutable release to S3
  -> update DEV desired state from candidate to release

higher-environment promotion
  -> pull request in data-product-deployment
  -> reference the same immutable release artifact
```

There is no `latest` artifact. DEV is the only environment allowed to consume candidates. Higher environments consume releases only.

## Repository layout

```text
.
|-- data-products/
|   |-- orders/
|   `-- customers/
|-- scripts/
|   |-- assembly/                   Shared ZIP descriptor
|   |-- infra/                      Repeatable AWS/GitHub setup
|   |-- tests/                      Shell regression tests
|   |-- build-changed-products.sh
|   |-- changed-products.sh
|   |-- install-hooks.sh
|   `-- validate-product-versions.sh
|-- .github/
|   |-- workflows/                  Candidate and release workflows
|   `-- scripts/                    CI-only publication/GitOps helpers
|-- .githooks/                      Local pre-push validation
|-- pom.xml                         Maven aggregator
`-- README.md
```

## Data-product contract

Every immediate directory below `data-products/` is an independent release unit:

```text
data-products/orders/
|-- product.yml
|-- config/
|-- schema/
|-- sql/
`-- meta/
```

`product.yml` owns the product identity and version:

```yaml
name: orders
version: 2.0.2
owner: orders-team
description: Orders data-product
```

The version must be an unquoted numeric SemVer (`MAJOR.MINOR.PATCH`). If any file belonging to a product changes, that product's version must increase. Unchanged products do not require a version change. Changes outside `data-products/` do not require any product version change.

Maven is used only as a build orchestrator. Each product module has `pom` packaging, and the Assembly Plugin creates a ZIP containing `product.yml`, `config/`, `schema/`, `sql/`, and `meta/` at its root.

## Developer workflow

Install the local validation hook once after cloning:

```bash
bash ./scripts/install-hooks.sh
```

For a product change:

1. Branch from current `main`.
2. Change one or more files inside the product directory.
3. Increment only the changed product's version.
4. Commit and push the branch.
5. Wait for the candidate workflow and automatic DEV deployment.
6. Iterate with further feature-branch pushes until DEV validation passes.
7. Raise the source pull request without changing the tested content.
8. Merge to `main`; release CI verifies the content and publishes the release.

Useful local checks:

```bash
bash ./scripts/changed-products.sh origin/main HEAD
bash ./scripts/validate-product-versions.sh origin/main HEAD
bash ./scripts/build-changed-products.sh origin/main HEAD
```

The validator reads both revisions directly from Git. It reports unchanged or downgraded versions, malformed SemVer, missing metadata, and duplicate version fields without modifying either commit.

## Candidate artifacts

Every successful feature push that changes a product publishes a candidate addressed by version and Git SHA:

```text
s3://<bucket>/<prefix>/candidates/<product>/<version>/<git-sha>/<product>-<version>.zip
s3://<bucket>/<prefix>/candidates/<product>/<version>/<git-sha>/<product>-<version>.zip.sha256
s3://<bucket>/<prefix>/candidates/<product>/<version>/<git-sha>/<product>-<version>.artifact.json
```

The workflow then commits `environments/dev/products/<product>.yml` in the deployment repository. Shared DEV follows that manifest; a later successful feature push for the same product replaces its desired candidate.

## Release artifacts

After a merge to `main`, CI compares a stable digest of the merged product tree with the candidate recorded in DEV. A mismatch fails the release. A match publishes:

```text
s3://<bucket>/<prefix>/releases/<product>/<version>/<product>-<version>.zip
s3://<bucket>/<prefix>/releases/<product>/<version>/<product>-<version>.zip.sha256
s3://<bucket>/<prefix>/releases/<product>/<version>/<product>-<version>.artifact.json
```

S3 writes use `If-None-Match: *`; an existing coordinate is never overwritten.

## GitHub Actions

Two workflows implement the lifecycle:

- `.github/workflows/publish-candidates.yml` runs on non-`main` product changes, publishes candidates, and writes DEV desired state.
- `.github/workflows/publish-data-products.yml` runs on `main`, enforces the DEV-tested-content gate, publishes releases, and records released DEV state.

The workflows use GitHub OIDC to assume a short-lived AWS publishing role. They use a fine-grained repository token to write the separate deployment repository. Required environment configuration is created by the infrastructure setup command except for the token secret:

```bash
bash ./scripts/infra/setup-aws-deployment.sh \
  --bucket ts-data-products \
  --region us-east-1 \
  --github-repo t-sterling/data-product \
  --deployment-repo t-sterling/data-product-deployment
```

Add `DEPLOYMENT_REPO_TOKEN` manually to the `data-product-production` GitHub environment. It needs contents read/write access to the deployment repository. Rerun the setup command after a repository rename so the AWS OIDC trust subject remains correct.

## Tests

```bash
bash ./scripts/tests/shell-tools-test.sh
bash ./scripts/tests/publish-artifacts-test.sh
bash ./scripts/tests/dev-manifest-test.sh
bash ./scripts/tests/setup-aws-deployment-test.sh
```

The complete platform installation, IAM/RBAC explanation, local-cluster setup, and corporate EKS/Rafay equivalents are documented in the deployment repository's [`setup.md`](https://github.com/t-sterling/data-product-deployment/blob/main/setup.md).
