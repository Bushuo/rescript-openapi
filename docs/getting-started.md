# Getting Started

## Workspace Layout

This repository is a `pnpm` workspace with three packages:

- `packages/openapi-rescript-cli` loads OpenAPI documents, parses YAML or JSON, resolves local file `$ref`s, and hands a normalized document to the generator
- `packages/openapi-rescript-core` contains the ReScript generator logic
- `packages/openapi-rescript-runtime` contains the runtime that generated clients import

The generator CLI is not exposed through a root `pnpm exec` command in this repository. Use the repository-local entrypoint directly:

```bash
node packages/openapi-rescript-cli/bin/openapi-rescript.mjs [--enum-mode=open|closed] [--config=<path>] <spec-file> [output-dir]
```

## Install

Use Node.js 24 (as in CI) and pnpm 10.33.0. Vitest 5 requires Node.js `^22.12.0 || ^24.0.0 || >=26.0.0`.

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

Use `--config=<path>` when OpenAPI string formats should map to domain types instead of plain `string`. Config scalar keys are `<type>:<format>`; currently only `string:<format>` is supported.

```json
{
  "scalars": {
    "string:uuid": {
      "type": "Hybit.Id.t",
      "module": "ApiScalars.Uuid"
    }
  }
}
```

The generated code will use `Hybit.Id.t` in models and `ApiScalars.Uuid.schema` in schemas. Implement that converter module with the runtime scalar functor:

```rescript
module Uuid = OpenapiRescriptRuntime.Scalar.MakeString({
  type t = Hybit.Id.t

  let decode = raw =>
    switch Hybit.Id.fromString(raw) {
    | Some(id) => Ok(id)
    | None => Error("Invalid UUID")
    }

  let encode = Hybit.Id.toString
})
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
pnpm test
```

## Generated Client Dependencies

Generated clients import the shared runtime package and its schema/HTTP dependencies. In a consuming project, install the published GitHub Packages runtime:

- `@bushuo/openapi-rescript-runtime`
- `@glennsl/rescript-fetch`
- `sury@11.1.0`

`@rescript/runtime` is a required peer dependency (`^12.2.0`), supplied by the consuming project. `rescript` is an optional peer dependency (`12.x`), needed when compiling ReScript sources. Install the JavaScript runtime explicitly alongside the client runtime:

```bash
pnpm add @bushuo/openapi-rescript-runtime @rescript/runtime@^12.2.0
```

The compiler peer accepts any stable ReScript 12 release; only the JavaScript runtime must be at least 12.2.0. Runtime releases 12.0.0 through 12.1.0 fail to load the packaged CommonJS CLI because their CommonJS `.js` files are treated as ES modules. Upgrading the runtime does not require upgrading the compiler.

Packaged-consumer tests cover compiler/runtime pairs 12.0.0/12.2.0, 12.2.0/12.2.0, and 12.3.1/12.3.1, and check that installation preserves both pinned versions.

Inside this repository, the corresponding workspace package is still named `openapi-rescript-runtime`.

## Operation Errors

Generated operation calls return a result whose error is a polymorphic variant row:

```rescript
promise<result<response, Client.operationErrorOpen<'error>>>
```

The closed base alias is available as `Client.operationError` so application functions can collect generated errors with domain errors:

```rescript
type appError = [
  | Client.operationError
  | #domain(string)
]

let loadPets = async (client: Client.t): result<array<Models.pet>, appError> => {
  switch await Pets.listPets(client, {limit: None}) {
  | Ok(pets) => Ok(pets)
  | Error(error) => Error(error)
  }
}
```

Available generated/runtime error cases are `#transport`, `#requestEncoding`, `#unexpectedStatus`, and `#responseDecode`.

## Supported Subset

V1 supports a strict subset of OpenAPI 3.1:

- OpenAPI `3.1.x`
- YAML or JSON input
- local file `$ref`s only
- tags, operations, parameters, request bodies, JSON responses, status codes, and security declarations
- JSON media types only, including `application/json` and `application/*+json`
- auth support limited to `apiKey` in header/query/cookie plus `http` basic and bearer schemes
- string enums in both default open mode and `--enum-mode=closed`
- configurable `string:<format>` scalar mappings through `--config=<path>`
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
