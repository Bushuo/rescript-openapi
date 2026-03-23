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
          paths: {},
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
        paths: {},
      })
    } finally {
      rmSync(dir, {recursive: true, force: true})
    }
  })

  it("parses YAML document markers, inline comments, and flow collections", async () => {
    const dir = mkdtempSync(join(tmpdir(), "openapi-rescript-cli-"))
    const file = join(dir, "spec.yaml")

    writeFileSync(
      file,
      [
        "---",
        "openapi: 3.1.0 # comment after version",
        "info:",
        "  title: Demo API",
        "  version: 1.0.0",
        "tags: [{name: pets, description: Pet operations}]",
        "servers: [https://example.com]",
        "paths:",
        "  /pets:",
        "    get:",
        "      summary: List pets # inline comment",
        "      parameters:",
        "        - name: limit",
        "          in: query",
        "          schema: {type: integer}",
        "      responses:",
        "        '200':",
        "          description: OK",
        "          content:",
        "            application/json:",
        "              schema:",
        "                type: object",
        "                properties:",
        "                  pets:",
        "                    type: array",
        "                    items:",
        "                      type: string",
        "",
      ].join("\n")
    )

    try {
      const result = await parseInput(file)

      expect(result.openapi).toBe("3.1.0")
      expect(result.tags).toEqual([{name: "pets", description: "Pet operations"}])
      expect(result.servers).toEqual(["https://example.com"])
      expect(result.paths["/pets"].get.parameters).toEqual([
        {
          name: "limit",
          in: "query",
          schema: {
            type: "integer",
          },
        },
      ])
      expect(result.paths["/pets"].get.summary).toBe("List pets")
    } finally {
      rmSync(dir, {recursive: true, force: true})
    }
  })
})
