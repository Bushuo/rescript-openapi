import {spawnSync} from "node:child_process"
import {mkdirSync, mkdtempSync, rmSync, writeFileSync} from "node:fs"
import {tmpdir} from "node:os"
import {join, resolve} from "node:path"
import {describe, expect, it} from "vitest"

const scriptPath = resolve("scripts/publish/resolve-dist-tag.mjs")

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

function runResolveDistTag(manifestPath) {
  const result = spawnSync("node", [scriptPath, manifestPath], {
    encoding: "utf8",
  })

  return {
    exitCode: result.status ?? 1,
    stdout: result.stdout ?? "",
    stderr: result.stderr ?? "",
  }
}

describe("resolve-dist-tag", () => {
  it("returns latest for stable versions", () => {
    const rootDir = mkdtempSync(join(tmpdir(), "openapi-rescript-dist-tag-"))

    try {
      const manifestPath = writeManifest(rootDir, "openapi-rescript-runtime", "1.2.3")
      const result = runResolveDistTag(manifestPath)

      expect(result.exitCode).toBe(0)
      expect(result.stdout).toBe("latest\n")
      expect(result.stderr).toBe("")
    } finally {
      rmSync(rootDir, {recursive: true, force: true})
    }
  })

  it("returns the prerelease channel for prerelease versions", () => {
    const rootDir = mkdtempSync(join(tmpdir(), "openapi-rescript-dist-tag-"))

    try {
      const manifestPath = writeManifest(rootDir, "openapi-rescript-runtime", "1.2.3-rc.4")
      const result = runResolveDistTag(manifestPath)

      expect(result.exitCode).toBe(0)
      expect(result.stdout).toBe("rc\n")
      expect(result.stderr).toBe("")
    } finally {
      rmSync(rootDir, {recursive: true, force: true})
    }
  })

  it("fails when a prerelease version starts with a numeric identifier", () => {
    const rootDir = mkdtempSync(join(tmpdir(), "openapi-rescript-dist-tag-"))

    try {
      const manifestPath = writeManifest(rootDir, "openapi-rescript-runtime", "1.2.3-0.alpha")
      const result = runResolveDistTag(manifestPath)

      expect(result.exitCode).toBe(1)
      expect(result.stdout).toBe("")
      expect(result.stderr).toContain("Cannot derive npm dist-tag")
      expect(result.stderr).toContain("1.2.3-0.alpha")
    } finally {
      rmSync(rootDir, {recursive: true, force: true})
    }
  })
})
