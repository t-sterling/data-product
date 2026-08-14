# Git-Native Data-Product Versioning Prototype

This repository demonstrates independently versioned data-products in one Maven monorepo. The repository is a shared source and build container, but **each directory immediately below `data-products/` is its own release unit**. For example, the same commit can describe `orders:2.3.1` and `customers:5.1.0`.

The invariant is simple: if files belonging to a data-product change between two commits, that product's `product.yml` version must also change to a strictly greater numeric SemVer. Git commits, refs, diffs, and repository contents are the entire validation interface; no GitHub API or CI-provider feature is involved.

## Layout

```text
.
|-- pom.xml                         Maven parent and aggregator
|-- data-products/
|   |-- orders/                     Independent Maven/release unit
|   `-- customers/                  Independent Maven/release unit
|-- scripts/
|   |-- changed-products.sh
|   |-- validate-product-versions.sh
|   |-- build-changed-products.sh
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

## Build and test

Requirements are Git, Bash, JDK 17 or later, and Maven.

```bash
mvn clean verify
./tests/shell-tools-test.sh
```

Install the local hook once after cloning:

```bash
./scripts/install-hooks.sh
```

This sets the repository-local `core.hooksPath` to `.githooks`; no manual copying into `.git/hooks` is needed.

## Validation and changed builds

`changed-products.sh` diffs two commits, keeps paths shaped like `data-products/<product>/...`, extracts the immediate child directory, and deduplicates the names:

```bash
./scripts/changed-products.sh origin/develop HEAD
./scripts/validate-product-versions.sh origin/develop HEAD
```

The validator reads both historical `product.yml` files directly with `git show`. It reports all affected invalid products it can, including unchanged versions, downgrades, invalid SemVer, missing fields, and duplicate fields. It never checks out or mutates either commit.

After a merge, CI can validate and build only affected reactor modules:

```bash
./scripts/build-changed-products.sh <previous-develop-sha> <new-develop-sha>
```

The script runs a single Maven reactor selection such as `mvn -pl data-products/orders -am clean verify`, then prints release identities such as `orders:1.3.0`, read from `product.yml`. It does not publish anything.

## Developer workflow

1. Branch from `develop` and change, for example, `data-products/orders/**`.
2. Decide explicitly whether the product change is PATCH, MINOR, or MAJOR. Automation cannot know its business compatibility.
3. Edit `data-products/orders/product.yml`, for example `1.2.3 -> 1.3.0`, and commit source and version together.
4. Run `mvn test`, then `git push`.
5. The local pre-push hook validates `origin/develop -> HEAD`. A forgotten or invalid bump rejects the push and tells the developer what to fix; it never modifies files or chooses a version.
6. Raise and merge the GitHub PR into `develop`.
7. Post-merge CI compares the previous and new `develop` SHAs, validates versions, selects changed modules, and reads immutable release identities from the merged source.

CI does not create a post-merge bump commit. Checking out the merge commit must reconstruct the exact source and product version that was released.

## Walkthrough with real commits

Starting from a commit where both products are `1.0.0`:

```bash
# Successful minor orders change
git switch -c demo/orders-minor
echo '// demo change' >> data-products/orders/src/main/java/com/example/dataproducts/orders/OrdersDataProduct.java
sed -i 's/version: 1.0.0/version: 1.1.0/' data-products/orders/product.yml
git add data-products/orders && git commit -m "Add orders capability (1.1.0)"
./scripts/validate-product-versions.sh develop HEAD       # passes

# Forgotten customers version
git switch -c demo/customers-patch develop
echo '// demo fix' >> data-products/customers/src/main/java/com/example/dataproducts/customers/CustomersDataProduct.java
git add data-products/customers && git commit -m "Fix customers"
./scripts/validate-product-versions.sh develop HEAD       # fails: still 1.0.0
sed -i 's/version: 1.0.0/version: 1.0.1/' data-products/customers/product.yml
git add data-products/customers/product.yml && git commit -m "Release customers 1.0.1"
./scripts/validate-product-versions.sh develop HEAD       # passes
```

For a two-product commit, change orders `1.1.0 -> 2.0.0` and customers `1.0.1 -> 1.1.0`; the validator reports and accepts both. The test harness creates temporary repositories and exercises this case plus all failure modes without rewriting this repository's history.

## Local versus authoritative enforcement

The local `.githooks/pre-push` hook is early developer feedback. It assumes feature branches are based on `origin/develop`; fetch that ref before pushing.

`examples/hooks/pre-receive` shows authoritative enforcement on a Git server that supports repository pre-receive hooks. It consumes `<old-sha> <new-sha> <ref-name>`, validates updates to `refs/heads/develop`, and ignores other refs. When deploying it into a bare server repository, deploy the core scripts too and set `PRODUCT_VERSION_VALIDATOR` to the executable validator's absolute path. GitHub does not allow arbitrary per-repository pre-receive hooks in the same way as a self-hosted Git server, but the core validator remains hosting-provider-independent and can be invoked by any enforcement environment.

## Lifecycle and boundaries

```text
PR merged to develop
        -> changed data-product detected
        -> version read from product.yml
        -> selected module built and tested
        -> immutable data-product artifact published
        -> artifact promoted through environments
```

Actual publication, GitHub Actions, JFrog/Nexus, Argo, automatic bumping, automatic SemVer classification, schema compatibility analysis, and real data-product behavior are intentionally out of scope. The prototype tests the release-unit and Git lifecycle model, not a generalized release framework.
