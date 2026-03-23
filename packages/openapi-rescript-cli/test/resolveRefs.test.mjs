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
    expect(result.paths["/hello"].get.responses["200"].content["application/json"].schema.required).toEqual([
      "message",
    ])
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

  it("rejects unsupported absolute URI refs", async () => {
    const dir = mkdtempSync(join(tmpdir(), "openapi-rescript-cli-"))
    const file = join(dir, "absolute-uri-ref.yaml")

    writeFileSync(
      file,
      [
        "openapi: 3.1.0",
        "info:",
        "  title: Absolute URI API",
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
        "                $ref: urn:example:foo",
        "",
      ].join("\n")
    )

    try {
      await expect(resolveRefs(file)).rejects.toThrow(/unsupported.*ref/i)
    } finally {
      rmSync(dir, {recursive: true, force: true})
    }
  })

  it("parses sequence items with inline mappings and nested fields", async () => {
    const dir = mkdtempSync(join(tmpdir(), "openapi-rescript-cli-"))
    const file = join(dir, "tags.yaml")

    writeFileSync(
      file,
      [
        "openapi: 3.1.0",
        "info:",
        "  title: Tags API",
        "  version: 1.0.0",
        "tags:",
        "  - name: pets",
        "    description: Pet operations",
        "    externalDocs:",
        "      description: More info",
        "      url: https://example.com/docs",
        "",
      ].join("\n")
    )

    try {
      const result = await resolveRefs(file)

      expect(result.tags).toEqual([
        {
          name: "pets",
          description: "Pet operations",
          externalDocs: {
            description: "More info",
            url: "https://example.com/docs",
          },
        },
      ])
    } finally {
      rmSync(dir, {recursive: true, force: true})
    }
  })
})
