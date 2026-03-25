import {beforeEach, describe, expect, it, vi} from "vitest"

const loadRuntime = async () => {
  let [Client, Schema] = await Promise.all([
    import("../lib/bs/src/Client.bs.js"),
    import("../lib/bs/src/Schema.bs.js"),
  ])

  return {Client, Schema}
}

const ok = value => ({TAG: "Ok", _0: value})
const error = value => ({TAG: "Error", _0: value})

describe("openapi-rescript-runtime", () => {
  beforeEach(() => {
    vi.restoreAllMocks()
  })

  it("encodes a JSON request body and decodes the typed JSON response", async () => {
    let fetchMock = vi.fn(async (_url, init) => {
      expect(init.method).toBe("POST")
      expect(init.headers.get("accept")).toBe("application/json")
      expect(init.headers.get("content-type")).toBe("application/json")
      expect(init.body).toBe(JSON.stringify({name: "Ada"}))

      return new Response(JSON.stringify({id: 7, name: "Ada"}), {
        status: 201,
        headers: {"content-type": "application/json"},
      })
    })

    vi.stubGlobal("fetch", fetchMock)

    let {Client, Schema} = await loadRuntime()
    let client = Client.make({
      baseUrl: "https://example.test",
      auth: [],
      defaultHeaders: [],
    })

    let userSchema = Schema.object_([
      Schema.field({name: "id", required: true}, Schema.int),
      Schema.field({name: "name", required: true}, Schema.string),
    ])

    let createUser = {
      name: "createUser",
      method: "post",
      path: "/users",
      parameters: [],
      requestBody: {
        required: true,
        schema: Schema.object_([Schema.field({name: "name", required: true}, Schema.string)]),
      },
      responses: [{statusCode: "201", schema: userSchema}],
      security: [],
      securitySchemes: [],
    }

    let result = await Client.callJson(client, createUser, {body: {name: "Ada"}})

    expect(result).toEqual(ok({id: 7, name: "Ada"}))
  })

  it("injects supported auth schemes into header, query, and cookie locations", async () => {
    let capturedUrls = []
    let capturedCookieHeaders = []
    let capturedAuthHeaders = []

    vi.stubGlobal(
      "fetch",
      vi.fn(async (url, init) => {
        capturedUrls.push(String(url))
        capturedCookieHeaders.push(init.headers.get("cookie"))
        capturedAuthHeaders.push(init.headers.get("authorization"))

        return new Response(JSON.stringify({ok: true}), {
          status: 200,
          headers: {"content-type": "application/json"},
        })
      }),
    )

    let {Client, Schema} = await loadRuntime()
    let responseSchema = Schema.object_([Schema.field({name: "ok", required: true}, Schema.bool)])

    let client = Client.make({
      baseUrl: "https://example.test/root/",
      auth: [
        {schemeName: "HeaderKey", value: "header-secret"},
        {schemeName: "QueryKey", value: "query-secret"},
        {schemeName: "CookieKey", value: "cookie-secret"},
        {schemeName: "BearerAuth", value: "bearer-token"},
      ],
      defaultHeaders: [],
    })

    let operation = {
      name: "listUsers",
      method: "get",
      path: "/users",
      parameters: [],
      requestBody: undefined,
      responses: [{statusCode: "200", schema: responseSchema}],
      security: [["HeaderKey", "QueryKey", "CookieKey"], ["BearerAuth"]],
      securitySchemes: [
        {name: "HeaderKey", authKind: "apiKey", credentialName: "x-api-key", location: "header"},
        {name: "QueryKey", authKind: "apiKey", credentialName: "api_key", location: "query"},
        {name: "CookieKey", authKind: "apiKey", credentialName: "session", location: "cookie"},
        {name: "BearerAuth", authKind: "httpBearer", credentialName: undefined, location: undefined},
      ],
    }

    let result = await Client.callJson(client, operation, {})

    expect(result).toEqual(ok({ok: true}))
    expect(capturedUrls).toEqual(["https://example.test/users?api_key=query-secret"])
    expect(capturedCookieHeaders).toEqual(["session=cookie-secret"])
    expect(capturedAuthHeaders).toEqual([null])
  })

  it("returns typed transport, request encoding, unexpected status, and response decode failures", async () => {
    let {Client, Schema} = await loadRuntime()
    let client = Client.make({
      baseUrl: "https://example.test",
      auth: [],
      defaultHeaders: [],
    })

    let operation = {
      name: "strictOperation",
      method: "post",
      path: "/strict",
      parameters: [],
      requestBody: {
        required: true,
        schema: Schema.object_([Schema.field({name: "enabled", required: true}, Schema.bool)]),
      },
      responses: [{statusCode: "200", schema: Schema.object_([Schema.field({name: "ok", required: true}, Schema.bool)])}],
      security: [],
      securitySchemes: [],
    }

    vi.stubGlobal("fetch", vi.fn(async () => new Response("{}", {status: 200, headers: {"content-type": "application/json"}})))
    let requestFailure = await Client.callJson(client, operation, {body: {enabled: "yes"}})
    expect(requestFailure).toEqual(
      error(
        expect.objectContaining({
          kind: "requestEncoding",
          operationName: "strictOperation",
        }),
      ),
    )

    vi.stubGlobal("fetch", vi.fn(async () => new Response("teapot", {status: 418})))
    let statusFailure = await Client.callJson(client, {...operation, requestBody: undefined}, {})
    expect(statusFailure).toEqual(
      error(
        expect.objectContaining({
          kind: "unexpectedStatus",
          status: 418,
        }),
      ),
    )

    vi.stubGlobal(
      "fetch",
      vi.fn(async () => new Response(JSON.stringify({ok: "nope"}), {status: 200, headers: {"content-type": "application/json"}})),
    )
    let decodeFailure = await Client.callJson(client, {...operation, requestBody: undefined}, {})
    expect(decodeFailure).toEqual(
      error(
        expect.objectContaining({
          kind: "responseDecode",
          operationName: "strictOperation",
        }),
      ),
    )

    vi.stubGlobal("fetch", vi.fn(async () => Promise.reject(new Error("network down"))))
    let transportFailure = await Client.callJson(client, {...operation, requestBody: undefined}, {})
    expect(transportFailure).toEqual(
      error(
        expect.objectContaining({
          kind: "transport",
          operationName: "strictOperation",
        }),
      ),
    )
  })

  it("does not treat declared non-2xx responses as successful results", async () => {
    let {Client, Schema} = await loadRuntime()
    let client = Client.make({
      baseUrl: "https://example.test",
      auth: [],
      defaultHeaders: [],
    })

    vi.stubGlobal(
      "fetch",
      vi.fn(async () => new Response(JSON.stringify({message: "missing"}), {status: 404, headers: {"content-type": "application/json"}})),
    )

    let operation = {
      name: "showUser",
      method: "get",
      path: "/users/1",
      parameters: [],
      requestBody: undefined,
      responses: [
        {
          statusCode: "404",
          schema: Schema.object_([Schema.field({name: "message", required: true}, Schema.string)]),
        },
      ],
      security: [],
      securitySchemes: [],
    }

    let result = await Client.callJson(client, operation, {})

    expect(result).toEqual(
      error(
        expect.objectContaining({
          kind: "unexpectedStatus",
          operationName: "showUser",
          status: 404,
        }),
      ),
    )
  })

  it("uses default responses as the success decoder fallback for unmatched 2xx statuses", async () => {
    let {Client, Schema} = await loadRuntime()
    let client = Client.make({
      baseUrl: "https://example.test",
      auth: [],
      defaultHeaders: [],
    })

    vi.stubGlobal(
      "fetch",
      vi.fn(async () => new Response(JSON.stringify({ok: true}), {status: 250, headers: {"content-type": "application/json"}})),
    )

    let operation = {
      name: "fallbackSuccess",
      method: "get",
      path: "/fallback",
      parameters: [],
      requestBody: undefined,
      responses: [
        {
          statusCode: "default",
          schema: Schema.object_([Schema.field({name: "ok", required: true}, Schema.bool)]),
        },
      ],
      security: [],
      securitySchemes: [],
    }

    let result = await Client.callJson(client, operation, {})

    expect(result).toEqual(ok({ok: true}))
  })

  it("does not use default success decoding when explicit 2xx responses are declared", async () => {
    let {Client, Schema} = await loadRuntime()
    let client = Client.make({
      baseUrl: "https://example.test",
      auth: [],
      defaultHeaders: [],
    })

    vi.stubGlobal(
      "fetch",
      vi.fn(async () => new Response(JSON.stringify({fallback: true}), {status: 250, headers: {"content-type": "application/json"}})),
    )

    let operation = {
      name: "mixedSuccesses",
      method: "get",
      path: "/mixed",
      parameters: [],
      requestBody: undefined,
      responses: [
        {
          statusCode: "200",
          schema: Schema.object_([Schema.field({name: "ok", required: true}, Schema.bool)]),
        },
        {
          statusCode: "default",
          schema: Schema.object_([Schema.field({name: "fallback", required: true}, Schema.bool)]),
        },
      ],
      security: [],
      securitySchemes: [],
    }

    let result = await Client.callJson(client, operation, {})

    expect(result).toEqual(
      error(
        expect.objectContaining({
          kind: "unexpectedStatus",
          operationName: "mixedSuccesses",
          status: 250,
        }),
      ),
    )
  })

  it("uses wildcard 2XX responses as explicit success decoders", async () => {
    let {Client, Schema} = await loadRuntime()
    let client = Client.make({
      baseUrl: "https://example.test",
      auth: [],
      defaultHeaders: [],
    })

    vi.stubGlobal(
      "fetch",
      vi.fn(async () => new Response(JSON.stringify({ok: true}), {status: 250, headers: {"content-type": "application/json"}})),
    )

    let operation = {
      name: "wildcardSuccess",
      method: "get",
      path: "/wildcard",
      parameters: [],
      requestBody: undefined,
      responses: [
        {
          statusCode: "2XX",
          schema: Schema.object_([Schema.field({name: "ok", required: true}, Schema.bool)]),
        },
      ],
      security: [],
      securitySchemes: [],
    }

    let result = await Client.callJson(client, operation, {})

    expect(result).toEqual(ok({ok: true}))
  })

  it("prefers exact success responses over wildcard matches regardless of response order", async () => {
    let {Client, Schema} = await loadRuntime()
    let client = Client.make({
      baseUrl: "https://example.test",
      auth: [],
      defaultHeaders: [],
    })

    vi.stubGlobal(
      "fetch",
      vi.fn(async () => new Response(JSON.stringify({exact: true}), {status: 200, headers: {"content-type": "application/json"}})),
    )

    let operation = {
      name: "exactBeforeWildcard",
      method: "get",
      path: "/precedence",
      parameters: [],
      requestBody: undefined,
      responses: [
        {
          statusCode: "2XX",
          schema: Schema.object_([Schema.field({name: "wildcard", required: true}, Schema.bool)]),
        },
        {
          statusCode: "200",
          schema: Schema.object_([Schema.field({name: "exact", required: true}, Schema.bool)]),
        },
      ],
      security: [],
      securitySchemes: [],
    }

    let result = await Client.callJson(client, operation, {})

    expect(result).toEqual(ok({exact: true}))
  })
})
