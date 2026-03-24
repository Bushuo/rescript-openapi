import {describe, expect, it} from "vitest"
import {execFileSync} from "node:child_process"
import {tmpdir} from "node:os"
import {join, resolve} from "node:path"
import {mkdtempSync, readdirSync, rmSync, writeFileSync} from "node:fs"

describe("openapi-rescript CLI smoke test", () => {
  it("runs through the packaged bin entrypoint", () => {
    const dir = mkdtempSync(join(tmpdir(), "openapi-rescript-cli-"))
    const file = join(dir, "smoke.yaml")
    const packageDir = resolve("packages/openapi-rescript-cli")

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
      execFileSync("pnpm", ["add", `file:${packageDir}`], {cwd: dir, stdio: "pipe"})

      const output = execFileSync("pnpm", ["exec", "openapi-rescript", file, dir], {
        cwd: dir,
        encoding: "utf8",
      })

      expect(output).toBe("")
      expect(readdirSync(dir)).toEqual(expect.arrayContaining(["Client.res", "Index.res", "Models.res", "Schemas.res"]))
    } finally {
      rmSync(dir, {recursive: true, force: true})
    }
  })
})
