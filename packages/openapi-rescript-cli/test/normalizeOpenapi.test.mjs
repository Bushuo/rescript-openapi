import {describe, expect, it} from "vitest"
import {normalizeOpenapi} from "../src/normalizeOpenapi.mjs"

describe("normalizeOpenapi", () => {
  it("accepts OpenAPI 3.1.x documents", () => {
    expect(
      normalizeOpenapi({
        openapi: "3.1.9",
        info: {
          title: "Accepted",
          version: "1.0.0",
        },
        paths: {},
      })
    ).toMatchObject({
      openapi: "3.1.9",
    })
  })

  it("rejects non-3.1 documents", () => {
    expect(() =>
      normalizeOpenapi({
        openapi: "3.0.3",
        info: {
          title: "Rejected",
          version: "1.0.0",
        },
        paths: {},
      })
    ).toThrow(/openapi 3\.1/i)
  })

  it("rejects minimal documents without the required top-level shape", () => {
    expect(() =>
      normalizeOpenapi({
        openapi: "3.1.0",
      })
    ).toThrow(/missing/i)
  })
})
