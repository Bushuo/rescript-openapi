# Component Ref Preservation Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Preserve same-document component schema `$ref` identity so generated ReScript code reuses shared component model/schema types instead of emitting usage-local duplicates.

**Architecture:** Narrow the change to CLI ref resolution. Keep `#/components/schemas/*` refs intact during normalization so core decoding produces `Ir.NamedRef` for component-backed schemas even when they are wrapped by nullable `oneOf` or embedded in component objects. Prove the behavior with a regression test that checks generated model and schema output.

**Tech Stack:** ReScript 12, Vitest, existing openapi-rescript CLI/core packages

---

### Task 1: Add Regression Coverage

**Files:**
- Modify: `packages/openapi-rescript-cli/test/resolveRefs.test.mjs`
- Test: `packages/openapi-rescript-cli/test/resolveRefs.test.mjs`

- [ ] **Step 1: Write the failing test**

Add a fixture-like inline JSON document with:
- `components.schemas.AlcoholHabitsDto` as a string enum
- `components.schemas.GetProfileHttpResponseBody` with `alcoholHabits: { oneOf: [{type: "null"}, {$ref: "#/components/schemas/AlcoholHabitsDto"}] }`
- a path response referencing `GetProfileHttpResponseBody`

Assert that `resolveRefs` preserves both `$ref` entries instead of inlining them.

- [ ] **Step 2: Run test to verify it fails**

Run: `pnpm vitest run packages/openapi-rescript-cli/test/resolveRefs.test.mjs`
Expected: FAIL because the resolver currently inlines the component refs.

- [ ] **Step 3: Write minimal implementation**

Update `packages/openapi-rescript-cli/src/ResolveRefs.res` so same-document `#/components/schemas/*` refs are returned unchanged from `resolveNode`.

- [ ] **Step 4: Run test to verify it passes**

Run: `pnpm vitest run packages/openapi-rescript-cli/test/resolveRefs.test.mjs`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add packages/openapi-rescript-cli/src/ResolveRefs.res packages/openapi-rescript-cli/test/resolveRefs.test.mjs
git commit -m "fix: preserve component schema refs during resolution"
```

### Task 2: Prove Codegen Reuses Component Types

**Files:**
- Modify: `packages/openapi-rescript-core/test/codegen.test.mjs`
- Test: `packages/openapi-rescript-core/test/codegen.test.mjs`

- [ ] **Step 1: Write the failing test**

Add a generator regression fixture with:
- a component enum `AlcoholHabitsDto`
- a component object `GetProfileHttpResponseBody` referencing that enum through nullable `oneOf`
- a response referencing `GetProfileHttpResponseBody`

Assert:
- `Models.res` contains `type alcoholHabitsDto =`
- `Models.res` does not contain `type getProfileHttpResponseBodyAlcoholHabits =`
- `Models.res` uses `alcoholHabitsDto` inside `getProfileHttpResponseBody`
- `Schemas.res` uses `nullableAsOption(alcoholHabitsDto)` inside `getProfileHttpResponseBody`

- [ ] **Step 2: Run test to verify it fails**

Run: `pnpm vitest run packages/openapi-rescript-core/test/codegen.test.mjs`
Expected: FAIL because current normalized input loses component identity.

- [ ] **Step 3: Write minimal implementation**

No extra core change should be necessary if resolver preservation is correct. Adjust only if a decoder/codegen assumption still forces relifting.

- [ ] **Step 4: Run test to verify it passes**

Run: `pnpm vitest run packages/openapi-rescript-core/test/codegen.test.mjs`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add packages/openapi-rescript-core/test/codegen.test.mjs
git commit -m "test: cover component-backed enum reuse"
```

### Task 3: Full Verification

**Files:**
- Modify: none unless failures require follow-up
- Test: workspace test suites

- [ ] **Step 1: Run targeted verification**

Run:
- `pnpm vitest run packages/openapi-rescript-cli/test/resolveRefs.test.mjs`
- `pnpm vitest run packages/openapi-rescript-core/test/codegen.test.mjs`

Expected: PASS

- [ ] **Step 2: Run broader regression suite**

Run: `pnpm test`
Expected: PASS

- [ ] **Step 3: Spot-check Hybit output**

Run the CLI against `/Users/paulb/Projects/work/hybit/apps/backend/api-docs/openapi.json` into a temp directory and confirm usage-local duplicates for `AlcoholHabitsDto` are gone.

- [ ] **Step 4: Commit**

```bash
git add -A
git commit -m "fix: preserve component schema identities"
```
