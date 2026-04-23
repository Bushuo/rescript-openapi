import {beforeEach, describe, expect, it, vi} from "vitest"

const loadRuntime = async () => {
  let [Client, Schema, Scalar, S] = await Promise.all([
    import("../src/Client.bs.js"),
    import("../src/Schema.bs.js"),
    import("../src/Scalar.bs.js"),
    import("../node_modules/sury/src/S.bs.js"),
  ])

  return {Client, Schema, Scalar, S}
}

const ok = value => ({TAG: "Ok", _0: value})
const error = value => ({TAG: "Error", _0: value})

describe("openapi-rescript-runtime", () => {
  beforeEach(() => {
    vi.restoreAllMocks()
  })

  it("maps string schemas through custom enum codecs", async () => {
    let {Schema, S} = await loadRuntime()

    let active = {TAG: "Active"}
    let unknown = value => ({TAG: "Unknown", _0: value})
    let openStatusSchema = Schema.stringMapped(
      value => (value === "Active" ? ok(active) : ok(unknown(value))),
      value => (value.TAG === "Unknown" ? value._0 : "Active"),
    )
    let closedStatusSchema = Schema.stringMapped(
      value => (value === "Active" ? ok(active) : error(`Unexpected enum value: ${value}`)),
      _value => "Active",
    )

    expect(S.parseJsonStringOrThrow(JSON.stringify("Active"), openStatusSchema)).toEqual(active)
    expect(S.parseJsonStringOrThrow(JSON.stringify("Paused"), openStatusSchema)).toEqual(unknown("Paused"))
    expect(() => S.parseJsonStringOrThrow(JSON.stringify("Paused"), closedStatusSchema)).toThrow(
      /Unexpected enum value: Paused/,
    )
    expect(S.reverseConvertToJsonStringOrThrow(active, openStatusSchema)).toBe(JSON.stringify("Active"))
    expect(S.reverseConvertToJsonStringOrThrow(unknown("Paused"), openStatusSchema)).toBe(JSON.stringify("Paused"))
  })

  it("builds string scalar schemas with the scalar functor", async () => {
    let {Scalar, S} = await loadRuntime()
    let Uuid = Scalar.MakeString({
      decode: value => (value.startsWith("id_") ? ok({value}) : error("Invalid UUID")),
      encode: uuid => uuid.value,
    })

    expect(S.parseJsonStringOrThrow(JSON.stringify("id_123"), Uuid.schema)).toEqual({
      value: "id_123",
    })
    expect(() => S.parseJsonStringOrThrow(JSON.stringify("bad"), Uuid.schema)).toThrow(
      /Invalid UUID/,
    )
    expect(S.reverseConvertToJsonStringOrThrow({value: "id_456"}, Uuid.schema)).toBe(
      JSON.stringify("id_456"),
    )
  })

  it("decodes nullable schemas as Null.t values", async () => {
    let {Schema, S} = await loadRuntime()
    let nullableString = Schema.nullableAsNull(Schema.string)

    expect(S.parseJsonStringOrThrow("null", nullableString)).toBeNull()
    expect(S.parseJsonStringOrThrow(JSON.stringify("Ada"), nullableString)).toBe("Ada")
    expect(S.reverseConvertToJsonStringOrThrow(null, nullableString)).toBe("null")
    expect(S.reverseConvertToJsonStringOrThrow("Ada", nullableString)).toBe(JSON.stringify("Ada"))
  })

  it("decodes optional nullable object fields as Nullable.t values", async () => {
    let {Schema, S} = await loadRuntime()
    let profileSchema = Schema.object_([Schema.makeOptionalNullableField("nickname", Schema.string)])

    expect(S.parseJsonStringOrThrow("{}", profileSchema)).toEqual({nickname: undefined})
    expect(S.parseJsonStringOrThrow(JSON.stringify({nickname: null}), profileSchema)).toEqual({
      nickname: null,
    })
    expect(S.parseJsonStringOrThrow(JSON.stringify({nickname: "Ada"}), profileSchema)).toEqual({
      nickname: "Ada",
    })
    expect(JSON.parse(S.reverseConvertToJsonStringOrThrow({nickname: undefined}, profileSchema))).toEqual({})
    expect(JSON.parse(S.reverseConvertToJsonStringOrThrow({nickname: null}, profileSchema))).toEqual({
      nickname: null,
    })
    expect(JSON.parse(S.reverseConvertToJsonStringOrThrow({nickname: "Ada"}, profileSchema))).toEqual({
      nickname: "Ada",
    })
  })

  it("decodes and re-encodes discriminated unions", async () => {
    let {Schema, S} = await loadRuntime()

    let genderSchema = Schema.discriminatedUnion("kind", [
        {
          tag: "Male",
          schema: Schema.object_([]),
          wrap: _payload => ({TAG: "Male"}),
          unwrap: value => (value.TAG === "Male" ? {} : undefined),
        },
        {
          tag: "Female",
          schema: Schema.object_([Schema.field({name: "value", required: true}, Schema.bool)]),
          wrap: payload => ({TAG: "Female", _0: payload}),
          unwrap: value => (value.TAG === "Female" ? value._0 : undefined),
        },
      ])

    expect(S.parseJsonStringOrThrow(JSON.stringify({kind: "Male"}), genderSchema)).toEqual({TAG: "Male"})
    expect(
      S.parseJsonStringOrThrow(JSON.stringify({kind: "Female", value: true}), genderSchema),
    ).toEqual({
      TAG: "Female",
      _0: {value: true},
    })
    expect(JSON.parse(S.reverseConvertToJsonStringOrThrow({TAG: "Male"}, genderSchema))).toEqual({
      kind: "Male",
    })
    expect(
      JSON.parse(
        S.reverseConvertToJsonStringOrThrow({TAG: "Female", _0: {value: true}}, genderSchema),
      ),
    ).toEqual({
      kind: "Female",
      value: true,
    })
  })

  it("reports missing and unknown discriminators precisely", async () => {
    let {Schema, S} = await loadRuntime()

    let genderSchema = Schema.discriminatedUnion("kind", [
        {
          tag: "Male",
          schema: Schema.object_([]),
          wrap: _payload => ({TAG: "Male"}),
          unwrap: value => (value.TAG === "Male" ? {} : undefined),
        },
      ])

    expect(() => S.parseJsonStringOrThrow(JSON.stringify({}), genderSchema)).toThrow(/kind/)
    expect(() => S.parseJsonStringOrThrow(JSON.stringify({kind: "Female"}), genderSchema)).toThrow(
      /Unknown discriminator value/,
    )
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
