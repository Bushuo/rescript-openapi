# OneOf Support: Design

Date: 2026-04-05

## Goal

Add support for a statically safe subset of OpenAPI 3.1 `oneOf` schemas without weakening the generator's strict failure model.

The design should:

- support `null | T` unions in OpenAPI 3.1
- support discriminated object unions when branch selection is provably safe at generation time
- lower supported `oneOf` inputs into explicit IR nodes rather than carrying generic `oneOf` through codegen
- keep failure behavior precise for unsupported or ambiguous union shapes

## Non-Goals

- support OpenAPI 3.0 `nullable: true`
- support general `oneOf` runtime branch matching
- support non-discriminated object unions
- support scalar unions such as `string | integer`
- support `anyOf` or `allOf` as part of this change
- support arbitrary JSON Schema composition nested inside supported `oneOf` branches
- support discriminator mappings or other advanced discriminator features in v1

## User-Facing Behavior

### Supported OpenAPI Version Scope

This feature targets OpenAPI 3.1 only.

The generator should interpret nullability through JSON Schema shapes that are valid in OpenAPI 3.1. It should not accept the OpenAPI 3.0-specific `nullable` keyword.

### Supported OneOf Shapes

The generator should accept exactly two categories of `oneOf`.

#### 1. Null Union

Accepted forms:

- `oneOf` with exactly one `type: "null"` branch
- the remaining branches must collectively decode as one supported non-null shape

Representative example:

```yaml
oneOf:
  - type: "null"
  - $ref: "#/components/schemas/AlcoholHabitsDto"
```

Nullable discriminated unions are also supported when the non-null branches form a supported discriminated object union:

```yaml
oneOf:
  - type: object
    required: [kind]
    properties:
      kind:
        type: string
        enum: ["Male"]
  - type: object
    required: [kind]
    properties:
      kind:
        type: string
        enum: ["Female"]
  - type: "null"
```

This should lower to `Nullable(nonNullSchema)` in IR and generate a nullable ReScript type, where `nonNullSchema` may itself be a discriminated union.

For CLI-driven generation, local `$ref` values are normally resolved before the core generator sees the schema. If the core still encounters a non-null `$ref` branch in this position, it should preserve the existing `NamedRef` behavior rather than trying to re-resolve the reference based on downstream shape analysis.

### 2. Discriminated Object Union

Accepted form:

- `oneOf` whose branches all decode into the existing supported object subset
- every branch has the same required discriminator property name
- each branch constrains that discriminator to exactly one unique string literal value
- that literal is expressed by either `const: "Tag"` or `enum: ["Tag"]`
- discriminator detection is structural only; the OpenAPI `discriminator` keyword is not part of the supported surface in this change
- the discriminator property schema itself must be inline; `$ref` is not allowed for the discriminator property in v1

Representative example:

```yaml
oneOf:
  - type: object
    required: [kind]
    properties:
      kind:
        type: string
        enum: ["Male"]
  - type: object
    required: [kind, value]
    properties:
      kind:
        type: string
        enum: ["Female"]
      value:
        $ref: "#/components/schemas/PregnancyStatusDto"
  - type: object
    required: [kind]
    properties:
      kind:
        type: string
        enum: ["PreferNotToSay"]
```

This should lower to a first-class discriminated union IR node and generate a ReScript variant.

## Support Matrix

### Accept

- `oneOf` with exactly one `null` branch and one supported non-null shape
- `oneOf` of object branches with a shared required discriminator field
- nullable discriminated unions, where the non-null branches form a supported discriminated object union
- discriminator literals expressed with `const`
- discriminator literals expressed with single-value string enums
- branches that use `$ref` within otherwise supported object fields

### Reject

