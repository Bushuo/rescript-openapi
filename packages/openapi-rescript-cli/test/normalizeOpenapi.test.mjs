import {describe, expect, it} from "vitest"
import {normalizeOpenapi} from "../src/normalizeOpenapi.mjs"

describe("normalizeOpenapi", () => {
  it("accepts OpenAPI 3.1 documents", () => {
    expect(
      normalizeOpenapi({
        openapi: "3.1.0",
        info: {
          title: "Accepted",
          version: "1.0.0",
        },
      })
    ).toMatchObject({
      openapi: "3.1.0",
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
      })
    ).toThrow(/openapi 3\.1/i)
  })
})
