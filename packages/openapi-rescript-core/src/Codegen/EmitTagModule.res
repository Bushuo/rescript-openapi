let paramsTypeName = (operation: Ir.operation): string => operation.name ++ "Params"

let defaultTag = "default"

let operationTags = (operation: Ir.operation): array<string> =>
  if Belt.Array.length(operation.tags) > 0 {
    operation.tags
  } else {
    [defaultTag]
  }

let isSuccessStatus = (statusCode: string): bool =>
  String.startsWith(statusCode, "2")

let effectiveSecurity = (~document: Ir.document, ~operation: Ir.operation): array<array<string>> =>
  if Belt.Array.length(operation.security) > 0 {
    operation.security
  } else {
    document.security
  }

let operationResultType = (operation: Ir.operation): string =>
  switch Belt.Array.getBy(operation.responses, response => isSuccessStatus(response.statusCode)) {
  | Some({schema: Some(schema)}) => Printer.modelType(~qualifiedNamedRefs=true, schema)
  | Some({schema: None}) => "unit"
  | None => "unit"
  }

let renderParameterField = (parameter: Ir.parameter): string =>
  Printer.indentLine(
    ~level=1,
    parameter.name
    ++ ": "
    ++ (
      if parameter.required {
        Printer.modelType(~qualifiedNamedRefs=true, parameter.schema)
      } else {
        "option<" ++ Printer.modelType(~qualifiedNamedRefs=true, parameter.schema) ++ ">"
      }
    )
    ++ ",",
  )

let renderParamsType = (operation: Ir.operation): array<string> => {
  let bodyField =
    switch operation.requestBody {
    | None => []
    | Some(body) => [
        Printer.indentLine(
          ~level=1,
          "body: "
          ++ (
            if body.required {
              Printer.modelType(~qualifiedNamedRefs=true, body.schema)
            } else {
              "option<" ++ Printer.modelType(~qualifiedNamedRefs=true, body.schema) ++ ">"
            }
          )
          ++ ",",
        ),
      ]
    }

  let fields = Belt.Array.concat(Belt.Array.map(operation.parameters, renderParameterField), bodyField)

  Belt.Array.concatMany([
    ["type " ++ paramsTypeName(operation) ++ " = {"],
    fields,
    ["}"],
  ])
}

let renderParameter = (parameter: Ir.parameter): array<string> => [
  "    {",
  "      name: " ++ Printer.quote(parameter.name) ++ ",",
  "      location: " ++ Printer.quote(parameter.location) ++ ",",
  "      required: " ++ Printer.boolLiteral(parameter.required) ++ ",",
  "      schema: " ++ Printer.schemaExpr(~qualified=true, parameter.schema) ++ ",",
  "    },",
]

let renderRequestBody = (requestBody: option<Ir.requestBody>): array<string> =>
  switch requestBody {
  | None => ["  requestBody: None,"]
  | Some(body) => [
      "  requestBody: Some({",
      "    required: " ++ Printer.boolLiteral(body.required) ++ ",",
      "    schema: " ++ Printer.schemaExpr(~qualified=true, body.schema) ++ ",",
      "  }),",
    ]
  }

let renderResponse = (response: Ir.response): array<string> => {
  let schemaLine =
    switch response.schema {
    | None => "None"
    | Some(schema) => "Some(" ++ Printer.schemaExpr(~qualified=true, schema) ++ ")"
    }

  [
    "    {",
    "      statusCode: " ++ Printer.quote(response.statusCode) ++ ",",
    "      schema: " ++ schemaLine ++ ",",
    "    },",
  ]
}

let renderOperationValue = (~document: Ir.document, operation: Ir.operation): array<string> => {
  let parameterLines = ref([])
  Belt.Array.forEach(operation.parameters, parameter =>
    parameterLines.contents = Belt.Array.concat(parameterLines.contents, renderParameter(parameter))
  )

  let responseLines = ref([])
  Belt.Array.forEach(operation.responses, response =>
    responseLines.contents = Belt.Array.concat(responseLines.contents, renderResponse(response))
  )

  Belt.Array.concatMany([
    ["let " ++ operation.name ++ "Operation: Client.jsonOperation = {"],
    ["  name: " ++ Printer.quote(operation.name) ++ ","],
    ["  method: " ++ Printer.quote(operation.method) ++ ","],
    ["  path: " ++ Printer.quote(operation.path) ++ ","],
    ["  tags: " ++ Printer.stringArray(operation.tags) ++ ","],
    if Belt.Array.length(parameterLines.contents) == 0 {
      ["  parameters: [],"]
    } else {
      Belt.Array.concatMany([
        ["  parameters: ["],
        parameterLines.contents,
        ["  ],"],
      ])
    },
    renderRequestBody(operation.requestBody),
    ["  responses: ["],
    responseLines.contents,
    ["  ],"],
    ["  security: " ++ Printer.stringMatrix(effectiveSecurity(~document, ~operation)) ++ ","],
    ["}"],
  ])
}

let renderOperationFunction = (operation: Ir.operation): array<string> => [
  "let " ++ operation.name ++ " = (",
  "  client: Client.t,",
  "  params: " ++ paramsTypeName(operation) ++ ",",
  "): promise<result<" ++ operationResultType(operation) ++ ", Client.operationError>> =>",
  "  Client.callJson(client, " ++ operation.name ++ "Operation, params)",
]

let renderOperation = (~document: Ir.document, operation: Ir.operation): array<string> =>
  Belt.Array.concatMany([
    renderParamsType(operation),
    [""],
    renderOperationValue(~document, operation),
    [""],
    renderOperationFunction(operation),
  ])

let collectTags = (document: Ir.document): array<string> => {
  let tags = ref([])

  Belt.Array.forEach(document.tags, tag => {
    if !Belt.Array.some(tags.contents, existing => existing == tag) {
      tags.contents = Belt.Array.concat(tags.contents, [tag])
    }
  })

  Belt.Array.forEach(document.operations, operation => {
    Belt.Array.forEach(operationTags(operation), tag => {
      if !Belt.Array.some(tags.contents, existing => existing == tag) {
        tags.contents = Belt.Array.concat(tags.contents, [tag])
      }
    })
  })

  tags.contents
}

let operationHasTag = (~tag: string, ~operation: Ir.operation): bool =>
  Belt.Array.some(operationTags(operation), operationTag => operationTag == tag)

let emitForTag = (~document: Ir.document, ~tag: string, ~operations: array<Ir.operation>): Printer.file => {
  let body = ref([])

  Belt.Array.forEachWithIndex(operations, (index, operation) => {
    if index > 0 {
      body.contents = Belt.Array.concat(body.contents, [""])
    }

    body.contents = Belt.Array.concat(body.contents, renderOperation(~document, operation))
  })

  Printer.makeFile(
    ~path=Printer.moduleName(tag) ++ ".res",
    ~lines=Belt.Array.concat([
      "// Generated by openapi-rescript-core.",
      "",
    ], body.contents),
  )
}

let emitAll = (document: Ir.document): array<Printer.file> => {
  let tags = collectTags(document)
  let files = ref([])

  Belt.Array.forEach(tags, tag => {
    let operations = Belt.Array.keep(document.operations, operation => operationHasTag(~tag, ~operation))
    files.contents = Belt.Array.concat(files.contents, [emitForTag(~document, ~tag, ~operations)])
  })

  files.contents
}

let moduleNames = (document: Ir.document): array<string> =>
  Belt.Array.map(collectTags(document), Printer.moduleName)
