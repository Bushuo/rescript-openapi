# Publishing Packages to GitHub Packages

## Published Package Names

The repository keeps its workspace package names unscoped:

- `openapi-rescript-runtime`
- `openapi-rescript-core`
- `openapi-rescript-cli`

The publish flow rewrites those names for GitHub Packages by lowercasing the repository owner and applying that scope. On this branch, the published package names are:

- `@bushuo/openapi-rescript-runtime`
- `@bushuo/openapi-rescript-core`
- `@bushuo/openapi-rescript-cli`

That keeps local workspace development unchanged while producing valid GitHub Packages names.

## Shared Version Requirement

All three published packages share one release line and one version number.

Before you publish:

1. bump the same `version` in `packages/openapi-rescript-runtime/package.json`
2. bump the same `version` in `packages/openapi-rescript-core/package.json`
3. bump the same `version` in `packages/openapi-rescript-cli/package.json`
4. commit and push the release you want to publish

If any package version differs, the publish workflow fails before packaging starts. If you try to publish a version that already exists, GitHub Packages rejects that package.

## Manual Publish Workflow

The repository includes a manual workflow at `.github/workflows/publish-packages.yml`.

When you run `Publish Packages to GitHub Packages`, it will:

1. install dependencies
2. run `pnpm test`
3. assert that `runtime`, `core`, and `cli` all share the same committed version
4. stage publishable copies of each package with GitHub Packages metadata rewritten on the runner
5. verify each staged tarball with `pnpm pack --dry-run`
6. publish the packages in dependency order: `runtime`, then `core`, then `cli`

The staged publish artifacts rewrite:

- package `name`
- `private`
- `publishConfig.registry`
- `repository`
- internal package dependencies so published packages depend on the scoped GitHub Packages names instead of workspace names

The dependency order matters:

1. `@bushuo/openapi-rescript-runtime` must exist before `@bushuo/openapi-rescript-core` depends on it in published installs
2. `@bushuo/openapi-rescript-core` must exist before `@bushuo/openapi-rescript-cli` depends on it in published installs

## Installing From Another Repository

In the consuming repository, add an `.npmrc` file with the GitHub Packages scope mapping:

```ini
@OWNER:registry=https://npm.pkg.github.com
```

Then authenticate:

- use `GITHUB_TOKEN` if that repository has been granted read access to the package
- otherwise use a classic personal access token with `read:packages`

Install the published packages you need:

```bash
pnpm add @OWNER/openapi-rescript-runtime
pnpm add @OWNER/openapi-rescript-core
pnpm add -D @OWNER/openapi-rescript-cli
```

Typical usage is:

- generated clients depend on `@OWNER/openapi-rescript-runtime`
- direct generator integrations can depend on `@OWNER/openapi-rescript-core`
- CLI consumers install `@OWNER/openapi-rescript-cli` as a dev dependency
