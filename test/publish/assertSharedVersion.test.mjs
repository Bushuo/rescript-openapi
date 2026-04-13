import {spawnSync} from "node:child_process"
import {mkdirSync, mkdtempSync, rmSync, writeFileSync} from "node:fs"
import {tmpdir} from "node:os"
import {join, resolve} from "node:path"
import {describe, expect, it} from "vitest"

const scriptPath = resolve("scripts/publish/assert-shared-version.mjs")

function writeManifest(rootDir, packageName, version) {
  const packageDir = join(rootDir, packageName)
  const manifestPath = join(packageDir, "package.json")

  mkdirSync(packageDir, {recursive: true})
  writeFileSync(
    manifestPath,
    JSON.stringify(
      {
        name: packageName,
        version,
      },
      null,
      2
    )
  )

  return manifestPath
}

function runAssertSharedVersion(manifestPaths) {
  const result = spawnSync("node", [scriptPath, ...manifestPaths], {
    encoding: "utf8",
  })

  return {
    exitCode: result.status ?? 1,
    stdout: result.stdout ?? "",
    stderr: result.stderr ?? "",
  }
}

describe("assert-shared-version", () => {
  it("passes when the runtime, core, and cli manifests share one version", () => {
    const rootDir = mkdtempSync(join(tmpdir(), "openapi-rescript-publish-version-"))

    try {
      const runtimeManifest = writeManifest(rootDir, "openapi-rescript-runtime", "1.2.3")
      const coreManifest = writeManifest(rootDir, "openapi-rescript-core", "1.2.3")
      const cliManifest = writeManifest(rootDir, "openapi-rescript-cli", "1.2.3")

      const result = runAssertSharedVersion([runtimeManifest, coreManifest, cliManifest])

      expect(result.exitCode).toBe(0)
      expect(result.stdout).toBe("")
      expect(result.stderr).toBe("")
    } finally {
      rmSync(rootDir, {recursive: true, force: true})
    }
  })

  it("fails with a readable package-specific error when one manifest version differs", () => {
    const rootDir = mkdtempSync(join(tmpdir(), "openapi-rescript-publish-version-"))

    try {
      const runtimeManifest = writeManifest(rootDir, "openapi-rescript-runtime", "1.2.3")
      const coreManifest = writeManifest(rootDir, "openapi-rescript-core", "1.2.4")
      const cliManifest = writeManifest(rootDir, "openapi-rescript-cli", "1.2.3")

      const result = runAssertSharedVersion([runtimeManifest, coreManifest, cliManifest])

      expect(result.exitCode).toBe(1)
      expect(result.stdout).toBe("")
      expect(result.stderr).toContain("openapi-rescript-core")
      expect(result.stderr).toContain("1.2.3")
      expect(result.stderr).toContain("1.2.4")
    } finally {
      rmSync(rootDir, {recursive: true, force: true})
    }
  })

  it("fails when the required three-package manifest set is missing or duplicated", () => {
    const rootDir = mkdtempSync(join(tmpdir(), "openapi-rescript-publish-version-"))

    try {
      const runtimeManifest = writeManifest(rootDir, "openapi-rescript-runtime", "1.2.3")
      const duplicateRuntimeManifest = writeManifest(rootDir, "openapi-rescript-runtime-copy", "1.2.3")
      const coreManifest = writeManifest(rootDir, "openapi-rescript-core", "1.2.3")
      writeFileSync(
        duplicateRuntimeManifest,
        JSON.stringify(
          {
            name: "openapi-rescript-runtime",
            version: "1.2.3",
          },
          null,
          2
        )
      )

      const result = runAssertSharedVersion([runtimeManifest, duplicateRuntimeManifest, coreManifest])

      expect(result.exitCode).toBe(1)
      expect(result.stdout).toBe("")
      expect(result.stderr).toContain("openapi-rescript-cli")
      expect(result.stderr).toContain("missing")
      expect(result.stderr).toContain("openapi-rescript-runtime")
      expect(result.stderr).toContain("duplicate")
    } finally {
      rmSync(rootDir, {recursive: true, force: true})
    }
  })
})
