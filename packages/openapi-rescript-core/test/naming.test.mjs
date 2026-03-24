import {readFileSync} from "node:fs"
import {describe, expect, it} from "vitest"
import {generate} from "../lib/js/src/OpenapiGenerator.bs.js"

const normalizedPetstore = JSON.parse(
  readFileSync(new URL("./fixtures/petstore.normalized.json", import.meta.url), "utf8"),
)
const duplicateOperationIds = JSON.parse(
  readFileSync(new URL("./fixtures/duplicate-operation-id.normalized.json", import.meta.url), "utf8"),
)
const authenticatedApi = JSON.parse(
  readFileSync(new URL("./fixtures/authenticated-api.normalized.json", import.meta.url), "utf8"),
)

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
      },
    }

    let output = generate(reservedWordOperationId)
    expect(output.ok).toBe(true)
    expect(output.value.operations.map(operation => operation.name)).toEqual(["type_", "await_"])
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
