# rescript-openapi

Workspace for the OpenAPI-to-ReScript generator.

## Workspace

- `packages/openapi-rescript-cli`: thin Node CLI for loading specs, resolving local `$ref`s, and invoking the generator
- `packages/openapi-rescript-core`: ReScript generator core
- `packages/openapi-rescript-runtime`: shared runtime used by generated clients

## Quick Start

See [docs/getting-started.md](docs/getting-started.md) for the full local workflow.

The repository-local generator entrypoint is:

```bash
node packages/openapi-rescript-cli/bin/openapi-rescript.mjs fixtures/specs/petstore.yaml ./tmp/petstore-client
```

Generated clients depend on:

- `openapi-rescript-runtime`
- `@glennsl/rescript-fetch`
- `sury@11.0.0-alpha.4`
