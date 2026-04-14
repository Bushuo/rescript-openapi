module S = S

type url
type searchParams

@new
external makeUrl: (string, string) => url = "URL"
@send
external toString: url => string = "toString"
@get
external searchParams: url => searchParams = "searchParams"
@send
external appendSearchParam: (searchParams, string, string) => unit = "append"
@val
external encodeURIComponent: string => string = "encodeURIComponent"
@val
external btoa: string => string = "btoa"
external methodFromString: string => Fetch.method = "%identity"
external dictFromUnknown: 'a => dict<unknown> = "%identity"
@send
external replaceAllString: (string, string, string) => string = "replaceAll"
type authCredential = {
  schemeName: string,
  value: string,
}

type t = {
  baseUrl: string,
  auth: array<authCredential>,
  defaultHeaders: array<(string, string)>,
}

type parameter = {
  name: string,
  location: string,
  required: bool,
  schema: Schema.any,
}

type requestBody = {
  required: bool,
  schema: Schema.any,
}

type response = {
  statusCode: string,
  schema: option<unknown>,
}

type securityScheme = {
  name: string,
  authKind: string,
  credentialName: option<string>,
  location: option<string>,
}

type jsonOperation = {
  name: string,
  method: string,
  path: string,
  tags: array<string>,
  parameters: array<parameter>,
  requestBody: option<requestBody>,
  responses: array<response>,
  security: array<array<string>>,
  securitySchemes: array<securityScheme>,
}

let make = (config: t): t => config

let isSuccessStatus = (status: int): bool => status >= 200 && status < 300

let exnMessage = (error: exn): string =>
  switch JsExn.message(Obj.magic(error)) {
  | Some(message) => message
  | None => "Unknown error"
  }

