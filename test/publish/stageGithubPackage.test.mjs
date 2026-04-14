import {spawnSync} from "node:child_process"
import {existsSync, mkdirSync, mkdtempSync, readFileSync, rmSync, writeFileSync} from "node:fs"
import {tmpdir} from "node:os"
import {basename, join, resolve} from "node:path"
import {describe, expect, it} from "vitest"

const scriptPath = resolve("scripts/publish/stage-github-package.mjs")

function readJson(path) {
  return JSON.parse(readFileSync(path, "utf8"))
}

function readPackageSnapshot(packageDir) {
  return {
    manifest: readFileSync(join(packageDir, "package.json"), "utf8"),
    readme: readFileSync(join(packageDir, "README.md"), "utf8"),
    indexJs: readFileSync(join(packageDir, "src", "index.js"), "utf8"),
  }
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

function writeRescriptConfig(packageDir, config) {
  writeFileSync(join(packageDir, "rescript.json"), `${JSON.stringify(config, null, 2)}\n`)
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
        "@bushuo/openapi-rescript-runtime": "1.2.3",
      })
    } finally {
      rmSync(rootDir, {recursive: true, force: true})
    }
  })

  it("rewrites staged workspace package dependencies to the committed release version", () => {
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
        "@bushuo/openapi-rescript-core": "1.2.3",
        yaml: "^2.8.3",
      })
    } finally {
      rmSync(rootDir, {recursive: true, force: true})
    }
  })

  it("rewrites rescript package names and dependencies to scoped publish names", () => {
    const rootDir = mkdtempSync(join(tmpdir(), "openapi-rescript-stage-package-"))

    try {
      const cliDir = writePackageFixture(rootDir, "openapi-rescript-cli")
      const outputDir = join(rootDir, "staged-cli")

      writeRescriptConfig(cliDir, {
        name: "openapi-rescript-cli",
        sources: [{dir: "src", subdirs: true}],
        dependencies: ["openapi-rescript-core"],
      })

      const result = runStageGithubPackage({
        packageDir: cliDir,
        owner: "bushuo",
        repository: "rescript-openapi",
        outputDir,
      })

      expect(result.exitCode).toBe(0)
      expect(result.stdout).toBe("")
      expect(result.stderr).toBe("")

      const sourceConfig = readJson(join(cliDir, "rescript.json"))
      const stagedConfig = readJson(join(outputDir, "rescript.json"))

      expect(sourceConfig).toEqual({
        name: "openapi-rescript-cli",
        sources: [{dir: "src", subdirs: true}],
        dependencies: ["openapi-rescript-core"],
      })
      expect(stagedConfig).toEqual({
        name: "@bushuo/openapi-rescript-cli",
        sources: [{dir: "src", subdirs: true}],
        dependencies: ["@bushuo/openapi-rescript-core"],
      })
    } finally {
      rmSync(rootDir, {recursive: true, force: true})
    }
  })

  it("uses an explicit owner/repository slug without prepending the owner again", () => {
    const rootDir = mkdtempSync(join(tmpdir(), "openapi-rescript-stage-package-"))

    try {
      const runtimeDir = writePackageFixture(rootDir, "openapi-rescript-runtime")
      const outputDir = join(rootDir, "staged-runtime")

      const result = runStageGithubPackage({
        packageDir: runtimeDir,
        owner: "bushuo",
        repository: "Bushuo/rescript-openapi",
        outputDir,
      })

      expect(result.exitCode).toBe(0)
      expect(result.stdout).toBe("")
      expect(result.stderr).toBe("")

      const stagedManifest = readJson(join(outputDir, "package.json"))

      expect(stagedManifest.repository).toEqual({
        type: "git",
        url: "git+https://github.com/Bushuo/rescript-openapi.git",
      })
    } finally {
      rmSync(rootDir, {recursive: true, force: true})
    }
  })

  it("removes staged pack-time hooks without stripping unrelated scripts", () => {
    const rootDir = mkdtempSync(join(tmpdir(), "openapi-rescript-stage-package-"))

    try {
      const cliDir = writePackageFixture(rootDir, "openapi-rescript-cli", {
        scripts: {
          prepack: "node scripts/vendor.mjs",
          postpack: "node scripts/cleanup.mjs",
          test: "vitest run",
          check: "tsc --noEmit",
        },
      })
      const outputDir = join(rootDir, "staged-cli")

      const result = runStageGithubPackage({
        packageDir: cliDir,
        owner: "bushuo",
        repository: "Bushuo/rescript-openapi",
        outputDir,
      })

      expect(result.exitCode).toBe(0)
      expect(result.stdout).toBe("")
      expect(result.stderr).toBe("")

      const sourceManifest = readJson(join(cliDir, "package.json"))
      const stagedManifest = readJson(join(outputDir, "package.json"))

      expect(sourceManifest.scripts).toEqual({
        prepack: "node scripts/vendor.mjs",
        postpack: "node scripts/cleanup.mjs",
        test: "vitest run",
        check: "tsc --noEmit",
      })
      expect(stagedManifest.scripts).toEqual({
        test: "vitest run",
        check: "tsc --noEmit",
      })
    } finally {
      rmSync(rootDir, {recursive: true, force: true})
    }
  })

  it("rewrites copied js imports from local package names to scoped publish names", () => {
    const rootDir = mkdtempSync(join(tmpdir(), "openapi-rescript-stage-package-"))

    try {
      const cliDir = writePackageFixture(rootDir, "openapi-rescript-cli", {
        dependencies: {
          "openapi-rescript-core": "workspace:*",
        },
      })
      const sourceJsPath = join(cliDir, "src", "CliArgs.bs.js")
      const outputDir = join(rootDir, "staged-cli")

      writeFileSync(
        sourceJsPath,
        'const OpenapiGenerator = require("openapi-rescript-core/src/OpenapiGenerator.bs.js")\n'
      )

      const result = runStageGithubPackage({
        packageDir: cliDir,
        owner: "bushuo",
        repository: "Bushuo/rescript-openapi",
        outputDir,
      })

      expect(result.exitCode).toBe(0)
      expect(result.stdout).toBe("")
      expect(result.stderr).toBe("")

      expect(readFileSync(sourceJsPath, "utf8")).toContain(
        'require("openapi-rescript-core/src/OpenapiGenerator.bs.js")'
      )
      expect(readFileSync(join(outputDir, "src", "CliArgs.bs.js"), "utf8")).toContain(
        'require("@bushuo/openapi-rescript-core/src/OpenapiGenerator.bs.js")'
      )
    } finally {
      rmSync(rootDir, {recursive: true, force: true})
    }
  })

  it("rejects an output directory that is the same as the source directory before mutating files", () => {
    const rootDir = mkdtempSync(join(tmpdir(), "openapi-rescript-stage-package-"))

    try {
      const runtimeDir = writePackageFixture(rootDir, "openapi-rescript-runtime")
      const sourceSnapshot = readPackageSnapshot(runtimeDir)

      const result = runStageGithubPackage({
        packageDir: runtimeDir,
        owner: "bushuo",
        repository: "rescript-openapi",
        outputDir: runtimeDir,
      })

      expect(result.exitCode).toBe(1)
      expect(result.stdout).toBe("")
      expect(result.stderr).toContain("Output directory must not overlap source directory")
      expect(readPackageSnapshot(runtimeDir)).toEqual(sourceSnapshot)
    } finally {
      rmSync(rootDir, {recursive: true, force: true})
    }
  })

  it("rejects an output directory nested under the source directory before creating staged files", () => {
    const rootDir = mkdtempSync(join(tmpdir(), "openapi-rescript-stage-package-"))

    try {
      const runtimeDir = writePackageFixture(rootDir, "openapi-rescript-runtime")
      const outputDir = join(runtimeDir, "staged")
      const sourceSnapshot = readPackageSnapshot(runtimeDir)

      const result = runStageGithubPackage({
        packageDir: runtimeDir,
        owner: "bushuo",
        repository: "rescript-openapi",
        outputDir,
      })

      expect(result.exitCode).toBe(1)
      expect(result.stdout).toBe("")
      expect(result.stderr).toContain("Output directory must not overlap source directory")
      expect(existsSync(outputDir)).toBe(false)
      expect(readPackageSnapshot(runtimeDir)).toEqual(sourceSnapshot)
    } finally {
      rmSync(rootDir, {recursive: true, force: true})
    }
  })
})
