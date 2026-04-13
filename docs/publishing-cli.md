# Publishing the CLI to GitHub Packages

## Versioning

The source of truth for the published version is `packages/openapi-rescript-cli/package.json`.

- bump `version` in git before you publish
- push the commit you want to release
- run the workflow against that branch or commit

If you try to publish the same version twice, GitHub Packages will reject it.

## Manual Publish Workflow

The repository includes a manual workflow at `.github/workflows/publish-cli.yml`.

When you run `Publish CLI to GitHub Packages`, it will:

1. install dependencies
2. run the workspace test suite
3. rewrite the CLI package metadata for GitHub Packages on the runner
4. verify the publish tarball with `pnpm pack --filter openapi-rescript-cli --dry-run`
5. publish the CLI package with the version already committed in git

The published package name is derived from the repository owner at runtime:

```text
@<repository-owner>/openapi-rescript-cli
```

That keeps the workspace package names unchanged in the repo while still satisfying GitHub Packages' scoped-package requirement.

## Installing From Another Private Repository

In the consuming repository, add an `.npmrc` file with the GitHub Packages scope mapping:

```ini
@OWNER:registry=https://npm.pkg.github.com
```

Then authenticate:

- use `GITHUB_TOKEN` if that repository has been granted read access to the package
- otherwise use a classic personal access token with `read:packages`

Install the CLI with:

```bash
pnpm add -D @OWNER/openapi-rescript-cli
```
