import {readFileSync} from "node:fs"
import {describe, expect, it} from "vitest"
import {generate} from "../src/OpenapiGenerator.bs.js"

const normalizedPetstore = JSON.parse(
  readFileSync(new URL("./fixtures/petstore.normalized.json", import.meta.url), "utf8"),
)
const duplicateOperationIds = JSON.parse(
  readFileSync(new URL("./fixtures/duplicate-operation-id.normalized.json", import.meta.url), "utf8"),
)
const authenticatedApi = JSON.parse(
  readFileSync(new URL("./fixtures/authenticated-api.normalized.json", import.meta.url), "utf8"),
)
const normalizedEnums = JSON.parse(
  readFileSync(new URL("./fixtures/enums.normalized.json", import.meta.url), "utf8"),
)

const generatedFile = (output, path) => output.files.find(file => file.path === path)?.contents

describe("naming and auth normalization", () => {
  it("prefers unique operationId values for normalized operation names", () => {
    let output = generate(normalizedPetstore)

    expect(output.ok).toBe(true)
    expect(output.value.operations.map(operation => operation.name)).toEqual([
      "listPets",
      "createPet",
    ])
  })

  it("normalizes all-uppercase tokens into stable lower-camel names", () => {
    let uppercaseOperationId = {
      openapi: "3.1.0",
      info: {
        title: "Uppercase Operation IDs API",
        version: "1.0.0",
      },
      paths: {
        "/pets": {
          get: {
            operationId: "LIST_PETS",
            responses: {
              200: {
                description: "ok",
              },
            },
          },
        },
      },
    }

    let output = generate(uppercaseOperationId)
    expect(output.ok).toBe(true)
    expect(output.value.operations.map(operation => operation.name)).toEqual(["listPets"])
  })

  it("makes normalized operation names safe for ReScript codegen", () => {
    let reservedWordOperationId = {
      openapi: "3.1.0",
      info: {
        title: "Reserved Words API",
        version: "1.0.0",
      },
      paths: {
        "/types": {
          get: {
            operationId: "type",
            responses: {
              200: {
                description: "ok",
              },
            },
          },
        },
        "/await": {
          post: {
            operationId: "await",
            responses: {
              200: {
                description: "ok",
              },
            },
          },
        },
        "/eval": {
          put: {
            operationId: "eval",
            responses: {
              200: {
                description: "ok",
              },
            },
          },
        },
        "/arguments": {
          delete: {
            operationId: "arguments",
            responses: {
              200: {
                description: "ok",
              },
            },
          },
        },
      },
    }

    let output = generate(reservedWordOperationId)
    expect(output.ok).toBe(true)
    expect(output.value.operations.map(operation => operation.name)).toEqual([
      "type_",
      "await_",
      "eval_",
      "arguments_",
    ])
  })

  it("derives stable operation names when operationId is missing or duplicated", () => {
    let output = generate(duplicateOperationIds)

    expect(output.ok).toBe(true)
    expect(
      output.value.operations.map(operation => ({
        operationId: operation.operationId,
        name: operation.name,
      })),
    ).toEqual([
      {
        operationId: "listPets",
        name: "getPets",
      },
      {
        operationId: "listPets",
        name: "postPets",
      },
      {
        operationId: undefined,
        name: "getPetsByPetId",
      },
      {
        operationId: "deletePet",
        name: "deletePet",
      },
    ])
  })

  it("falls back to derived names when distinct operationIds sanitize to the same identifier", () => {
    let sanitizingCollision = {
      openapi: "3.1.0",
      info: {
        title: "Sanitizing Collision API",
        version: "1.0.0",
      },
      paths: {
        "/pets": {
          get: {
            operationId: "list-pets",
            responses: {
              200: {
                description: "ok",
              },
            },
          },
          post: {
            operationId: "list_pets",
            responses: {
              201: {
                description: "ok",
              },
            },
          },
        },
      },
    }

    let output = generate(sanitizingCollision)
    expect(output.ok).toBe(true)
    expect(output.value.operations.map(operation => operation.name)).toEqual(["getPets", "postPets"])
  })

  it("rejects unresolved operation naming collisions with a precise diagnostic", () => {
    let collidingOperations = {
      openapi: "3.1.0",
      info: {
        title: "Colliding API",
        version: "1.0.0",
      },
      paths: {
        "/pets-tag": {
          get: {
            responses: {
              200: {
                description: "ok",
              },
            },
          },
        },
        "/pets_tag": {
          get: {
            responses: {
              200: {
                description: "ok",
              },
            },
          },
        },
      },
    }

    expect(generate(collidingOperations)).toMatchObject({
      ok: false,
      error: {
        path: ["paths", "/pets_tag", "get"],
        message: "Operation name collision after normalization: getPetsTag",
      },
    })
  })

  it("normalizes supported auth schemes into codegen-ready metadata", () => {
    let output = generate(authenticatedApi)

    expect(output.ok).toBe(true)
    expect(Object.fromEntries(output.value.securitySchemes.map(scheme => [scheme.name, scheme]))).toEqual({
      ApiKeyCookie: {
        name: "ApiKeyCookie",
        authKind: "apiKey",
        credentialName: "session",
        location: "cookie",
      },
      ApiKeyHeader: {
        name: "ApiKeyHeader",
        authKind: "apiKey",
        credentialName: "X-API-Key",
        location: "header",
      },
      ApiKeyQuery: {
        name: "ApiKeyQuery",
        authKind: "apiKey",
        credentialName: "api_key",
        location: "query",
      },
      BasicAuth: {
        name: "BasicAuth",
        authKind: "httpBasic",
        credentialName: undefined,
        location: undefined,
      },
      BearerAuth: {
        name: "BearerAuth",
        authKind: "httpBearer",
        credentialName: undefined,
        location: undefined,
      },
    })
    expect(output.value.security).toEqual([["BearerAuth"]])
    expect(output.value.operations.map(operation => operation.security)).toEqual([
      [["BearerAuth"]],
      [["BasicAuth"]],
      [["ApiKeyHeader"], ["ApiKeyQuery"], ["ApiKeyCookie"]],
    ])
  })

  it("lifts reachable enums into deterministic generated model type names", () => {
    let output = generate(normalizedEnums)
    let generatedModels = generatedFile(output, "Models.res")

    expect(output.ok).toBe(true)
    expect(generatedModels).toContain("type listUsersParamSort =")
    expect(generatedModels).toContain("type createSessionRequestState =")
    expect(generatedModels).toContain("type getSessionResponse200State =")
  })

  it("rejects lifted enum type name collisions after normalization", () => {
    let collidingInlineEnums = {
      openapi: "3.1.0",
      info: {
        title: "Enum Type Collision API",
        version: "1.0.0",
      },
      paths: {
        "/users": {
          get: {
            operationId: "listUsers",
            parameters: [
              {
                name: "sort-order",
                in: "query",
                schema: {
                  type: "string",
                  enum: ["asc", "desc"],
                },
              },
              {
                name: "sort_order",
                in: "query",
                schema: {
                  type: "string",
                  enum: ["newest", "oldest"],
                },
              },
            ],
            responses: {
              200: {
                description: "ok",
              },
            },
          },
        },
      },
    }

    expect(generate(collidingInlineEnums)).toMatchObject({
      ok: false,
      error: {
        path: ["paths", "/users", "get", "parameters", "1", "schema"],
        message: "Enum type name collision after normalization: listUsersParamSortOrder",
      },
    })
  })

  it("rejects collisions between lifted enum names and existing schema names after normalization", () => {
    let collidingExistingSchema = {
      openapi: "3.1.0",
      info: {
        title: "Enum Existing Schema Collision API",
        version: "1.0.0",
      },
      components: {
        schemas: {
          ListUsersParamSort: {
            type: "string",
          },
        },
      },
      paths: {
        "/users": {
          get: {
            operationId: "listUsers",
            parameters: [
              {
                name: "sort",
                in: "query",
                schema: {
                  type: "string",
                  enum: ["asc", "desc"],
                },
              },
            ],
            responses: {
              200: {
                description: "ok",
              },
            },
          },
        },
      },
    }

    expect(generate(collidingExistingSchema)).toMatchObject({
      ok: false,
      error: {
        path: ["paths", "/users", "get", "parameters", "0", "schema"],
        message: "Enum type name collision after normalization: listUsersParamSort",
      },
    })
  })

  it("uses response status codes to keep lifted response enum names distinct", () => {
    let distinctResponseEnums = {
      openapi: "3.1.0",
      info: {
        title: "Distinct Response Enum API",
        version: "1.0.0",
      },
      paths: {
        "/sessions/{sessionId}": {
          get: {
            operationId: "getSession",
            responses: {
              200: {
                description: "ok",
                content: {
                  "application/json": {
                    schema: {
                      type: "object",
                      required: ["state"],
                      properties: {
                        state: {
                          type: "string",
                          enum: ["active", "archived"],
                        },
                      },
                    },
                  },
                },
              },
              400: {
                description: "bad request",
                content: {
                  "application/json": {
                    schema: {
                      type: "object",
                      required: ["state"],
                      properties: {
                        state: {
                          type: "string",
                          enum: ["invalid", "missing"],
                        },
                      },
                    },
                  },
                },
              },
            },
          },
        },
      },
    }

    let output = generate(distinctResponseEnums)
    let generatedModels = generatedFile(output, "Models.res")

    expect(output.ok).toBe(true)
    expect(generatedModels).toContain("type getSessionResponse200State =")
    expect(generatedModels).toContain("type getSessionResponse400State =")
  })

  it("rejects enum constructor collisions after normalization", () => {
    let collidingConstructors = {
      openapi: "3.1.0",
      info: {
        title: "Enum Constructor Collision API",
        version: "1.0.0",
      },
      paths: {
        "/sessions": {
          post: {
            operationId: "createSession",
            requestBody: {
              required: true,
              content: {
                "application/json": {
                  schema: {
                    type: "object",
                    required: ["state"],
                    properties: {
                      state: {
                        type: "string",
                        enum: ["in-progress", "in_progress"],
                      },
                    },
                  },
                },
              },
            },
            responses: {
              201: {
                description: "created",
              },
            },
          },
        },
      },
    }

    expect(generate(collidingConstructors)).toMatchObject({
      ok: false,
      error: {
        path: [
          "paths",
          "/sessions",
          "post",
          "requestBody",
          "content",
          "application/json",
          "schema",
          "properties",
          "state",
          "enum",
          "1",
        ],
        message: "Enum constructor collision after normalization: InProgress",
      },
    })
  })

  it("rejects discriminated-union constructor collisions after normalization", () => {
    let collidingUnionFixture = {
      openapi: "3.1.0",
      info: {
        title: "Union Constructor Collision API",
        version: "1.0.0",
      },
      paths: {},
      components: {
        schemas: {
          Gender: {
            oneOf: [
              {
                type: "object",
                required: ["kind"],
                properties: {
                  kind: {
                    type: "string",
                    enum: ["Prefer-Not-To-Say"],
                  },
                },
              },
              {
                type: "object",
                required: ["kind"],
                properties: {
                  kind: {
                    type: "string",
                    enum: ["Prefer_Not_To_Say"],
                  },
                },
              },
            ],
          },
        },
      },
    }

    expect(generate(collidingUnionFixture)).toMatchObject({
      ok: false,
      error: {
        path: ["components", "schemas", "Gender", "oneOf", "1", "properties", "kind", "enum", "0"],
        message: "Enum constructor collision after normalization: PreferNotToSay",
      },
    })
  })

  it("rejects unsupported OAuth security schemes", () => {
    let unsupportedAuth = {
      ...authenticatedApi,
      components: {
        ...authenticatedApi.components,
        securitySchemes: {
          OAuthFlow: {
            type: "oauth2",
            flows: {
              clientCredentials: {
                tokenUrl: "https://example.com/token",
                scopes: {},
              },
            },
          },
        },
      },
      security: [{OAuthFlow: []}],
    }

    expect(generate(unsupportedAuth)).toMatchObject({
      ok: false,
      error: {
        path: ["components", "securitySchemes", "OAuthFlow", "type"],
        message: "Unsupported security scheme: oauth2",
      },
    })
  })
})
