# String Enum Support: Design

Date: 2026-03-25

## Goal

Add support for OpenAPI string enums to the generator without weakening type safety or forward compatibility.

The design should:

- support all reachable `type: string` + `enum: [...]` schemas
- expose enum compatibility behavior as a CLI setting
- default to forward-compatible decoding
- lift inline enums to top-level generated names
- keep room for future support of numeric or other enum shapes

## Non-Goals

- support non-string enums in v1 of this feature
- support mixed-type enum arrays
- support `oneOf` or other composition constructs as part of this change
- add per-enum override extensions in the source OpenAPI document

## User-Facing Behavior

### CLI Surface

Add a CLI flag:

- `--enum-mode=open|closed`

Default:

- `open`

The flag should apply to all generated enums in a run.

### Supported Enum Inputs

Accept only schemas that satisfy all of the following:

- schema has `type: string`
- schema has `enum`
- every `enum` item is a string

Any other `enum` shape remains unsupported and should fail with a precise diagnostic.

### Reach

Support string enums wherever they are reachable by the current supported subset, including:

- named component schemas
- inline object properties
- parameters
- request body schemas
- response body schemas

## Generated Output

### Top-Level Enum Lifting

Every supported string enum should become a top-level generated type and schema binding.

This applies even when the source enum was inline. Inline enums should be lifted into generated names instead of remaining anonymous in parent record types.

Representative examples:

- `components.schemas.SessionStateDto` -> `type sessionStateDto = ...`
- `components.schemas.User.properties.role` -> `type userRole = ...`
- `paths./users.get.parameters.sort` -> `type listUsersSortParam = ...`

### Open Mode

In `open` mode, generated enum models should include an unknown fallback case:

```rescript
type sessionStateDto =
  | Active
  | Completed
  | Closed
  | Unknown(string)
```

Behavior:

- known wire values decode to known constructors
- unknown wire values decode to `Unknown(raw)`
- known constructors encode to their declared wire values
- `Unknown(raw)` encodes back to `raw`

This is the default because it preserves client usability when the server adds enum members before the client is regenerated.

### Closed Mode

In `closed` mode, generated enum models should omit the unknown case:

```rescript
type sessionStateDto =
  | Active
  | Completed
  | Closed
```

Behavior:

- known wire values decode to known constructors
- unknown wire values fail decoding
- known constructors encode to their declared wire values

## Internal Design

### IR Changes

The core schema IR should gain a first-class enum representation for named string enums.

The exact representation can vary, but it must preserve:

- the generated enum name
- the declared wire values
- whether the enum originated from a reusable component or an inline site

Important constraint:

- enums must not be represented as plain `Scalar("string")` with side metadata

Enums need to be explicit in the schema graph so model and schema codegen can treat them as a real type.

### Decode Pipeline

`SchemaDecode` should stop rejecting `enum` only when:

- the schema is explicitly `type: string`
- the enum array exists
- all enum entries are strings

It should continue rejecting:

- `enum` with no string type
- numeric enums
- mixed enums

The enum name should be assigned before printing so the rest of the pipeline works with stable named schemas rather than anonymous special cases.

### Naming

Use deterministic generated names for inline enums.

Rules:

- component schema enums keep their schema name
- inline property enums derive from parent schema name + property name
- parameter enums derive from normalized operation name + `Param` + parameter name
- request and response body enums derive from normalized operation name plus a stable request/response prefix and then the nested property path

Examples:

- `User.role` -> `UserRole`
- `listUsers` query parameter `sort` -> `ListUsersParamSort`
- `createSession` request body property `state` -> `CreateSessionRequestState`
- `getSession` `200` response body property `state` -> `GetSessionResponseState`

If two generated enum names collide after normalization, generation should fail with a precise diagnostic instead of silently renaming one of them.

### Model Codegen

`EmitModels` should generate one top-level variant type for each enum.

Generated constructors should come from the enum string values via the existing naming normalization rules, with collision checks applied at the enum-member level.

Examples:

- `"Active"` -> `Active`
- `"created_at"` -> `CreatedAt`

If two enum values normalize to the same constructor name, generation should fail with a diagnostic pointing at that enum.

### Schema Codegen

`EmitSchemas` should generate a schema binding for each enum that matches the model type.

This requires custom decode and encode logic rather than reusing the bare `string` schema.

Open mode:

- decode known strings to known constructors
- decode unknown strings to `Unknown(raw)`

Closed mode:

- decode known strings to known constructors
- reject unknown strings

For both modes:

- encode known constructors to their declared wire string

### Runtime Support

The runtime schema module currently exposes primitive string/int/float/bool plus array and object composition.

Add a helper for custom string-backed codecs so generated enum schemas can stay declarative.

Representative shape:

```rescript
let stringMapped: (~decode: string => result<'a, string>, ~encode: 'a => string) => t<'a>
```

The exact API can differ, but it must support:

- decoding a raw JSON string into a typed value
- producing a decode failure message for closed enums
- encoding typed enum values back to JSON strings

This helper should be general enough to support future string-backed schema refinements beyond enums.

## Error Handling

Failure cases should remain precise and structured.

Generation-time failures:

- non-string enum
- mixed enum values
- generated enum type name collision
- generated enum constructor collision

Runtime decode failure in closed mode:

- unknown enum string should surface as a response decode or request encoding failure through the existing runtime error contract
- the message should indicate the unexpected enum value and the allowed values

Open mode should not fail on unknown enum values.

## Why Open By Default

Open enum handling is a common SDK compatibility pattern because servers frequently add enum values without treating that as a breaking change.

A closed default would cause older generated clients to start failing response decode for otherwise valid server responses. Open-by-default preserves compatibility while still giving typed access to known values.

Keeping the mode configurable allows consumers with strict contracts to opt into closed decoding without changing the schema model design.

## Testing Strategy

Add tests at four layers.

### Core Decode Tests

- accepts named string enums
- accepts inline string enums
- rejects numeric enums
- rejects mixed enums

### Naming Tests

- generates deterministic names for inline property enums
- generates deterministic names for parameter enums
- rejects enum type name collisions
- rejects enum constructor collisions

### Codegen Tests

- emits top-level enum variants in `Models.res`
- emits schema bindings in `Schemas.res`
- emits `Unknown(string)` in open mode only
- references lifted enum names from parent record types

### Runtime Tests

- open mode decodes known values
- open mode decodes unknown values to `Unknown(raw)`
- open mode re-encodes `Unknown(raw)` unchanged
- closed mode decodes known values
- closed mode rejects unknown values

### CLI And E2E Tests

- default CLI behavior is `--enum-mode=open`
- `--enum-mode=closed` changes generated output and behavior
- the new backend fixture progresses past enum decoding once enum support is implemented

## Implementation Notes

To avoid painting the design into a corner:

- keep enum behavior represented in IR rather than only in printers
- keep mode selection outside individual schema nodes so one generator run stays consistent
- make runtime codec support reusable for future refined string types

This leaves room for later work on:

- numeric enums
- per-schema enum-mode overrides
- `oneOf`-based discriminated unions