- `oneOf` with more than one `null` branch
- `oneOf` with one `null` branch plus remaining branches that do not form a single supported non-null shape
- `oneOf` with scalar branches
- `oneOf` with array branches
- `oneOf` with mixed object and scalar branches except the `null | T` special case
- `oneOf` where a branch omits the discriminator field
- `oneOf` where the discriminator field is optional in any branch
- `oneOf` where discriminator values are duplicated across branches
- `oneOf` where discriminator values are not a single string literal
- `oneOf` that relies on the OpenAPI `discriminator` keyword for acceptance
- `oneOf` where the discriminator property schema is a `$ref`
- `oneOf` where branch selection would require trying multiple schemas at runtime
- `oneOf` that contains unsupported nested constructs such as `anyOf`, `allOf`, `not`, `if`, `then`, or `else`
- OpenAPI 3.0 `nullable`
- top-level `type: ["null", "..."]` unions as part of this change

The design is intentionally narrower than full JSON Schema `oneOf`. The generator should reject any `oneOf` shape that cannot be proven safe from static structure alone.

## Generated Output

### Nullable

Supported null unions should generate a nullable model type.

Representative target shape:

```rescript
type alcoholHabitsDto = option<Models.alcoholHabitsDto>
```

The exact codegen surface may use a dedicated runtime helper or the existing option support in Sury, but the generated model type should behave as a nullable value rather than a two-case custom variant.

When the wrapped schema is a discriminated union, nullability should wrap the union rather than becoming a separate constructor.

Representative target shape:

```rescript
type genderDto = option<Models.genderDto_nonNull>
```

The exact naming can vary, but the design intent is `Nullable(DiscriminatedUnion(...))`, not a bespoke `Null | Male | Female` variant.

### Discriminated Unions

Supported discriminated object unions should generate a top-level variant type.

Representative target shape:

```rescript
type genderDto =
  | Male
  | Female({value: Models.pregnancyStatusDto})
  | PreferNotToSay
```

Case payload rules:

- branches with only the discriminator field become nullary constructors
- branches with additional required or optional fields become payload constructors
- the discriminator field itself should not be duplicated in the payload record unless a later design explicitly chooses to preserve it

The generated schema binding must decode and encode using the discriminator field.

## Internal Design

### IR Changes

The schema IR in [Ir.res](/Users/paulb/Projects/rescript-openapi/packages/openapi-rescript-core/src/Ir.res) should gain dedicated nodes for the supported `oneOf` subset.

Representative shape:

```rescript
type rec schema =
  | Scalar(string)
  | StringEnum({name: string, values: array<string>, path: array<string>})
  | Array(schema)
  | Object(array<objectField>)
  | NamedRef(string)
  | Nullable(schema)
  | DiscriminatedUnion({
      discriminator: string,
      cases: array<unionCase>,
    })

and unionCase = {
  tag: string,
  schema: schema,
}
```

Important constraints:

- `Nullable` should be explicit in IR rather than represented as a scalar plus side metadata
- `DiscriminatedUnion` should be explicit in IR rather than carrying a generic `oneOf`
- decode should only construct these nodes after proving the source shape is safe

### Why Not A Generic OneOf Node

A generic `OneOf(array<schema>)` IR node would preserve more source structure, but it would defer ambiguity into codegen and runtime behavior.

That is the wrong trade-off for this generator. The current design prefers early rejection of unsupported schema constructs. A dedicated IR node per safe shape keeps that boundary intact.

## Decode Pipeline

### SchemaDecode Changes

`SchemaDecode.decodeObject` in [SchemaDecode.res](/Users/paulb/Projects/rescript-openapi/packages/openapi-rescript-core/src/SchemaDecode.res) should stop rejecting `oneOf` unconditionally.

Instead:

1. If `oneOf` is present, call a dedicated `decodeOneOf` helper.
2. `decodeOneOf` should try the supported cases in a fixed order:
   - `decodeNullableOneOf`
   - `decodeDiscriminatedUnion`
3. If neither helper succeeds, fail with a precise diagnostic at the `oneOf` path.

### Null Union Detection

`decodeNullableOneOf` should:

- require exactly one branch to be `type: "null"`
- collect the remaining non-null branches
- decode the remaining branches as one supported non-null shape
- if the remaining set has one branch, decode it with the existing schema decoder
- if the remaining set has multiple branches, allow it only if it decodes as a supported discriminated union
- reject nested unsupported constructs inside the non-null shape as usual

