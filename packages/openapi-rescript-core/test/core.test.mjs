import {execFileSync} from "node:child_process"
import {cpSync, mkdtempSync, readFileSync} from "node:fs"
import {tmpdir} from "node:os"
import {join} from "node:path"
import {fileURLToPath} from "node:url"
import {describe, expect, it} from "vitest"
import {generate} from "../lib/js/src/OpenapiGenerator.bs.js"

const minimalFixture = JSON.parse(
  readFileSync(new URL("./fixtures/minimal.json", import.meta.url), "utf8"),
)
const packageDir = fileURLToPath(new URL("..", import.meta.url))

describe("generate", () => {
  it("returns a structured diagnostic for unsupported inputs", () => {
    expect(generate({})).toMatchObject({
      ok: false,
      error: {
        path: [],
      },
    })
  })

  it("accepts a minimal supported OpenAPI 3.1 document", () => {
    expect(generate(minimalFixture)).toMatchObject({
      ok: true,
      value: {
        title: "Minimal API",
        version: "1.0.0",
        operations: [],
        schemas: [],
      },
    })
  })

  it("loads the built entrypoint under plain Node package resolution", () => {
    let sandboxDir = mkdtempSync(join(tmpdir(), "openapi-rescript-core-"))
    cpSync(new URL("../lib", import.meta.url), join(sandboxDir, "lib"), {recursive: true})
    cpSync(join(packageDir, "node_modules"), join(sandboxDir, "node_modules"), {recursive: true})

    let output = execFileSync(
      "node",
      ["-e", "require('./lib/js/src/OpenapiGenerator.bs.js'); process.stdout.write('loaded')"],
      {
        cwd: sandboxDir,
        encoding: "utf8",
        env: {
          PATH: process.env.PATH,
        },
      },
    )

    expect(output).toBe("loaded")
  })
})
