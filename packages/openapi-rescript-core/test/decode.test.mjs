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
    expect(output.value.security).toEqual([["ApiKeyAuth"]])
    expect(output.value.securitySchemes).toEqual([
      {
        name: "ApiKeyAuth",
        kind: "apiKey",
        keyName: "X-API-Key",
        location: "header",
        scheme: undefined,
      },
    ])
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

  it("merges path-item parameters into operations", () => {
    let withPathParameters = {
      ...normalizedPetstore,
      paths: {
        ...normalizedPetstore.paths,
        "/pets": {
          ...normalizedPetstore.paths["/pets"],
          parameters: [
            {
              name: "tenantId",
              in: "header",
              required: true,
              schema: {type: "string"},
            },
          ],
        },
      },
    }

    let output = generate(withPathParameters)
    expect(output.ok).toBe(true)
    expect(output.value.operations[0].parameters).toEqual([
      {
        name: "tenantId",
        location: "header",
        required: true,
        schema: {TAG: "Scalar", _0: "string"},
      },
      {
        name: "limit",
        location: "query",
        required: false,
        schema: {TAG: "Scalar", _0: "integer"},
      },
    ])
  })

  it("lets operation parameters override matching path-item parameters", () => {
    let withOverriddenPathParameter = {
      ...normalizedPetstore,
      paths: {
        ...normalizedPetstore.paths,
        "/pets": {
          ...normalizedPetstore.paths["/pets"],
          parameters: [
            {
              name: "limit",
              in: "query",
              required: true,
              schema: {type: "string"},
            },
          ],
        },
      },
    }

    let output = generate(withOverriddenPathParameter)
    expect(output.ok).toBe(true)
    expect(output.value.operations[0].parameters).toEqual([
      {
        name: "limit",
        location: "query",
        required: false,
        schema: {TAG: "Scalar", _0: "integer"},
      },
    ])
  })

  it("rejects unsupported schemas with a precise path", () => {
    expect(generate(normalizedUnsupported)).toMatchObject({
      ok: false,
      error: {
        path: ["components", "schemas", "WeirdType", "oneOf"],
      },
    })
  })

  it("rejects unsupported schema keywords with precise paths", () => {
    let unsupportedEnum = {
      ...normalizedPetstore,
      components: {
        ...normalizedPetstore.components,
        schemas: {
          ...normalizedPetstore.components.schemas,
          Pet: {
            type: "string",
            enum: ["cat"],
          },
        },
      },
    }

    expect(generate(unsupportedEnum)).toMatchObject({
      ok: false,
      error: {
        path: ["components", "schemas", "Pet", "enum"],
        message: "Unsupported schema construct: enum",
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

  it("rejects wrong-typed optional fields with precise paths", () => {
    let wrongTypes = {
      ...normalizedPetstore,
      paths: {
        ...normalizedPetstore.paths,
        "/pets": {
          ...normalizedPetstore.paths["/pets"],
          get: {
            ...normalizedPetstore.paths["/pets"].get,
            operationId: 123,
          },
        },
      },
    }

    expect(generate(wrongTypes)).toMatchObject({
      ok: false,
      error: {
        path: ["paths", "/pets", "get", "operationId"],
        message: "Expected string",
      },
    })
  })

  it("rejects wrong-typed optional booleans with precise paths", () => {
    let wrongRequired = {
      ...normalizedPetstore,
      paths: {
        ...normalizedPetstore.paths,
        "/pets": {
          ...normalizedPetstore.paths["/pets"],
          post: {
            ...normalizedPetstore.paths["/pets"].post,
            requestBody: {
              ...normalizedPetstore.paths["/pets"].post.requestBody,
              required: "yes",
            },
          },
        },
      },
    }

    expect(generate(wrongRequired)).toMatchObject({
      ok: false,
      error: {
        path: ["paths", "/pets", "post", "requestBody", "required"],
        message: "Expected boolean",
      },
    })
  })

  it("rejects request bodies with no supported JSON media type", () => {
    let emptyContent = {
      ...normalizedPetstore,
      paths: {
        ...normalizedPetstore.paths,
        "/pets": {
          ...normalizedPetstore.paths["/pets"],
          post: {
            ...normalizedPetstore.paths["/pets"].post,
            requestBody: {
              ...normalizedPetstore.paths["/pets"].post.requestBody,
              content: {},
            },
          },
        },
      },
    }

    expect(generate(emptyContent)).toMatchObject({
      ok: false,
      error: {
        path: ["paths", "/pets", "post", "requestBody", "content"],
        message: "Only JSON media types are supported",
      },
    })
  })

  it("rejects unsupported security scheme kinds", () => {
    let unsupportedSecurity = {
      ...normalizedPetstore,
      components: {
        ...normalizedPetstore.components,
        securitySchemes: {
          OAuth: {
            type: "oauth2",
          },
        },
      },
      security: [{OAuth: []}],
    }

    expect(generate(unsupportedSecurity)).toMatchObject({
      ok: false,
      error: {
        path: ["components", "securitySchemes", "OAuth"],
        message: "Unsupported security scheme: oauth2",
      },
    })
  })

  it("rejects wrong-typed security requirement values", () => {
    let invalidSecurityRequirement = {
      ...normalizedPetstore,
      security: [{ApiKeyAuth: true}],
    }

    expect(generate(invalidSecurityRequirement)).toMatchObject({
      ok: false,
      error: {
        path: ["security", "0", "ApiKeyAuth"],
        message: "Expected array",
      },
    })
  })

  it("rejects scoped security requirement arrays", () => {
    let scopedSecurityRequirement = {
      ...normalizedPetstore,
      security: [{ApiKeyAuth: ["admin"]}],
    }

    expect(generate(scopedSecurityRequirement)).toMatchObject({
      ok: false,
      error: {
        path: ["security", "0", "ApiKeyAuth"],
        message: "Only empty security requirement arrays are supported",
      },
    })
  })

  it("rejects unsupported HTTP auth schemes", () => {
    let unsupportedHttpScheme = {
      ...normalizedPetstore,
      components: {
        ...normalizedPetstore.components,
        securitySchemes: {
          HttpAuth: {
            type: "http",
            scheme: "digest",
          },
        },
      },
      security: [{HttpAuth: []}],
    }

    expect(generate(unsupportedHttpScheme)).toMatchObject({
      ok: false,
      error: {
        path: ["components", "securitySchemes", "HttpAuth"],
        message: "Unsupported HTTP auth scheme: digest",
      },
    })
  })
})
