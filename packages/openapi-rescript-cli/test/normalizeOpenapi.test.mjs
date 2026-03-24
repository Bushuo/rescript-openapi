import {describe, expect, it} from "vitest"
import {normalizeOpenapi} from "../src/normalizeOpenapi.mjs"

describe("normalizeOpenapi", () => {
  it("accepts OpenAPI 3.1.x documents with paths", () => {
    expect(
      normalizeOpenapi({
        openapi: "3.1.9",
        info: {
          title: "Accepted",
          version: "1.0.0",
        },
        paths: {},
        webhooks: {},
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

  it.each([
    {
      label: "components only",
      document: {
        openapi: "3.1.0",
        info: {
          title: "Missing paths",
          version: "1.0.0",
        },
        components: {},
      },
    },
    {
      label: "webhooks only",
      document: {
        openapi: "3.1.0",
        info: {
          title: "Missing paths",
          version: "1.0.0",
        },
        webhooks: {},
      },
    },
  ])("rejects $label documents without paths", ({document}) => {
    expect(() => normalizeOpenapi(document)).toThrow(/must include a paths object/i)
  })
})
