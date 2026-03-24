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
const normalizedPetstore = JSON.parse(
  readFileSync(new URL("./fixtures/petstore.normalized.json", import.meta.url), "utf8"),
)
const normalizedUnsupported = JSON.parse(
  readFileSync(new URL("./fixtures/unsupported-schema.normalized.json", import.meta.url), "utf8"),
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
        operations: [],
        schemas: [],
      },
    })
  })

  it("decodes a supported OpenAPI 3.1 document into IR", () => {
    let output = generate(normalizedPetstore)

    expect(output.ok).toBe(true)
    expect(output.value.title).toBe("Petstore")
    expect(output.value.version).toBe("1.0.0")
    expect(output.value.tags).toEqual(["pets"])
    expect(output.value.securitySchemes).toEqual([{name: "ApiKeyAuth", kind: "apiKey"}])
    expect(output.value.operations.map(operation => operation.operationId)).toEqual([
      "listPets",
      "createPet",
    ])
    expect(output.value.operations[0].parameters).toEqual([
      {
        name: "limit",
        location: "query",
        required: false,
        schema: {TAG: "Scalar", _0: "integer"},
      },
    ])
    expect(output.value.operations[0].responses).toEqual([
      {
        statusCode: "200",
        schema: {TAG: "Array", _0: {TAG: "NamedRef", _0: "#/components/schemas/Pet"}},
      },
    ])
    expect(output.value.operations[1].requestBody).toEqual({
      required: true,
      schema: {TAG: "NamedRef", _0: "#/components/schemas/NewPet"},
    })
    expect(output.value.operations[1].responses).toEqual([
      {
        statusCode: "201",
        schema: {TAG: "NamedRef", _0: "#/components/schemas/Pet"},
      },
    ])
    expect(output.value.schemas.map(schema => schema.name)).toEqual(["Pet", "NewPet"])
  })

  it("rejects unsupported schemas with a precise path", () => {
    expect(generate(normalizedUnsupported)).toMatchObject({
      ok: false,
      error: {
        path: ["components", "schemas", "WeirdType"],
      },
    })
  })

  it("allows operations without operationId so later tasks can normalize names", () => {
    let withoutOperationId = {
      ...normalizedPetstore,
      paths: {
        ...normalizedPetstore.paths,
        "/pets": {
          ...normalizedPetstore.paths["/pets"],
          get: {
            ...normalizedPetstore.paths["/pets"].get,
            operationId: undefined,
          },
        },
      },
    }

    let output = generate(withoutOperationId)
    expect(output.ok).toBe(true)
    expect(output.value.operations[0].operationId).toBeUndefined()
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
