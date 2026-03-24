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
const without = (object, key) => {
  let copy = {...object}
  delete copy[key]
  return copy
}

describe("generate", () => {
  it("returns a root diagnostic for non-object inputs", () => {
    expect(generate(null)).toMatchObject({
      ok: false,
      error: {
        path: [],
        message: "Unsupported OpenAPI input",
      },
    })
  })

  it("accepts a minimal supported OpenAPI 3.1 document", () => {
    expect(generate(minimalFixture)).toMatchObject({
      ok: true,
      value: {
        title: "Minimal API",
        version: "1.0.0",
        security: [],
        operations: [],
        schemas: [],
      },
    })
  })

  it("reports the openapi field path when openapi is missing", () => {
    expect(generate(without(minimalFixture, "openapi"))).toMatchObject({
      ok: false,
      error: {
        path: ["openapi"],
        message: "Missing required field",
      },
    })
  })

  it("reports the info field path when info is missing", () => {
    expect(generate(without(minimalFixture, "info"))).toMatchObject({
      ok: false,
      error: {
        path: ["info"],
        message: "Missing required field",
      },
    })
  })

  it("reports the paths field path when paths is missing", () => {
    expect(generate(without(minimalFixture, "paths"))).toMatchObject({
      ok: false,
      error: {
        path: ["paths"],
        message: "Missing required field",
      },
    })
  })

  it("reports the openapi field path when openapi has the wrong type", () => {
    expect(generate({...minimalFixture, openapi: 3.1})).toMatchObject({
      ok: false,
      error: {
        path: ["openapi"],
        message: "Expected string",
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
