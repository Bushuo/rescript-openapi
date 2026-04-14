# Published Runtime Compile Regression Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a publish-path end-to-end regression test that stages and packs the packages exactly like CI, installs them into a temporary consumer app, and verifies the generated client compiles.

**Architecture:** Reuse the existing publish staging script to create publishable package directories, pack them into tarballs with `npm pack`, then install those tarballs into a temporary ReScript app that generates a client from a known-good fixture and runs `rescript build`. Fix the published runtime package metadata only after the regression test fails and proves the current artifact shape is broken.

**Tech Stack:** Node.js, Vitest, npm pack, ReScript, existing publish staging script

---

### Task 1: Add the failing publish-path e2e test

**Files:**
- Create: `test/publish/installPublishedPackage.test.mjs`
- Test: `test/publish/installPublishedPackage.test.mjs`

- [ ] **Step 1: Write the failing test**

Create a Vitest test that:
- stages `runtime`, `core`, and `cli` with `scripts/publish/stage-github-package.mjs`
- packs each staged directory with `npm pack`
- creates a temporary consumer app with `package.json`, `rescript.json`, `src/Demo.res`, and a copied OpenAPI spec fixture
- installs the packed tarballs plus `rescript`
- runs the installed CLI to generate a client into `src/generated`
- runs `npx rescript build`
- asserts the build succeeds with empty stderr

- [ ] **Step 2: Run the new test to verify it fails**

Run: `pnpm exec vitest run test/publish/installPublishedPackage.test.mjs`
Expected: FAIL with a published-install compile error that reproduces the runtime `Client` collision

### Task 2: Fix the published runtime metadata

**Files:**
- Modify: `packages/openapi-rescript-runtime/rescript.json`

- [ ] **Step 1: Write the minimal fix**

Update the runtime ReScript config so the published runtime keeps a stable namespace during consumer installs and no longer collides with generated `Client.res`.

- [ ] **Step 2: Run the focused test to verify it passes**

Run: `pnpm exec vitest run test/publish/installPublishedPackage.test.mjs`
Expected: PASS

### Task 3: Verify publish packaging still works

**Files:**
- Modify: `test/publish/stageGithubPackage.test.mjs`

- [ ] **Step 1: Add or update assertions for the staged runtime ReScript config**

Make the package staging tests assert the runtime config keeps the namespace property expected by the published install path.

- [ ] **Step 2: Run focused verification**

Run: `pnpm exec vitest run test/publish/*.test.mjs`
Expected: PASS

- [ ] **Step 3: Run broader verification**

Run: `pnpm test`
Expected: PASS
