import {describe, expect, it} from "vitest"
import {execFileSync} from "node:child_process"
import {mkdtempSync, readdirSync, rmSync, writeFileSync} from "node:fs"
import {tmpdir} from "node:os"
import {join, resolve} from "node:path"
import {pathToFileURL} from "node:url"

const publishOwner = "bushuo"
const publishRepository = "rescript-openapi"
const stageGithubPackageScript = resolve("scripts/publish/stage-github-package.mjs")
const publishedCorePackageName = `@${publishOwner}/openapi-rescript-core`

function packStagedPackage(packageName) {
  const packageDir = resolve("packages", packageName)
  const stageDir = mkdtempSync(join(tmpdir(), `${packageName}-stage-`))
  const packDir = mkdtempSync(join(tmpdir(), "openapi-rescript-cli-pack-"))

  execFileSync("node", [stageGithubPackageScript, packageDir, publishOwner, publishRepository, stageDir], {
    encoding: "utf8",
  })

  execFileSync("pnpm", ["pack", "--pack-destination", packDir], {
    cwd: stageDir,
    encoding: "utf8",
  })

  const tarball = readdirSync(packDir).find((file) => file.endsWith(".tgz"))
  expect(tarball).toBeDefined()

  return {packDir, stageDir, tarball: join(packDir, tarball)}
}

function cleanEnv() {
  return Object.fromEntries(
    ["HOME", "PATH", "TMPDIR", "TMP", "TEMP", "SystemRoot", "ComSpec", "PATHEXT"]
      .map((name) => [name, process.env[name]])
      .filter(([, value]) => value !== undefined)
  )
}

function writeSmokeProjectManifest(projectDir, coreTarball) {
  writeFileSync(
    join(projectDir, "package.json"),
    `${JSON.stringify(
      {
        private: true,
        pnpm: {
          overrides: {
            [publishedCorePackageName]: pathToFileURL(coreTarball).href,
          },
        },
      },
      null,
      2
    )}\n`
  )
}

function runInstalledCli(projectDir, args) {
  return execFileSync("pnpm", ["exec", "openapi-rescript", ...args], {
    cwd: projectDir,
    encoding: "utf8",
    env: cleanEnv(),
  })
}

describe("openapi-rescript CLI smoke test", () => {
  it("runs through the packaged bin entrypoint", () => {
    const dir = mkdtempSync(join(tmpdir(), "openapi-rescript-cli-"))
    const file = join(dir, "smoke.yaml")
    const cliPackage = packStagedPackage("openapi-rescript-cli")
    const corePackage = packStagedPackage("openapi-rescript-core")

    writeFileSync(
      file,
      [
        "openapi: 3.1.0",
        "info:",
        "  title: Smoke API",
        "  version: 1.0.0",
        "components:",
        "  schemas:",
        "    Pong:",
        "      type: object",
        "paths: {}",
        "",
      ].join("\n")
    )

    try {
      writeSmokeProjectManifest(dir, corePackage.tarball)
      execFileSync("pnpm", ["add", cliPackage.tarball], {cwd: dir, stdio: "pipe"})
      const output = runInstalledCli(dir, [file, dir])

      expect(output).toBe("")
      expect(readdirSync(dir)).toEqual(expect.arrayContaining(["Client.res", "Index.res", "Models.res", "Schemas.res"]))
    } finally {
      rmSync(dir, {recursive: true, force: true})
      rmSync(cliPackage.stageDir, {recursive: true, force: true})
      rmSync(cliPackage.packDir, {recursive: true, force: true})
      rmSync(corePackage.stageDir, {recursive: true, force: true})
      rmSync(corePackage.packDir, {recursive: true, force: true})
    }
  })

  it("accepts the packaged closed enum mode flag", () => {
    const dir = mkdtempSync(join(tmpdir(), "openapi-rescript-cli-"))
    const file = join(dir, "smoke.yaml")
    const cliPackage = packStagedPackage("openapi-rescript-cli")
    const corePackage = packStagedPackage("openapi-rescript-core")

    writeFileSync(
      file,
      [
        "openapi: 3.1.0",
        "info:",
        "  title: Smoke API",
        "  version: 1.0.0",
        "components:",
        "  schemas:",
        "    Pong:",
        "      type: object",
        "paths: {}",
        "",
      ].join("\n")
    )

    try {
      writeSmokeProjectManifest(dir, corePackage.tarball)
      execFileSync("pnpm", ["add", cliPackage.tarball], {cwd: dir, stdio: "pipe"})
      const output = runInstalledCli(dir, ["--enum-mode=closed", file, dir])

      expect(output).toBe("")
      expect(readdirSync(dir)).toEqual(expect.arrayContaining(["Client.res", "Index.res", "Models.res", "Schemas.res"]))
    } finally {
      rmSync(dir, {recursive: true, force: true})
      rmSync(cliPackage.stageDir, {recursive: true, force: true})
      rmSync(cliPackage.packDir, {recursive: true, force: true})
      rmSync(corePackage.stageDir, {recursive: true, force: true})
      rmSync(corePackage.packDir, {recursive: true, force: true})
    }
  })
})
