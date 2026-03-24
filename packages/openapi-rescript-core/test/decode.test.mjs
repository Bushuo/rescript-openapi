import {readFileSync} from "node:fs"
import {describe, expect, it} from "vitest"
import {generate} from "../lib/js/src/OpenapiGenerator.bs.js"

const normalizedPetstore = JSON.parse(
  readFileSync(new URL("./fixtures/petstore.normalized.json", import.meta.url), "utf8"),
)
const normalizedUnsupported = JSON.parse(
  readFileSync(new URL("./fixtures/unsupported-schema.normalized.json", import.meta.url), "utf8"),
)

describe("decodeDocument", () => {
  it("decodes a supported OpenAPI 3.1 document into IR", () => {
    let output = generate(normalizedPetstore)

    expect(output.ok).toBe(true)
    expect(output.value.title).toBe("Petstore")
    expect(output.value.version).toBe("1.0.0")
    expect(output.value.tags).toEqual(["pets"])
    expect(output.value.security).toEqual(["ApiKeyAuth"])
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
})