The output should be `Ir.Nullable(innerSchema)`.

This keeps nullability compositional: the wrapped schema may be a plain supported schema or a supported discriminated union.

If the remaining non-null shape is a `$ref` that still reaches core decode, the output should be `Ir.Nullable(Ir.NamedRef(...))`. The decoder should not attempt to inspect what that reference may resolve to later.

### Discriminated Union Detection

`decodeDiscriminatedUnion` should:

- require at least two branches
- require each branch to decode as a supported object schema
- inspect each branch before lowering to ensure the discriminator property:
  - exists in `properties`
  - is listed in `required`
  - is inline rather than a `$ref`
  - is constrained by `const` or a single-value string enum
- require all branches to use the same discriminator property name
- require discriminator values to be unique strings

The OpenAPI `discriminator` keyword should remain unsupported for this first pass. Branch acceptance should come entirely from structural detection of the branch-local discriminator property.

For each accepted branch:

- decode the branch into object schema form
- remove the discriminator field from the case payload schema after capturing its literal tag
- store the case as `{tag, schema}`

Removing the discriminator field from the payload keeps the generated variant ergonomic and avoids duplicating information that is already expressed by the constructor choice.

### Const Handling

The decoder currently rejects `const` globally.

This change should narrow that behavior:

- allow `const` only in the exact branch-local position needed to recognize discriminator literals
- continue rejecting all other `const` usage

This keeps the feature surface small while avoiding a broader commitment to arbitrary constant-valued schemas.

## Codegen Changes

### Printer

[Printer.res](/Users/paulb/Projects/rescript-openapi/packages/openapi-rescript-core/src/Codegen/Printer.res) should gain rendering support for:

- `Nullable(schema)` in `modelType`
- `Nullable(schema)` in `schemaExpr`
- `DiscriminatedUnion` in `modelType`
- `DiscriminatedUnion` schema helper references in `schemaExpr`

The exact formatting can vary, but printer logic should no longer treat these as unsupported fallbacks.

### Dependency Traversal And Ordering

Every helper that walks `Ir.schema` must learn the new nodes.

In particular:

- [EmitSchemas.res](/Users/paulb/Projects/rescript-openapi/packages/openapi-rescript-core/src/Codegen/EmitSchemas.res) `collectNamedSchemaDependencies` must recurse through `Nullable`
- [EmitSchemas.res](/Users/paulb/Projects/rescript-openapi/packages/openapi-rescript-core/src/Codegen/EmitSchemas.res) `collectNamedSchemaDependencies` must recurse through every discriminated-union case payload schema
- [EmitSchemas.res](/Users/paulb/Projects/rescript-openapi/packages/openapi-rescript-core/src/Codegen/EmitSchemas.res) `orderSchemas` must continue to use those collected dependencies so named refs reachable through union payloads are emitted in a valid order
- any future `Ir.schema` walker added during implementation should treat missing `Nullable` or `DiscriminatedUnion` handling as a bug, not a fallback case

This is required so a discriminated union case that carries a named schema payload still emits after its dependencies and does not silently miss dependency edges.

### Models

[EmitModels.res](/Users/paulb/Projects/rescript-openapi/packages/openapi-rescript-core/src/Codegen/EmitModels.res) should:

- render `Nullable(inner)` as `option<...>`
- render named discriminated unions as top-level variants
- derive constructor names from discriminator string literals using the existing naming normalization rules
- fail generation if two discriminator values normalize to the same constructor name

Payload shaping for union cases:

- if the branch object has no fields beyond the discriminator, emit a nullary constructor
- otherwise emit a constructor with a record payload containing the remaining fields

### Schemas

[EmitSchemas.res](/Users/paulb/Projects/rescript-openapi/packages/openapi-rescript-core/src/Codegen/EmitSchemas.res) should:

