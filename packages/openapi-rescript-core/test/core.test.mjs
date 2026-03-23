import {readFileSync} from "node:fs"
import {describe, expect, it} from "vitest"
import {generate} from "../lib/js/src/OpenapiGenerator.bs.js"

const minimalFixture = JSON.parse(
  readFileSync(new URL("./fixtures/minimal.json", import.meta.url), "utf8"),
)

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
})
