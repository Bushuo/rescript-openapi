# Three-Package GitHub Publish: Design

Date: 2026-04-13

## Goal

Replace the current vendored CLI publish model with a normal three-package release model on GitHub Packages while keeping the existing monorepo developer workflow intact.

The published packages will be:

- `@bushuo/openapi-rescript-runtime`
- `@bushuo/openapi-rescript-core`
- `@bushuo/openapi-rescript-cli`

All three packages share one release line and one version number.

## Decisions

### Keep Workspace And ReScript Names Stable In Repo

Do not rename the in-repo workspace package names or ReScript package names.

Reasoning:

- local monorepo development already works with the current names
- ReScript package naming and npm publish naming are separate concerns
- renaming internal package identities would create unnecessary churn in `rescript.json` files and tests

Published package names will instead be rewritten during the publish flow.

### Publish All Three Packages

`runtime`, `core`, and `cli` must all be published.

Reasoning:

- generated clients already depend on `openapi-rescript-runtime`
- `openapi-rescript-cli` should depend on `openapi-rescript-core` as a normal package
- removing vendoring only works cleanly if the dependency chain exists in published form

The publish dependency order is:

1. `runtime`
2. `core`
3. `cli`

### Use GitHub Packages Scoped To The Repository Owner

The public artifact names should be derived from the GitHub repository owner and published to GitHub Packages.

For this repository, the resulting package names are:

- `@bushuo/openapi-rescript-runtime`
- `@bushuo/openapi-rescript-core`
- `@bushuo/openapi-rescript-cli`

Reasoning:

- this matches the existing publish target
- it avoids maintaining different permanent names in source and publish metadata
- it keeps installation aligned with GitHub Packages scope rules

### One Shared Release Line

All three packages must carry the same committed version.

Reasoning:

- these packages are released as one logical product
- it keeps dependency wiring simple in the publish workflow
- it avoids partial-release ambiguity when the CLI, generator core, and runtime evolve together

The publish workflow must fail early if the three package versions diverge.

### Remove The Vendored CLI Packaging Model

Delete the CLI `prepack` and `postpack` vendoring behavior and stop shipping `vendor/openapi-rescript-core`.

Reasoning:

- vendoring created the runtime import mismatch that broke the packaged CLI
- normal package dependencies are easier to reason about and verify
- tarballs should reflect the actual dependency graph instead of carrying hidden copies

After this change, the CLI should resolve `openapi-rescript-core` as a standard package dependency both in the workspace and after publish.

### Rewrite Publish Metadata On The Runner

Keep the committed workspace metadata optimized for local development, then rewrite npm-facing metadata in CI immediately before packing and publishing.

The workflow should rewrite:

- `name`
- `private`
- `publishConfig.registry`
- `repository`
- internal dependency names and versions for published packages

Reasoning:

- local workspace links remain simple
- publish-time metadata can point at the scoped GitHub packages without forcing that shape into every local tool path
- this preserves the current pattern already used by the CLI workflow, but extends it consistently to all three packages

### Verify Tarballs As Publish Artifacts

Tarball verification must be part of the release path for all three packages, not only CLI.

Reasoning:

- the failure mode here was a packaged-artifact failure, not a source-tree failure
- pack-level validation is the right boundary for publish confidence
- `runtime` and `core` deserve the same artifact-level checks as `cli`

The CLI smoke test should validate a packed install that resolves `core` through normal dependencies, not through vendored files or ambient workspace state.

## Expected Behavioral Changes

- `packages/openapi-rescript-cli/package.json` stops vendoring `openapi-rescript-core`
- the publish workflow publishes three packages instead of one
- GitHub Packages installs use the scoped names above
- generated clients can depend on a published `@bushuo/openapi-rescript-runtime`
- local development remains `pnpm install`, `pnpm build`, and `pnpm test` in the existing monorepo

## Non-Goals

- changing the ReScript package names in `rescript.json`
- changing the runtime API, generator API, or CLI behavior beyond packaging and publish wiring
- switching away from GitHub Packages
- introducing independent package versioning
- changing the generated client surface except for documented runtime installation requirements
