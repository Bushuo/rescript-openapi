import {describe, expect, it} from "vitest"
import {mkdtempSync, rmSync, writeFileSync} from "node:fs"
import {tmpdir} from "node:os"
import {join, resolve} from "node:path"
import {resolveRefs} from "../src/resolveRefs.mjs"

describe("resolveRefs", () => {
  it("resolves local file refs", async () => {
    const result = await resolveRefs(resolve("fixtures/refs/root.yaml"))

    expect(result.paths["/hello"].get.responses["200"].content["application/json"].schema).toMatchObject(
      {
        type: "object",
        properties: {
          message: {
            type: "string",
          },
        },
      }
    )
  })

  it("rejects remote refs", async () => {
    const dir = mkdtempSync(join(tmpdir(), "openapi-rescript-cli-"))
    const file = join(dir, "remote-ref.yaml")

    writeFileSync(
      file,
      [
        "openapi: 3.1.0",
        "info:",
        "  title: Remote API",
        "  version: 1.0.0",
        "paths:",
        "  /hello:",
        "    get:",
        "      responses:",
        "        '200':",
        "          description: OK",
        "          content:",
        "            application/json:",
        "              schema:",
        "                $ref: https://example.com/schema.yaml",
        "",
      ].join("\n")
    )

    try {
      await expect(resolveRefs(file)).rejects.toThrow(/remote refs/i)
    } finally {
      rmSync(dir, {recursive: true, force: true})
    }
  })
})
