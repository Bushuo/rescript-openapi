# Getting Started

## Workspace Layout

This repository is a `pnpm` workspace with three packages:

- `packages/openapi-rescript-cli` loads OpenAPI documents, parses YAML or JSON, resolves local file `$ref`s, and hands a normalized document to the generator
- `packages/openapi-rescript-core` contains the ReScript generator logic
- `packages/openapi-rescript-runtime` contains the runtime that generated clients import

The generator CLI is not exposed through a root `pnpm exec` command in this repository. Use the repository-local entrypoint directly:

```bash
node packages/openapi-rescript-cli/bin/openapi-rescript.mjs [--enum-mode=open|closed] <spec-file> [output-dir]
```

## Install

```bash
pnpm install
```

## Build

Build the workspace from the repository root:

```bash
pnpm build
```

This compiles the workspace packages and is the command the docs and tests are aligned to.

## Happy Path

Generate the sample Petstore client into a temporary directory:

```bash
mkdir -p ./tmp/petstore-client
node packages/openapi-rescript-cli/bin/openapi-rescript.mjs fixtures/specs/petstore.yaml ./tmp/petstore-client
ls ./tmp/petstore-client
```

String enums are supported. The CLI defaults to `--enum-mode=open`, which preserves forward compatibility by generating an `Unknown(string)` constructor for unrecognized values. Pass `--enum-mode=closed` if you want generated enums to accept only the declared OpenAPI values.

```bash
node packages/openapi-rescript-cli/bin/openapi-rescript.mjs --enum-mode=closed fixtures/specs/petstore.yaml ./tmp/petstore-client
```

Expected output files:

- `Client.res`
- `Index.res`
- `Models.res`
- `Pets.res`
- `Schemas.res`

## Test

Run the workspace test suite with the same arguments used by the repo CI flow:

```bash
pnpm test -- --runInBand
```

## Generated Client Dependencies

Generated clients import the shared runtime package and its schema/HTTP dependencies. In a consuming project, install the published GitHub Packages runtime:

- `@bushuo/openapi-rescript-runtime`
- `@glennsl/rescript-fetch`
- `sury@11.0.0-alpha.4`

Inside this repository, the corresponding workspace package is still named `openapi-rescript-runtime`.

## Supported Subset

V1 supports a strict subset of OpenAPI 3.1:

- OpenAPI `3.1.x`
- YAML or JSON input
- local file `$ref`s only
- tags, operations, parameters, request bodies, JSON responses, status codes, and security declarations
- JSON media types only, including `application/json` and `application/*+json`
- auth support limited to `apiKey` in header/query/cookie plus `http` basic and bearer schemes
- string enums in both default open mode and `--enum-mode=closed`
- nullable values use ReScript nullability types: required nullable fields emit `Null.t<T>`, optional nullable fields emit `Nullable.t<T>`
- a strict `oneOf` subset:
  nullable wrappers with exactly one `null` branch plus one supported non-null schema, and
  structurally safe discriminated object unions with inline literal discriminator values

Unsupported constructs are rejected instead of being approximated.

## Strict Failure Behavior

The generator fails fast when it cannot represent a schema safely.

On failure it:

- exits non-zero
- writes a structured JSON diagnostic to stderr
- does not emit partial generated output

The CLI also writes `.openapi-rescript-generated.json` in the output directory so later runs can track which files were generated and clean up stale artifacts safely.

For example, `fixtures/specs/unsupported-schema.yaml` intentionally fails because it uses an unsupported `oneOf` shape. Scalar unions, ambiguous unions, and other `oneOf` forms outside the supported nullable-wrapper and discriminated-object subset are still rejected.
