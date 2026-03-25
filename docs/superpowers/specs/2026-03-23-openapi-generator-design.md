# OpenAPI Generator For ReScript: Design

Date: 2026-03-23

## Goal

Build an OpenAPI client generator for ReScript that:

- targets OpenAPI 3.1
- generates one client module per tag
- uses `@glennsl/rescript-fetch` for HTTP
- uses `sury` `v11.0.0-alpha.4` for schema generation, request validation, and response parsing
- exposes explicit typed errors instead of exception-driven APIs

The generator itself should be implemented in ReScript, with a thin JS-backed CLI/input layer for document loading and `$ref` resolution.

## Non-Goals For V1

- OpenAPI 3.0 support as a separate target
- remote `$ref` resolution
- non-JSON media types
- OAuth flow framework generation
- lossy fallback generation for unsupported schemas
- full package publishing scaffolds
- broad metadata/doc rendering from the source spec

## Product Shape

V1 should produce:

- generated operation modules, grouped by OpenAPI tag
- generated model and schema modules
- a shared runtime dependency used by generated clients

V1 should not try to emit a fully publishable SDK package layout beyond what is required for generated source consumption.

## High-Level Architecture

Use a hybrid architecture with three layers:

1. `openapi-rescript-cli`
   - thin CLI entrypoint
   - accepts JSON and YAML input
   - resolves local file `$ref`s
   - normalizes the document into one OpenAPI 3.1 JSON object
2. `openapi-rescript-core`
   - generator core written in ReScript
   - decodes the normalized document into a strict internal IR
   - fails on unsupported features
   - emits `.res` files
3. `openapi-rescript-runtime`
   - shared ReScript runtime helpers imported by generated code
   - wraps `rescript-fetch`
   - exposes typed error handling and Sury-backed request/response helpers

The JS layer is limited to ingestion concerns. Generator decisions stay in ReScript.

## Supported V1 Input Surface

### OpenAPI

- OpenAPI `3.1.x`
- single-file specs
- multi-file local specs via local `$ref`
- normalized JSON handed to the ReScript core

### Document Features

Support only the core path/operation surface required for client generation:

- tags
- operations
- parameters
- request bodies
- JSON responses
- status codes
- security declarations

Ignore or reject broader metadata outside this core depending on whether it affects code generation correctness.

### Media Types

Support JSON only:

- `application/json`
- `application/*+json`

Any required request or response media type outside this subset should fail generation.

## Generated Output Shape

Generate:

- one module per tag
- `Models.res`
- `Schemas.res`
- `Client.res`
- `Index.res`
- optionally `Errors.res` if separate generated error helpers are warranted

### Operation API

Each operation should expose:

- a single params record
- optional record fields where the schema/parameter is optional
- `promise<result<'ok, operationError>>` as the primary async contract

Representative shape:

```rescript
module Pets = {
  type getPetParams = {
    id: string,
    includeVaccines?: bool,
  }

  let getPet: (client, getPetParams) => promise<result<pet, operationError>>
}
```

## Runtime Behavior

### Request Handling

- request bodies should be validated and encoded through generated Sury schemas before sending
- auth handling should support common generated cases only:
  - `apiKey`
  - `http` bearer
  - `http` basic
  - header/query/cookie injection

### Response Handling

- response bodies should be parsed and validated through generated Sury schemas
- only JSON responses are supported in v1

### Error Contract

Each operation should return a typed error value that distinguishes at least:

- transport errors
- request encoding or validation errors
- unexpected HTTP status
- response decode or parse errors

For non-2xx responses with declared JSON schemas, the runtime should parse typed error payloads where possible.

Exceptions from lower layers should be caught and converted into the typed error contract at the runtime boundary.

## Naming Rules

- use `operationId` when present and unique
- if `operationId` is missing or duplicated, derive a stable name from HTTP method + path
- fail generation if collisions still remain after derivation

Tag names should define the primary generated module grouping.

## Internal IR

The ReScript core should decode into a smaller IR rather than generate directly from raw OpenAPI JSON.

Suggested IR domains:

- document
- operation
- parameter
- request body
- response
- security requirement
- schema
- naming metadata

Suggested schema IR subset:

- scalar
- object
- array
- enum
- nullable
- literal
- union
- intersection
- named reference

Unsupported features should be rejected during decode into IR, before code generation begins.

## Schema Mapping Rules

### Safe Supported Mapping

- closed object schemas map to ReScript records when field structure is clear
- optional properties map to optional record fields
- arrays map to ReScript arrays; generated output should not use ReScript lists
- enums map to variants when representation is stable and safe

### Composition

Support only the subset of composition that can be represented safely:

- `oneOf`
- `anyOf`
- `allOf`
- discriminator-based unions

If a composition construct cannot be mapped cleanly into ReScript + Sury, generation should fail with a precise schema path.

### Strict Failure Rule

When the generator encounters a schema feature that cannot be represented safely, it must fail generation rather than emit weak or lossy fallback types.

## ReScript And Library Targets

- generator core target: ReScript `12+`
- generated client target: ReScript `12+`
- HTTP dependency: `rescript-fetch`
- schema/runtime dependency: `sury` `v11.0.0-alpha.4`

## Testing Strategy

The project should validate three layers independently:

1. ingestion tests
   - CLI accepts JSON and YAML
   - local `$ref` resolution works for multi-file specs
2. IR tests
   - normalized OpenAPI documents decode into the expected internal representation
   - unsupported constructs fail with precise diagnostics
3. codegen/runtime tests
   - generated modules match expected snapshots or golden files
   - request validation and response parsing behave correctly with Sury
   - typed error mapping covers transport, status, and decode failures

V1 should prioritize golden tests for representative specs:

- simple CRUD API
- auth-protected API with bearer/api key
- discriminator-based union schema
- duplicate or missing `operationId`
- unsupported schema feature that must fail generation

## Tooling Decisions

Recommended tools and boundaries:

- JS CLI/input layer for YAML parsing and local `$ref` resolution
- ReScript core for IR building and code generation
- shared runtime package to keep generated output smaller and stable

The core generator should not depend on JS-side business logic beyond receiving the normalized document.

## Approach Options Considered

### 1. JS-First Generator

Fastest ecosystem path, but it weakens the requirement that the generator itself be ReScript.

### 2. Hybrid Generator

JS only for ingestion and resolution, ReScript for IR and codegen. This best matches the desired product boundary and is the selected approach.

### 3. Pure ReScript Generator

Conceptually clean, but too much v1 effort would go into YAML parsing and `$ref` resolution infrastructure.

## Open Questions For Later Phases

- exact generated file layout and naming conventions
- whether enums should always become variants or sometimes remain strings plus validators
- the precise shape of `operationError`
- whether `Errors.res` should exist as a standalone generated module
- how much configurability the CLI should expose beyond input/output paths

## Recommended First Implementation Slice

Build the smallest vertical slice that proves the architecture:

1. CLI accepts one spec file, normalizes JSON/YAML, and resolves local `$ref`
2. ReScript core decodes a limited OpenAPI 3.1 subset into IR
3. generator emits one tag module, `Models.res`, `Schemas.res`, `Client.res`, and `Index.res`
4. runtime executes one JSON request path through `rescript-fetch`
5. Sury validates one request body and one response body end to end

This slice is enough to validate the package boundaries before expanding schema coverage.
