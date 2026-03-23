import {describe, expect, it} from "vitest"
import {mkdtempSync, rmSync, writeFileSync} from "node:fs"
import {tmpdir} from "node:os"
import {join, resolve} from "node:path"
import {parseInput} from "../src/parseInput.mjs"

describe("parseInput", () => {
  it("parses YAML input into a plain JS object", async () => {
    const result = await parseInput(resolve("fixtures/refs/root.yaml"))

    expect(result).toMatchObject({
      openapi: "3.1.0",
      info: {
        title: "Root API",
      },
    })
  })

  it("parses JSON input into a plain JS object", async () => {
    const dir = mkdtempSync(join(tmpdir(), "openapi-rescript-cli-"))
    const file = join(dir, "spec.json")

    writeFileSync(
      file,
      JSON.stringify(
        {
          openapi: "3.1.0",
          info: {
            title: "JSON API",
            version: "1.0.0",
          },
        },
        null,
        2
      )
    )

    try {
      const result = await parseInput(file)

      expect(result).toMatchObject({
        openapi: "3.1.0",
        info: {
          title: "JSON API",
        },
      })
    } finally {
      rmSync(dir, {recursive: true, force: true})
    }
  })
})
