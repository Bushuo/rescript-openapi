import {describe, expect, it} from "vitest"
import {mkdtempSync, readFileSync, readdirSync, rmSync} from "node:fs"
import {spawnSync} from "node:child_process"
import {tmpdir} from "node:os"
import {join, resolve} from "node:path"

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
