# ReScript Monorepo Structure: Design

Date: 2026-03-29

## Goal

Adopt the ReScript 12 monorepo layout described in the official manual while preserving the current workspace package boundaries:

- `openapi-rescript-core`
- `openapi-rescript-runtime`
- `openapi-rescript-cli`

This iteration is structural only. The CLI implementation remains in JavaScript except for its existing tiny bin shim, and the follow-up JS-to-ReScript migration will happen later.

## Decisions

### Root ReScript Project

Add a repository-root `rescript.json` that declares the workspace packages as monorepo dependencies. Shared output settings belong at the root so package builds behave consistently:

- `package-specs.module = "commonjs"`
- `package-specs.in-source = true`
- `suffix = ".bs.js"`

### Keep CommonJS For Now

Do not switch to ES modules in this pass.

Reasoning:

- the current core package is consumed through Node package resolution using `require(...)`
- CLI packaging currently vendors and imports compiled `.bs.js` files by path
- changing module format at the same time as the monorepo wiring would couple two migrations and make failures harder to isolate

### Leaf Package Role

Each package keeps its own `rescript.json`, but only for package-local concerns:

- `name`
- `sources`
- `dependencies`

The leaf configs should stop redefining shared output settings that the root monorepo now owns.

### CLI As A Monorepo Member

Add `packages/openapi-rescript-cli/rescript.json` now so the CLI is part of the ReScript project tree even before its source files are converted. Its `src/` directory stays JavaScript-only in this iteration.

## Expected Behavioral Changes

- root `pnpm build` should invoke a root ReScript build instead of recursively building each package in isolation
- `openapi-rescript-core` should stop compiling into `lib/js/...` and instead emit in-source `.bs.js` outputs
- tests and CLI packaging paths that assume `core/lib/js/...` must be updated to the new in-source location

## Non-Goals

- converting CLI implementation modules from `.mjs` to `.res`
- changing published package interfaces beyond the compiled file locations needed by this structure change
- switching module output from CommonJS to ES modules
