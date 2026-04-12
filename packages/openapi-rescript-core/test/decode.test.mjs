import {readFileSync} from "node:fs"
import {describe, expect, it} from "vitest"
import {generate} from "../src/OpenapiGenerator.bs.js"

const normalizedPetstore = JSON.parse(
  readFileSync(new URL("./fixtures/petstore.normalized.json", import.meta.url), "utf8"),
)
const normalizedUnsupported = JSON.parse(
  readFileSync(new URL("./fixtures/unsupported-schema.normalized.json", import.meta.url), "utf8"),
)
const normalizedEnums = JSON.parse(
  readFileSync(new URL("./fixtures/enums.normalized.json", import.meta.url), "utf8"),
)

const findSchema = (schemas, name) => schemas.find(schema => schema.name === name)

const emptyApi = title => ({
  openapi: "3.1.0",
  info: {title, version: "1.0.0"},
  paths: {},
  components: {schemas: {}},
})

const discriminatedBranch = ({tag, tagMode = "enum", properties = {}, required = []}) => ({
  type: "object",
  required: ["kind", ...required],
  properties: {
    kind: tagMode === "const" ? {const: tag} : {type: "string", enum: [tag]},
    ...properties,
  },
})

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
        authKind: "apiKey",
        credentialName: "X-API-Key",
        location: "header",
      },
    ])
    expect(output.value.operations.map(operation => operation.operationId)).toEqual(["listPets", "createPet"])
    expect(output.value.operations.map(operation => operation.name)).toEqual(["listPets", "createPet"])
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
        path: ["components", "schemas", "WeirdType", "oneOf", "0", "type"],
      },
    })
  })

  it("decodes oneOf [null, $ref] as Nullable(NamedRef)", () => {
    let fixture = {
      openapi: "3.1.0",
      info: {title: "Nullable Ref API", version: "1.0.0"},
      paths: {},
      components: {
        schemas: {
          AlcoholHabitsDto: {
            type: "object",
            properties: {},
          },
          Person: {
            oneOf: [{type: "null"}, {$ref: "#/components/schemas/AlcoholHabitsDto"}],
          },
        },
      },
    }

    let output = generate(fixture)

    expect(output.ok).toBe(true)
    expect(findSchema(output.value.schemas, "Person")).toEqual({
      name: "Person",
      schema: {
        TAG: "Nullable",
        _0: {TAG: "NamedRef", _0: "#/components/schemas/AlcoholHabitsDto"},
      },
    })
  })

  it("rejects nullable oneOf schemas with multiple null branches", () => {
    let fixture = {
      openapi: "3.1.0",
      info: {title: "Broken Nullable API", version: "1.0.0"},
      paths: {},
      components: {
        schemas: {
          Person: {
            oneOf: [{type: "null"}, {type: "null"}, {type: "string"}],
          },
        },
      },
    }

    expect(generate(fixture)).toMatchObject({
      ok: false,
      error: {
        path: ["components", "schemas", "Person", "oneOf"],
      },
    })
  })

  it("decodes supported discriminated object unions", () => {
    let fixture = emptyApi("Gender API")
    fixture.components.schemas.PregnancyStatusDto = {
      type: "object",
      properties: {},
    }
    fixture.components.schemas.Gender = {
      oneOf: [
        discriminatedBranch({tag: "Male"}),
        discriminatedBranch({
          tag: "Female",
          properties: {
            value: {$ref: "#/components/schemas/PregnancyStatusDto"},
          },
          required: ["value"],
        }),
        discriminatedBranch({tag: "PreferNotToSay", tagMode: "const"}),
      ],
    }

    let output = generate(fixture)
    let gender = findSchema(output.value.schemas, "Gender")

    expect(output.ok).toBe(true)
    expect(gender).toEqual({
      name: "Gender",
      schema: {
        TAG: "DiscriminatedUnion",
        discriminator: "kind",
        cases: [
          {tag: "Male", schema: {TAG: "Object", _0: []}},
          {
            tag: "Female",
            schema: {
              TAG: "Object",
              _0: expect.arrayContaining([
                {
                  name: "value",
                  required: true,
                  schema: {TAG: "NamedRef", _0: "#/components/schemas/PregnancyStatusDto"},
                },
              ]),
            },
          },
          {tag: "PreferNotToSay", schema: {TAG: "Object", _0: []}},
        ],
      },
    })
    expect(gender.schema.cases.find(case_ => case_.tag === "Female").schema._0).toEqual(
      expect.not.arrayContaining([expect.objectContaining({name: "kind"})]),
    )
  })

  it("decodes nullable discriminated object unions", () => {
    let fixture = emptyApi("Nullable Gender API")
    fixture.components.schemas.Gender = {
      oneOf: [
        {type: "null"},
        discriminatedBranch({tag: "Male"}),
        discriminatedBranch({tag: "Female"}),
      ],
    }

    let output = generate(fixture)

    expect(output.ok).toBe(true)
    expect(findSchema(output.value.schemas, "Gender")).toEqual({
      name: "Gender",
      schema: {
        TAG: "Nullable",
        _0: {
          TAG: "DiscriminatedUnion",
          discriminator: "kind",
          cases: [
            {tag: "Male", schema: {TAG: "Object", _0: []}},
            {tag: "Female", schema: {TAG: "Object", _0: []}},
          ],
        },
      },
    })
  })

  it("rejects discriminated unions when the discriminator is not required in every branch", () => {
    let fixture = emptyApi("Broken Gender API")
    fixture.components.schemas.Gender = {
      oneOf: [
        {
          type: "object",
          properties: {
            kind: {type: "string", enum: ["Male"]},
          },
        },
        discriminatedBranch({tag: "Female"}),
      ],
    }

    expect(generate(fixture)).toMatchObject({
      ok: false,
      error: {
        path: ["components", "schemas", "Gender", "oneOf"],
      },
    })
  })

  it("rejects discriminated unions with duplicate discriminator values", () => {
    let fixture = emptyApi("Duplicate Gender API")
    fixture.components.schemas.Gender = {
      oneOf: [discriminatedBranch({tag: "Male"}), discriminatedBranch({tag: "Male"})],
    }

    expect(generate(fixture)).toMatchObject({
      ok: false,
      error: {
        path: ["components", "schemas", "Gender", "oneOf", "1", "properties", "kind", "enum", "0"],
      },
    })
  })

  it("rejects discriminated unions with $ref discriminator schemas", () => {
    let fixture = emptyApi("Ref Gender API")
    fixture.components.schemas.GenderTag = {
      type: "string",
      enum: ["Male"],
    }
    fixture.components.schemas.Gender = {
      oneOf: [
        {
          type: "object",
          required: ["kind"],
          properties: {
            kind: {$ref: "#/components/schemas/GenderTag"},
          },
        },
      ],
    }

    expect(generate(fixture)).toMatchObject({
      ok: false,
      error: {
        path: ["components", "schemas", "Gender", "oneOf", "0", "properties", "kind", "$ref"],
      },
    })
  })

  it("decodes reachable string enums into named IR schemas", () => {
    let output = generate(normalizedEnums)

    expect(output.ok).toBe(true)
    expect(output.value.schemas.map(schema => schema.name)).toEqual(
      expect.arrayContaining([
        "Session",
        "SessionState",
        "sessionVisibility",
        "listUsersParamSort",
        "createSessionRequestState",
        "getSessionResponse200State",
      ]),
    )
    expect(findSchema(output.value.schemas, "SessionState")).toEqual({
      name: "SessionState",
      schema: {
        TAG: "StringEnum",
        name: "SessionState",
        path: ["components", "schemas", "SessionState", "enum"],
        values: ["draft", "active", "archived"],
      },
    })
    expect(findSchema(output.value.schemas, "Session")).toEqual({
      name: "Session",
      schema: {
        TAG: "Object",
        _0: expect.arrayContaining([
          {
            name: "visibility",
            required: true,
            schema: {TAG: "NamedRef", _0: "#/components/schemas/sessionVisibility"},
          },
        ]),
      },
    })
    expect(output.value.operations.find(operation => operation.name === "listUsers").parameters).toEqual([
      {
        name: "sort",
        location: "query",
        required: false,
        schema: {TAG: "NamedRef", _0: "#/components/schemas/listUsersParamSort"},
      },
    ])
    expect(output.value.operations.find(operation => operation.name === "createSession").requestBody)
      .toEqual({
        required: true,
        schema: {
          TAG: "Object",
          _0: expect.arrayContaining([
            {
              name: "state",
              required: true,
              schema: {TAG: "NamedRef", _0: "#/components/schemas/createSessionRequestState"},
            },
          ]),
        },
      })
    expect(output.value.operations.find(operation => operation.name === "getSession").responses).toEqual([
      {
        statusCode: "200",
        schema: {
          TAG: "Object",
          _0: expect.arrayContaining([
            {
              name: "state",
              required: true,
              schema: {TAG: "NamedRef", _0: "#/components/schemas/getSessionResponse200State"},
            },
          ]),
        },
      },
    ])
  })

  it("rejects enum siblings on $ref schemas with a precise path", () => {
    let refWithEnumSibling = {
      ...normalizedPetstore,
      components: {
        ...normalizedPetstore.components,
        schemas: {
          ...normalizedPetstore.components.schemas,
          PetAlias: {
            $ref: "#/components/schemas/Pet",
            enum: ["cat"],
          },
        },
      },
    }

    expect(generate(refWithEnumSibling)).toMatchObject({
      ok: false,
      error: {
        path: ["components", "schemas", "PetAlias", "enum"],
        message: "Unsupported schema construct: enum with $ref",
      },
    })
  })

  it("accepts untyped enums when all enum values are strings", () => {
    let untypedStringEnum = {
      ...normalizedPetstore,
      components: {
        ...normalizedPetstore.components,
        schemas: {
          ...normalizedPetstore.components.schemas,
          PetState: {
            enum: ["available", "adopted"],
          },
        },
      },
    }

    let output = generate(untypedStringEnum)

    expect(output.ok).toBe(true)
    expect(findSchema(output.value.schemas, "PetState")).toEqual({
      name: "PetState",
      schema: {
        TAG: "StringEnum",
        name: "PetState",
        path: ["components", "schemas", "PetState", "enum"],
        values: ["available", "adopted"],
      },
    })
  })

  it("rejects non-string enum base types with a precise path", () => {
    let integerEnum = {
      ...normalizedPetstore,
      components: {
        ...normalizedPetstore.components,
        schemas: {
          ...normalizedPetstore.components.schemas,
          PetId: {
            type: "integer",
            enum: [1, 2, 3],
          },
        },
      },
    }

    expect(generate(integerEnum)).toMatchObject({
      ok: false,
      error: {
        path: ["components", "schemas", "PetId", "type"],
        message: "Only string enums are supported",
      },
    })
  })

  it("rejects mixed enum value arrays with a precise path", () => {
    let mixedEnum = {
      ...normalizedPetstore,
      components: {
        ...normalizedPetstore.components,
        schemas: {
          ...normalizedPetstore.components.schemas,
          PetState: {
            type: "string",
            enum: ["cat", 1],
          },
        },
      },
    }

    expect(generate(mixedEnum)).toMatchObject({
      ok: false,
      error: {
        path: ["components", "schemas", "PetState", "enum", "1"],
        message: "Expected string",
      },
    })
  })

  it("rejects empty enum arrays with a precise path", () => {
    let emptyEnum = {
      ...normalizedPetstore,
      components: {
        ...normalizedPetstore.components,
        schemas: {
          ...normalizedPetstore.components.schemas,
          PetState: {
            type: "string",
            enum: [],
          },
        },
      },
    }

    expect(generate(emptyEnum)).toMatchObject({
      ok: false,
      error: {
        path: ["components", "schemas", "PetState", "enum"],
        message: "Enum arrays must not be empty",
      },
    })
  })

  it("derives fallback names for operations without operationId", () => {
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
    expect(output.value.operations[0].name).toBe("getPets")
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
        path: ["components", "securitySchemes", "OAuth", "type"],
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

  it("preserves explicit operation-level security clears instead of inheriting document auth", () => {
    let explicitSecurityClear = {
      ...normalizedPetstore,
      paths: {
        ...normalizedPetstore.paths,
        "/pets": {
          ...normalizedPetstore.paths["/pets"],
          get: {
            ...normalizedPetstore.paths["/pets"].get,
            security: [],
          },
        },
      },
    }

    let output = generate(explicitSecurityClear)

    expect(output.ok).toBe(true)
    expect(output.value.security).toEqual([["ApiKeyAuth"]])
    expect(output.value.operations.map(operation => operation.security)).toEqual([[], undefined])
  })

  it("accepts optional-auth security requirements expressed as empty objects", () => {
    let optionalAuth = {
      ...normalizedPetstore,
      security: [{}, {ApiKeyAuth: []}],
    }

    let output = generate(optionalAuth)

    expect(output.ok).toBe(true)
    expect(output.value.security).toEqual([[], ["ApiKeyAuth"]])
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
        path: ["components", "securitySchemes", "HttpAuth", "scheme"],
        message: "Unsupported HTTP auth scheme: digest",
      },
    })
  })
})