let getValue = (params: 'params, key: string): option<unknown> =>
  Dict.get(dictFromUnknown(params), key)

let hasValue = (params: 'params, key: string): bool =>
  switch getValue(params, key) {
  | Some(_) => true
  | None => false
  }

let findCredential = (client: t, schemeName: string): option<authCredential> =>
  Array.find(client.auth, credential => credential.schemeName == schemeName)

let findSecurityScheme = (operation: jsonOperation, schemeName: string): option<securityScheme> =>
  Array.find(operation.securitySchemes, scheme => scheme.name == schemeName)

let isRequirementSatisfied = (
  client: t,
  operation: jsonOperation,
  requirement: array<string>,
): bool =>
  Array.every(requirement, schemeName =>
    switch (findCredential(client, schemeName), findSecurityScheme(operation, schemeName)) {
    | (Some(_), Some(_)) => true
    | _ => false
    }
  )

let resolveSecurityRequirement = (client: t, operation: jsonOperation): option<array<string>> =>
  Array.find(operation.security, requirement =>
    isRequirementSatisfied(client, operation, requirement)
  )

let reverseJsonString = (value: unknown, schema: Schema.any): string =>
  S.reverseConvertToJsonStringOrThrow(value, schema)

let scalarToString = (json: JSON.t): string =>
  switch JSON.Decode.string(json) {
  | Some(value) => value
  | None =>
    switch JSON.Decode.float(json) {
    | Some(value) => Float.toString(value)
    | None =>
      switch JSON.Decode.bool(json) {
      | Some(value) =>
        if value {
          "true"
        } else {
          "false"
        }
      | None =>
        switch JSON.Decode.null(json) {
        | Some(_) => "null"
        | None => JSON.stringifyAny(json)->Option.getOr("")
        }
      }
    }
  }

let encodeScalar = (value: unknown, schema: Schema.any): string =>
  reverseJsonString(value, schema)->JSON.parseOrThrow->scalarToString

let replacePathParameter = (path: string, name: string, value: string): string =>
  path->replaceAllString("{" ++ name ++ "}", encodeURIComponent(value))

let setHeaderIfAbsent = (headers: Fetch.Headers.t, name: string, value: string) =>
  if !(headers->Fetch.Headers.has(name)) {
    headers->Fetch.Headers.set(name, value)
  }

let appendCookie = (headers: Fetch.Headers.t, name: string, value: string) => {
  let nextValue = switch headers->Fetch.Headers.get("cookie") {
  | Some(existing) if existing != "" => existing ++ "; " ++ name ++ "=" ++ value
  | _ => name ++ "=" ++ value
  }

  headers->Fetch.Headers.set("cookie", nextValue)
}

let applySecurity = (
  client: t,
  operation: jsonOperation,
  resolvedUrl: url,
  headers: Fetch.Headers.t,
) =>
  switch resolveSecurityRequirement(client, operation) {
  | None => ()
  | Some(requirement) =>
    Array.forEach(requirement, schemeName =>
      switch (findCredential(client, schemeName), findSecurityScheme(operation, schemeName)) {
      | (Some(credential), Some(scheme)) =>
        switch scheme.authKind {
        | "apiKey" =>
          switch (scheme.credentialName, scheme.location) {
          | (Some(name), Some("header")) => headers->Fetch.Headers.set(name, credential.value)
          | (Some(name), Some("query")) =>
            resolvedUrl->searchParams->appendSearchParam(name, credential.value)
          | (Some(name), Some("cookie")) => headers->appendCookie(name, credential.value)
          | _ => ()
          }
        | "httpBearer" => headers->setHeaderIfAbsent("authorization", "Bearer " ++ credential.value)
        | "httpBasic" =>
          headers->setHeaderIfAbsent("authorization", "Basic " ++ btoa(credential.value))
        | _ => ()
        }
      | _ => ()
      }
    )
  }

let applyParameters = (operation: jsonOperation, params: 'params, headers: Fetch.Headers.t): result<
  (string, array<(string, string)>),
  OperationError.t,
> => {
  let path = ref(operation.path)
  let queryParams = ref([])

  try {
    Array.forEach(operation.parameters, parameter =>
      switch getValue(params, parameter.name) {
      | None =>
        if parameter.required {
          throw(Failure("Missing required parameter: " ++ parameter.name))
        }
      | Some(value) =>
        let encoded = encodeScalar(value, parameter.schema)

        switch parameter.location {
        | "path" => path.contents = replacePathParameter(path.contents, parameter.name, encoded)
        | "query" =>
          queryParams.contents = Belt.Array.concat(
            queryParams.contents,
            [(parameter.name, encoded)],
          )
        | "header" => headers->Fetch.Headers.set(parameter.name, encoded)
        | "cookie" => headers->appendCookie(parameter.name, encoded)
        | _ => ()
        }
      }
    )

    Ok((path.contents, queryParams.contents))
  } catch {
  | error =>
    Error(OperationError.requestEncoding(~operationName=operation.name, ~message=exnMessage(error)))
  }
}

let encodeRequestBody = (
  operation: jsonOperation,
  params: 'params,
  headers: Fetch.Headers.t,
): result<option<Fetch.Body.t>, OperationError.t> =>
  switch operation.requestBody {
  | None => Ok(None)
  | Some(requestBody) =>
    switch getValue(params, "body") {
    | None =>
      if requestBody.required {
        Error(
          OperationError.requestEncoding(
            ~operationName=operation.name,
            ~message="Missing required request body",
          ),
        )
      } else {
        Ok(None)
      }
    | Some(body) =>
      try {
        let validated = S.parseOrThrow(body, requestBody.schema)
        let encoded = reverseJsonString(validated, requestBody.schema)
        headers->Fetch.Headers.set("content-type", "application/json")
        Ok(Some(Fetch.Body.string(encoded)))
      } catch {
      | error =>
        Error(
          OperationError.requestEncoding(~operationName=operation.name, ~message=exnMessage(error)),
        )
      }
    }
  }

let matchesStatusCode = (statusCode: string, status: int): bool => {
  let statusText = Int.toString(status)
  let patternLength = String.length(statusCode)

  if patternLength != String.length(statusText) {
    false
  } else {
    let rec loop = index =>
      if index >= patternLength {
        true
      } else {
        switch (String.get(statusCode, index), String.get(statusText, index)) {
        | (Some(expected), Some(actual)) =>
          if expected == actual || expected == "X" {
            loop(index + 1)
          } else {
            false
          }
        | _ => false
        }
      }

    loop(0)
  }
}

let findExactResponse = (operation: jsonOperation, status: int): option<response> =>
  Array.find(operation.responses, response => response.statusCode == Int.toString(status))

let findWildcardResponse = (operation: jsonOperation, status: int): option<response> =>
  Array.find(operation.responses, response =>
    response.statusCode != Int.toString(status) && matchesStatusCode(response.statusCode, status)
  )

let findExplicitResponse = (operation: jsonOperation, status: int): option<response> =>
  switch findExactResponse(operation, status) {
  | Some(response) => Some(response)
  | None => findWildcardResponse(operation, status)
  }

let findDefaultResponse = (operation: jsonOperation): option<response> =>
  Array.find(operation.responses, response => response.statusCode == "default")

let hasExplicitSuccessResponse = (operation: jsonOperation): bool =>
  Array.some(operation.responses, response => String.startsWith(response.statusCode, "2"))

let findSuccessResponse = (operation: jsonOperation, status: int): option<response> =>
  switch findExplicitResponse(operation, status) {
  | Some(response) => Some(response)
  | None =>
    if hasExplicitSuccessResponse(operation) {
      None
    } else {
      findDefaultResponse(operation)
    }
  }

let makeRequestInit = (
  ~method_: Fetch.method,
  ~headers: Fetch.Headers.t,
  ~body: option<Fetch.Body.t>=None,
): Fetch.Request.init =>
  switch body {
  | Some(body) => {method: method_, headers, body}
  | None => {method: method_, headers}
  }

let finishJsonRequest: (
  jsonOperation,
  url,
  Fetch.Headers.t,
  option<Fetch.Body.t>,
) => promise<result<'response, OperationError.t>> = async (
  operation: jsonOperation,
  requestUrl: url,
  requestHeaders: Fetch.Headers.t,
  body: option<Fetch.Body.t>,
): result<'response, OperationError.t> => {
  try {
    let response = await Fetch.fetch(
      requestUrl->toString,
      makeRequestInit(
        ~method_=methodFromString(operation.method->String.toUpperCase),
        ~headers=requestHeaders,
        ~body,
      ),
    )
    let status = response->Fetch.Response.status
    let responseText = await response->Fetch.Response.text

    switch (isSuccessStatus(status), findSuccessResponse(operation, status)) {
    | (false, _) =>
      Error(
        OperationError.unexpectedStatus(
          ~operationName=operation.name,
          ~status,
          ~body=responseText,
        ),
      )
    | (true, None) =>
      Error(
        OperationError.unexpectedStatus(
          ~operationName=operation.name,
          ~status,
          ~body=responseText,
        ),
      )
    | (true, Some({schema: None})) => Ok(Obj.magic())
    | (true, Some({schema: Some(schema)})) =>
      try {
        let responseSchema: Schema.any = Obj.magic(schema)
        Ok(Obj.magic(S.parseJsonStringOrThrow(responseText, responseSchema)))
      } catch {
      | error =>
        Error(
          OperationError.responseDecode(
            ~operationName=operation.name,
            ~message=exnMessage(error),
            ~status,
            ~body=responseText,
          ),
        )
      }
    }
  } catch {
  | error =>
    Error(OperationError.transport(~operationName=operation.name, ~message=exnMessage(error)))
  }
}

let callJson: (t, jsonOperation, 'params) => promise<result<'response, OperationError.t>> = async (
  client: t,
  operation: jsonOperation,
  params: 'params,
): result<'response, OperationError.t> => {
  let headers = Fetch.Headers.fromArray(client.defaultHeaders)
  headers->Fetch.Headers.set("accept", "application/json")

  switch applyParameters(operation, params, headers) {
  | Error(error) => Error(error)
  | Ok((path, queryParams)) =>
    let requestUrl = makeUrl(path, client.baseUrl)
    Array.forEach(queryParams, ((name, value)) =>
      requestUrl->searchParams->appendSearchParam(name, value)
    )
    let requestHeaders = Fetch.Headers.clone(headers)
    applySecurity(client, operation, requestUrl, requestHeaders)

    switch encodeRequestBody(operation, params, requestHeaders) {
    | Error(error) => Error(error)
    | Ok(body) => await finishJsonRequest(operation, requestUrl, requestHeaders, body)
    }
  }
}
