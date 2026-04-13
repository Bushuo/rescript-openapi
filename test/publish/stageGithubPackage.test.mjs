import {spawnSync} from "node:child_process"
import {existsSync, mkdirSync, mkdtempSync, readFileSync, rmSync, writeFileSync} from "node:fs"
import {tmpdir} from "node:os"
import {basename, join, resolve} from "node:path"
import {describe, expect, it} from "vitest"

const scriptPath = resolve("scripts/publish/stage-github-package.mjs")

function readJson(path) {
  return JSON.parse(readFileSync(path, "utf8"))
}

function writePackageFixture(rootDir, packageName, manifestExtras = {}) {
  const packageDir = join(rootDir, packageName)

  mkdirSync(join(packageDir, "src"), {recursive: true})
  writeFileSync(join(packageDir, "src", "index.js"), `export const name = "${packageName}"\n`)
  writeFileSync(join(packageDir, "README.md"), `# ${packageName}\n`)
  writeFileSync(
    join(packageDir, "package.json"),
    JSON.stringify(
      {
        name: packageName,
        private: true,
        version: "1.2.3",
        ...manifestExtras,
      },
      null,
      2
    )
  )

  return packageDir
}

function runStageGithubPackage({packageDir, owner, repository, outputDir}) {
  const result = spawnSync("node", [scriptPath, packageDir, owner, repository, outputDir], {
    encoding: "utf8",
  })

  return {
    exitCode: result.status ?? 1,
    stdout: result.stdout ?? "",
    stderr: result.stderr ?? "",
  }
}

describe("stage-github-package", () => {
  it("stages runtime, core, and cli package contents into scoped GitHub Packages directories", () => {
    const rootDir = mkdtempSync(join(tmpdir(), "openapi-rescript-stage-package-"))

    try {
      const runtimeDir = writePackageFixture(rootDir, "openapi-rescript-runtime")
      const coreDir = writePackageFixture(rootDir, "openapi-rescript-core", {
        dependencies: {
          "openapi-rescript-runtime": "workspace:*",
        },
      })
      const cliDir = writePackageFixture(rootDir, "openapi-rescript-cli", {
        dependencies: {
          "openapi-rescript-core": "workspace:*",
          yaml: "^2.8.3",
        },
      })

      for (const packageDir of [runtimeDir, coreDir, cliDir]) {
        const outputDir = join(rootDir, "staged", basename(packageDir))
        const result = runStageGithubPackage({
          packageDir,
          owner: "bushuo",
          repository: "rescript-openapi",
          outputDir,
        })

        expect(result.exitCode).toBe(0)
        expect(result.stdout).toBe("")
        expect(result.stderr).toBe("")

        const manifest = readJson(join(outputDir, "package.json"))

        expect(manifest.name).toBe(`@bushuo/${basename(packageDir)}`)
        expect(manifest.private).toBe(false)
        expect(manifest.version).toBe("1.2.3")
        expect(manifest.publishConfig).toEqual({
          registry: "https://npm.pkg.github.com",
        })
        expect(manifest.repository).toEqual({
          type: "git",
          url: "git+https://github.com/bushuo/rescript-openapi.git",
        })
        expect(existsSync(join(outputDir, "src", "index.js"))).toBe(true)
        expect(existsSync(join(outputDir, "README.md"))).toBe(true)
        expect(existsSync(join(outputDir, basename(packageDir), "package.json"))).toBe(false)
      }

      const stagedCoreManifest = readJson(join(rootDir, "staged", "openapi-rescript-core", "package.json"))
      expect(stagedCoreManifest.dependencies).toEqual({
        "@bushuo/openapi-rescript-runtime": "workspace:*",
      })
    } finally {
      rmSync(rootDir, {recursive: true, force: true})
    }
  })

  it("rewrites workspace package dependencies only inside the staged CLI manifest", () => {
    const rootDir = mkdtempSync(join(tmpdir(), "openapi-rescript-stage-package-"))

    try {
      const cliDir = writePackageFixture(rootDir, "openapi-rescript-cli", {
        dependencies: {
          "openapi-rescript-core": "workspace:*",
          yaml: "^2.8.3",
        },
      })
      const outputDir = join(rootDir, "staged-cli")

      const result = runStageGithubPackage({
        packageDir: cliDir,
        owner: "bushuo",
        repository: "rescript-openapi",
        outputDir,
      })

      expect(result.exitCode).toBe(0)
      expect(result.stdout).toBe("")
      expect(result.stderr).toBe("")

      const sourceManifest = readJson(join(cliDir, "package.json"))
      const stagedManifest = readJson(join(outputDir, "package.json"))

      expect(sourceManifest.name).toBe("openapi-rescript-cli")
      expect(sourceManifest.dependencies).toEqual({
        "openapi-rescript-core": "workspace:*",
        yaml: "^2.8.3",
      })

      expect(stagedManifest.name).toBe("@bushuo/openapi-rescript-cli")
      expect(stagedManifest.dependencies).toEqual({
        "@bushuo/openapi-rescript-core": "workspace:*",
        yaml: "^2.8.3",
      })
    } finally {
      rmSync(rootDir, {recursive: true, force: true})
    }
  })
})