- render `Nullable(inner)` using an option-capable schema expression
- render discriminated unions with custom decode and encode logic keyed on the discriminator field

Representative schema behavior:

- decode JSON objects by first reading the discriminator field
- dispatch to the matching branch schema
- produce a precise decode failure for missing or unknown discriminator values
- encode a constructor by writing its discriminator value plus any payload fields

The schema emitter will likely need a generated helper expression rather than a single primitive runtime combinator, because union encoding and decoding requires object-level branching.

## Runtime Support

The existing runtime in [Schema.res](/Users/paulb/Projects/rescript-openapi/packages/openapi-rescript-runtime/src/Schema.res) already supports:

- string-backed custom codecs via `stringMapped`
- optional object fields via `S.option` inside `object_`

This change should avoid new runtime helpers unless they clearly reduce generated complexity.

Likely requirements:

- nullable schemas can probably reuse existing option support from Sury
- discriminated unions may need either:
  - a new runtime helper for object-dispatch unions, or
  - generated inline transform logic in `Schemas.res`

Recommendation:

- keep `Nullable` runtime handling minimal
- prefer generated schema logic first for discriminated unions
- add a runtime helper only if the generated code becomes repetitive or unreadable

## Naming

Type names for named component schemas should continue to come from the existing schema naming flow.

For discriminated union constructors:

- use the discriminator literal value as the source name
- normalize through the existing enum-constructor naming rules, including the same reserved-name validation behavior
- fail if normalization causes collisions

Examples:

- `"Male"` -> `Male`
- `"PreferNotToSay"` -> `PreferNotToSay`
- `"prefer_not_to_say"` -> `PreferNotToSay`

## Diagnostics

Failure messages should remain precise and point to the offending path.

Important failure cases:

- unsupported `oneOf` shape
- nullable `oneOf` with more than one `null` branch
- nullable `oneOf` whose remaining branches do not form a supported non-null shape
- discriminated union branch missing discriminator field
- discriminator field not required
- discriminator literal not a single string
- duplicated discriminator values
- constructor naming collision after normalization
- unsupported nested composition inside a `oneOf` branch

Representative diagnostic messages:

- `Unsupported schema construct: oneOf`
- `Unsupported oneOf shape: expected null union or discriminated object union`
- `Unsupported oneOf shape: expected exactly one null branch plus one supported non-null shape`
- `Invalid discriminated union: discriminator field "kind" must be required in every branch`
- `Invalid discriminated union: duplicate discriminator value "Male"`

The message text can differ, but the diagnostics should make the rejection cause obvious enough that the spec author can fix the source schema.

## Testing Strategy

Add tests at four layers.

### Core Decode Tests

- accepts `oneOf` null unions
- accepts nullable discriminated unions
- rejects `oneOf` with more than one `null` branch
- rejects nullable `oneOf` whose non-null branches do not form a supported shape
- accepts discriminated unions with `enum: ["Tag"]`
- accepts discriminated unions with `const: "Tag"`
- rejects branches missing the discriminator
- rejects duplicated discriminator tags
- rejects scalar `oneOf`
- rejects mixed-shape `oneOf`

### Printer And Codegen Tests

- renders nullable component schemas as `option<...>`
- renders discriminated unions as variants
- renders payload cases without duplicating the discriminator field
- rejects constructor naming collisions

### Golden Tests

- component schema using `oneOf: [null, $ref]`
- component schema using discriminated object union
- response body or nested property using supported `oneOf`
- unsupported scalar `oneOf` fixture still fails with a precise diagnostic

### Runtime Tests

- nullable decode accepts `null` and non-null payloads
- discriminated union decode selects the correct branch from the discriminator field
- decode fails for missing discriminator
- decode fails for unknown discriminator
- encode writes the discriminator field back out correctly

## Implementation Notes

This design is intentionally limited to shapes that can be represented without runtime schema backtracking.

That keeps implementation aligned with the generator's current principles:

- strict failure over lossy fallback
- explicit IR over side metadata
- generated output that is idiomatic ReScript rather than a direct JSON Schema mirror
