import {describe, expect, it} from "vitest"
import {existsSync, mkdtempSync, readFileSync, readdirSync, rmSync, writeFileSync} from "node:fs"
import {spawnSync} from "node:child_process"
import {tmpdir} from "node:os"
import {basename, join, resolve} from "node:path"

function runCli(specPath, targetDir) {
  const cliPath = resolve("packages/openapi-rescript-cli/bin/openapi-rescript.mjs")
  const result = spawnSync("node", [cliPath, specPath, targetDir], {
    encoding: "utf8",
  })

  return {
    exitCode: result.status ?? 1,
    stdout: result.stdout ?? "",
    stderr: result.stderr ?? "",
  }
}

describe("generateClient", () => {
  it("generates the petstore client files from a YAML spec", () => {
    const targetDir = mkdtempSync(join(tmpdir(), "openapi-rescript-e2e-"))

    try {
      const result = runCli(resolve("fixtures/specs/petstore.yaml"), targetDir)

      expect(result.exitCode).toBe(0)
      expect(result.stderr).toBe("")
      expect(readdirSync(targetDir)).toEqual(
        expect.arrayContaining(["Client.res", "Index.res", "Models.res", "Pets.res", "Schemas.res"])
      )
      expect(readFileSync(join(targetDir, "Pets.res"), "utf8")).toContain("let listPets =")
    } finally {
      rmSync(targetDir, {recursive: true, force: true})
    }
  })

  it("removes stale generated files but preserves unrelated files", () => {
    const targetDir = mkdtempSync(join(tmpdir(), "openapi-rescript-e2e-"))
    const firstSpec = resolve("fixtures/specs/petstore.yaml")
    const secondSpec = join(targetDir, "minimal.yaml")

    try {
      const first = runCli(firstSpec, targetDir)

      expect(first.exitCode).toBe(0)

      writeFileSync(secondSpec, [
        "openapi: 3.1.0",
        "info:",
        "  title: Minimal",
        "  version: 1.0.0",
        "paths: {}",
        "",
      ].join("\n"))
      writeFileSync(join(targetDir, "keep.txt"), "keep me\n")

      const second = runCli(secondSpec, targetDir)

      expect(second.exitCode).toBe(0)
      expect(readdirSync(targetDir)).not.toContain("Pets.res")
      expect(readdirSync(targetDir)).toContain("keep.txt")
      expect(readdirSync(targetDir)).toContain("minimal.yaml")
    } finally {
      rmSync(targetDir, {recursive: true, force: true})
    }
  })

  it("ignores unsafe manifest entries outside the target directory", () => {
    const targetDir = mkdtempSync(join(tmpdir(), "openapi-rescript-e2e-"))
    const outsideFile = join(tmpdir(), `openapi-rescript-outside-${Date.now()}.txt`)

    try {
      writeFileSync(outsideFile, "keep\n")
      writeFileSync(join(targetDir, ".openapi-rescript-generated.json"), JSON.stringify([`../${basename(outsideFile)}`]))

      const result = runCli(resolve("fixtures/specs/petstore.yaml"), targetDir)

      expect(result.exitCode).toBe(0)
      expect(existsSync(outsideFile)).toBe(true)
    } finally {
      rmSync(targetDir, {recursive: true, force: true})
      rmSync(outsideFile, {force: true})
    }
  })

  it("rejects unsupported schemas with a structured diagnostic", () => {
    const targetDir = mkdtempSync(join(tmpdir(), "openapi-rescript-e2e-"))

    try {
      const result = runCli(resolve("fixtures/specs/unsupported-schema.yaml"), targetDir)

      expect(result.exitCode).toBe(1)
      expect(result.stdout).toBe("")
      expect(JSON.parse(result.stderr)).toMatchObject({
        path: ["components", "schemas", "WeirdType", "oneOf"],
        message: "Unsupported schema construct: oneOf",
      })
      expect(readdirSync(targetDir)).toEqual([])
    } finally {
      rmSync(targetDir, {recursive: true, force: true})
    }
  })
})
