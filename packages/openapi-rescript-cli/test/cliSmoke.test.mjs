import {describe, expect, it} from "vitest"
import {execFileSync} from "node:child_process"
import {mkdtempSync, readdirSync, rmSync, writeFileSync} from "node:fs"
import {tmpdir} from "node:os"
import {join, resolve} from "node:path"

function packCliPackage() {
  const packageDir = resolve("packages/openapi-rescript-cli")
  const packDir = mkdtempSync(join(tmpdir(), "openapi-rescript-cli-pack-"))

  execFileSync("pnpm", ["pack", "--pack-destination", packDir], {
    cwd: packageDir,
    encoding: "utf8",
  })

  const tarball = readdirSync(packDir).find((file) => file.endsWith(".tgz"))
  expect(tarball).toBeDefined()

  return {packDir, tarball: join(packDir, tarball)}
}

describe("openapi-rescript CLI smoke test", () => {
  it("runs through the packaged bin entrypoint", () => {
    const dir = mkdtempSync(join(tmpdir(), "openapi-rescript-cli-"))
    const file = join(dir, "smoke.yaml")
    const {packDir, tarball} = packCliPackage()

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
      writeFileSync(join(dir, "package.json"), "{}\n")
      execFileSync("pnpm", ["add", tarball], {cwd: dir, stdio: "pipe"})

      const output = execFileSync("pnpm", ["exec", "openapi-rescript", file, dir], {
        cwd: dir,
        encoding: "utf8",
      })

      expect(output).toBe("")
      expect(readdirSync(dir)).toEqual(expect.arrayContaining(["Client.res", "Index.res", "Models.res", "Schemas.res"]))
    } finally {
      rmSync(dir, {recursive: true, force: true})
      rmSync(packDir, {recursive: true, force: true})
    }
  })
})
