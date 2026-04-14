# Component Ref Preservation Design

## Problem

The CLI currently resolves all `$ref` entries eagerly. That erases same-document component schema identity before `openapi-rescript-core` decodes the schema tree.

For schemas that reuse component enums through wrappers such as `oneOf` nullable refs, core sees the referenced schema as an anonymous inline enum and lifts it again under a usage-specific name. In the Hybit schema this produces duplicates such as:

- `alcoholHabitsDto`
- `getProfileHttpResponseBodyAlcoholHabits`
- `getMeResponse200AlcoholHabits`

Those duplicate generated variant types are runtime-compatible but not type-equal in ReScript, which causes inference failures when shared schemas are expected to reuse the same component type.

## Goal

Preserve identity for same-document `#/components/schemas/*` refs so generated model and schema code reuses top-level component types instead of generating usage-local duplicates.

## Non-Goals

- Structural deduplication of identical inline schemas
- Preserving identity for non-schema component refs
- Changing external file ref resolution behavior
- Refactoring codegen naming outside the component-ref case

## Approach

Use approach 1: preserve local component schema refs during CLI ref resolution.

When the resolver encounters a `$ref` that points to `#/components/schemas/<Name>` in the current file, it should keep the `$ref` entry intact instead of replacing it with the resolved target JSON. Other refs should continue to resolve as they do today.

That keeps component identity available to `SchemaDecode.decodeRef`, which already maps `$ref` values to `Ir.NamedRef`. Once the decoder sees named refs again, existing printers and emitters reuse the shared component type/schema definitions automatically.

## Expected Effect

For Hybit:

- `GetProfileHttpResponseBody` remains a named component schema
- `alcoholHabits` inside it decodes as `Nullable(NamedRef("#/components/schemas/AlcoholHabitsDto"))`
- generated code reuses `Models.alcoholHabitsDto` and `Schemas.alcoholHabitsDto`
- usage-local duplicates such as `getProfileHttpResponseBodyAlcoholHabits` are no longer emitted for component-backed enums

## Implementation Notes

- The smallest safe change is in `packages/openapi-rescript-cli/src/ResolveRefs.res`
- Preserve the raw `$ref` object only when:
  - the ref is same-document
  - the fragment targets `#/components/schemas/`
- Keep current merge behavior for refs with sibling fields outside that narrow case
- Add a regression test that exercises a nullable `oneOf` around a component enum ref and asserts the generated files reuse the component type name

## Risks

- Same-document component object refs will also stay named, which changes some generated anonymous operation result aliases into shared component refs. That is desirable for this bug class and stays within the explicit “component refs only” rule.
- If a schema illegally combines a preserved component `$ref` with sibling keywords, the current decoder will still reject or mishandle it according to existing rules. This change does not try to normalize invalid schemas.
