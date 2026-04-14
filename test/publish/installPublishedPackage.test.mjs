import {spawnSync} from "node:child_process"
import {mkdtempSync, mkdirSync, readFileSync, readdirSync, rmSync, writeFileSync} from "node:fs"
import {tmpdir} from "node:os"
import {join, resolve} from "node:path"
import {describe, expect, it} from "vitest"

const stageScriptPath = resolve("scripts/publish/stage-github-package.mjs")
const packageRoot = resolve(".")
const petstoreSpecPath = resolve("fixtures/specs/petstore.yaml")

function run(command, args, options = {}) {
  const result = spawnSync(command, args, {
    encoding: "utf8",
    ...options,
  })

  return {
    exitCode: result.status ?? 1,
    stdout: result.stdout ?? "",
    stderr: result.stderr ?? "",
  }
}

function writeJson(path, value) {
  writeFileSync(path, `${JSON.stringify(value, null, 2)}\n`)
}

function stagePackage(packageDir, outputDir) {
  return run("node", [stageScriptPath, packageDir, "bushuo", "rescript-openapi", outputDir], {
    cwd: packageRoot,
  })
}

function packPackage(packageDir, tarballDir) {
  mkdirSync(tarballDir, {recursive: true})
  const before = new Set(readdirSync(tarballDir))
  const result = run("pnpm", ["pack", "--pack-destination", tarballDir], {
    cwd: packageDir,
  })
  const tarballName = readdirSync(tarballDir).find(entry => !before.has(entry))

  return {
    ...result,
    tarballPath: tarballName ? join(tarballDir, tarballName) : null,
  }
}

function writeConsumerFixture(appDir, tarballPaths) {
  mkdirSync(join(appDir, "src"), {recursive: true})
  writeFileSync(join(appDir, "openapi.yaml"), readFileSync(petstoreSpecPath, "utf8"))
  writeJson(join(appDir, "package.json"), {
    name: "published-package-compile-smoke",
    private: true,
    version: "0.0.0",
    dependencies: {
      "@bushuo/openapi-rescript-runtime": tarballPaths.runtime,
      rescript: "12.2.0",
    },
    devDependencies: {
      "@bushuo/openapi-rescript-core": tarballPaths.core,
      "@bushuo/openapi-rescript-cli": tarballPaths.cli,
    },
  })
  writeJson(join(appDir, "rescript.json"), {
    name: "published-package-compile-smoke",
    sources: {
      dir: "src",
      subdirs: true,
    },
    "package-specs": {
      module: "esmodule",
      "in-source": true,
    },
    suffix: ".res.mjs",
    dependencies: ["@bushuo/openapi-rescript-runtime"],
    "compiler-flags": [],
  })
  writeFileSync(join(appDir, "src", "Demo.res"), "let ready = true\n")
}

function withoutNpmConfigEnv(env) {
  return Object.fromEntries(
    Object.entries(env).filter(([key]) => !/^npm_config_/i.test(key))
  )
}

describe("published package install", () => {
  it("drops inherited npm config env vars before invoking npm", () => {
    expect(
      withoutNpmConfigEnv({
        PATH: "/usr/bin",
        HOME: "/tmp/home",
        NPM_CONFIG_VERIFY_DEPS_BEFORE_RUN: "1",
        npm_config_npm_globalconfig: "/tmp/npmrc",
        NPM_CONFIG__JSR_REGISTRY: "https://jsr.invalid",
      })
    ).toEqual({
      PATH: "/usr/bin",
      HOME: "/tmp/home",
    })
  })

  it(
    "stages, packs, installs, generates, and compiles a consumer app",
    () => {
      const rootDir = mkdtempSync(join(tmpdir(), "openapi-rescript-published-install-"))
      const stagedDir = join(rootDir, "staged")
      const tarballDir = join(rootDir, "tarballs")
      const appDir = join(rootDir, "consumer")

      try {
        const runtimeStage = stagePackage(resolve("packages/openapi-rescript-runtime"), join(stagedDir, "runtime"))
        const coreStage = stagePackage(resolve("packages/openapi-rescript-core"), join(stagedDir, "core"))
        const cliStage = stagePackage(resolve("packages/openapi-rescript-cli"), join(stagedDir, "cli"))

        expect(runtimeStage).toMatchObject({exitCode: 0, stdout: "", stderr: ""})
        expect(coreStage).toMatchObject({exitCode: 0, stdout: "", stderr: ""})
        expect(cliStage).toMatchObject({exitCode: 0, stdout: "", stderr: ""})

        const runtimePack = packPackage(join(stagedDir, "runtime"), tarballDir)
        const corePack = packPackage(join(stagedDir, "core"), tarballDir)
        const cliPack = packPackage(join(stagedDir, "cli"), tarballDir)

        expect(runtimePack.exitCode).toBe(0)
        expect(corePack.exitCode).toBe(0)
        expect(cliPack.exitCode).toBe(0)
        expect(runtimePack.tarballPath).toBeTruthy()
        expect(corePack.tarballPath).toBeTruthy()
        expect(cliPack.tarballPath).toBeTruthy()

        writeConsumerFixture(appDir, {
          runtime: runtimePack.tarballPath,
          core: corePack.tarballPath,
          cli: cliPack.tarballPath,
        })

        const installResult = run("npm", ["install"], {
          cwd: appDir,
          env: withoutNpmConfigEnv(process.env),
        })
        expect(installResult.exitCode).toBe(0)
        expect(installResult.stderr).toBe("")

        const generateResult = run(
          "node",
          [join(appDir, "node_modules", ".bin", "openapi-rescript"), join(appDir, "openapi.yaml"), join(appDir, "src", "generated")],
          {cwd: appDir}
        )
        expect(generateResult.exitCode).toBe(0)
        expect(generateResult.stdout).toBe("")
        expect(generateResult.stderr).toBe("")

        const buildResult = run("node", [join(appDir, "node_modules", ".bin", "rescript"), "build"], {cwd: appDir})
        expect(buildResult.exitCode).toBe(0)
        expect(buildResult.stderr).toBe("")
      } finally {
        rmSync(rootDir, {recursive: true, force: true})
      }
    },
    120000
  )
})
