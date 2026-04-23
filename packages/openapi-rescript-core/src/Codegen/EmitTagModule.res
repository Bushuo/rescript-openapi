let paramsTypeName = (operation: Ir.operation): string => operation.name ++ "Params"

let defaultTag = "default"

type tagModule = {
  tag: string,
  moduleName: string,
}

let operationTags = (operation: Ir.operation): array<string> =>
  if Array.length(operation.tags) > 0 {
    operation.tags
  } else {
    [defaultTag]
  }

let isSuccessStatus = (statusCode: string): bool => String.startsWith(statusCode, "2")

let effectiveSecurity = (~document: Ir.document, ~operation: Ir.operation): array<array<string>> =>
  switch operation.security {
  | Some(security) => security
  | None => document.security
  }

let operationResultTypeName = (operation: Ir.operation): string => operation.name ++ "Result"

let rec renderAnonymousResultType = (
  ~baseName: string,
  schema: Ir.schema,
): (string, array<string>) =>
  switch schema {
  | Ir.Object(_) =>
    (
      baseName,
      [
        "type " ++
        baseName ++
        " = " ++
        Printer.modelType(~qualifiedNamedRefs=true, schema),
      ],
    )
  | Ir.Array(item) =>
    let (itemType, aliasLines) = renderAnonymousResultType(
      ~baseName=baseName ++ "Item",
      item,
    )
    ("array<" ++ itemType ++ ">", aliasLines)
  | Ir.Nullable(inner) =>
    let (innerType, aliasLines) = renderAnonymousResultType(
      ~baseName=baseName ++ "Value",
      inner,
    )
    ("Null.t<" ++ innerType ++ ">", aliasLines)
  | _ => (Printer.modelType(~qualifiedNamedRefs=true, schema), [])
  }

let operationResultType = (operation: Ir.operation): (string, array<string>) =>
  switch Array.find(operation.responses, response => isSuccessStatus(response.statusCode)) {
  | Some({schema: Some(schema)}) =>
    renderAnonymousResultType(~baseName=operationResultTypeName(operation), schema)
  | Some({schema: None}) => ("unit", [])
  | None =>
    switch Array.find(operation.responses, response => response.statusCode == "default") {
    | Some({schema: Some(schema)}) =>
      renderAnonymousResultType(~baseName=operationResultTypeName(operation), schema)
    | Some({schema: None}) => ("unit", [])
    | None => ("unit", [])
    }
  }

let renderParameterField = (
  ~quoteLabels: bool,
  parameter: Ir.parameter,
): string =>
  Printer.indentLine(
    ~level=1,
    Printer.recordLabel(~quoteAll=quoteLabels, parameter.name) ++
    ": " ++
    if parameter.required {
      Printer.modelType(~qualifiedNamedRefs=true, parameter.schema)
    } else {
      Printer.optionalModelType(~qualifiedNamedRefs=true, parameter.schema)
    } ++ ",",
  )

let renderParamsType = (operation: Ir.operation): array<string> => {
  let fieldNames = Belt.Array.concat(
    Array.map(operation.parameters, parameter => parameter.name),
    switch operation.requestBody {
    | Some(_) => ["body"]
    | None => []
    },
  )
  let quoteLabels = Printer.shouldQuoteRecordLabels(fieldNames)

  let bodyField = switch operation.requestBody {
  | None => []
  | Some(body) => [
      Printer.indentLine(
        ~level=1,
        Printer.recordLabel(~quoteAll=quoteLabels, "body") ++
        ": " ++
        if body.required {
          Printer.modelType(~qualifiedNamedRefs=true, body.schema)
        } else {
          Printer.optionalModelType(~qualifiedNamedRefs=true, body.schema)
        } ++ ",",
      ),
    ]
  }

  let fields = Belt.Array.concat(
    Array.map(operation.parameters, parameter =>
      renderParameterField(~quoteLabels, parameter)
    ),
    bodyField,
  )

  Belt.Array.concatMany([["type " ++ paramsTypeName(operation) ++ " = {"], fields, ["}"]])
}

let renderParameter = (parameter: Ir.parameter): array<string> => [
  "    {",
  "      name: " ++ Printer.quote(parameter.name) ++ ",",
  "      location: " ++ Printer.quote(parameter.location) ++ ",",
  "      required: " ++ Printer.boolLiteral(parameter.required) ++ ",",
  "      schema: OpenapiRescriptRuntime.Schema.toAny(" ++
  Printer.schemaExpr(~qualified=true, parameter.schema) ++ "),",
  "    },",
]

let renderRequestBody = (
  requestBody: option<Ir.requestBody>,
): array<string> =>
  switch requestBody {
  | None => ["  requestBody: None,"]
  | Some(body) => [
      "  requestBody: Some({",
      "    required: " ++ Printer.boolLiteral(body.required) ++ ",",
      "    schema: OpenapiRescriptRuntime.Schema.toAny(" ++
      Printer.schemaExpr(~qualified=true, body.schema) ++ "),",
      "  }),",
    ]
  }

let renderResponse = (response: Ir.response): array<string> => {
  let schemaLine = switch response.schema {
  | None => "None"
  | Some(schema) =>
    "Some(Obj.magic(OpenapiRescriptRuntime.Schema.toAny(" ++
    Printer.schemaExpr(~qualified=true, schema) ++ ")))"
  }

  [
    "    {",
    "      statusCode: " ++ Printer.quote(response.statusCode) ++ ",",
    "      schema: " ++ schemaLine ++ ",",
    "    },",
  ]
}

let optionStringLiteral = (value: option<string>): string =>
  switch value {
  | Some(value) => "Some(" ++ Printer.quote(value) ++ ")"
  | None => "None"
  }

let renderSecurityScheme = (scheme: Ir.securityScheme): array<string> => [
  "    {",
  "      name: " ++ Printer.quote(scheme.name) ++ ",",
  "      authKind: " ++ Printer.quote(scheme.authKind) ++ ",",
  "      credentialName: " ++ optionStringLiteral(scheme.credentialName) ++ ",",
  "      location: " ++ optionStringLiteral(scheme.location) ++ ",",
  "    },",
]

let renderOperationValue = (
  ~document: Ir.document,
  operation: Ir.operation,
): array<string> => {
  let parameterLines = ref([])
  Array.forEach(operation.parameters, parameter =>
    parameterLines.contents = Belt.Array.concat(
      parameterLines.contents,
      renderParameter(parameter),
    )
  )

  let responseLines = ref([])
  Array.forEach(operation.responses, response =>
    responseLines.contents = Belt.Array.concat(
      responseLines.contents,
      renderResponse(response),
    )
  )

  let securitySchemeLines = ref([])
  Array.forEach(document.securitySchemes, scheme =>
    securitySchemeLines.contents = Belt.Array.concat(
      securitySchemeLines.contents,
      renderSecurityScheme(scheme),
    )
  )

  Belt.Array.concatMany([
    ["let " ++ operation.name ++ "Operation: Client.jsonOperation = {"],
    ["  name: " ++ Printer.quote(operation.name) ++ ","],
    ["  method: " ++ Printer.quote(operation.method) ++ ","],
    ["  path: " ++ Printer.quote(operation.path) ++ ","],
    ["  tags: " ++ Printer.stringArray(operation.tags) ++ ","],
    if Array.length(parameterLines.contents) == 0 {
      ["  parameters: [],"]
    } else {
      Belt.Array.concatMany([["  parameters: ["], parameterLines.contents, ["  ],"]])
    },
    renderRequestBody(operation.requestBody),
    ["  responses: ["],
    responseLines.contents,
    ["  ],"],
    ["  security: " ++ Printer.stringMatrix(effectiveSecurity(~document, ~operation)) ++ ","],
    if Array.length(securitySchemeLines.contents) == 0 {
      ["  securitySchemes: [],"]
    } else {
      Belt.Array.concatMany([["  securitySchemes: ["], securitySchemeLines.contents, ["  ],"]])
    },
    ["}"],
  ])
}

let renderOperationFunction = (operation: Ir.operation): array<string> => {
  let (resultType, resultTypeAliases) = operationResultType(operation)

  Belt.Array.concatMany([
    resultTypeAliases,
    if Array.length(resultTypeAliases) > 0 {
      [""]
    } else {
      []
    },
    [
  "let " ++ operation.name ++ " = (",
  "  client: Client.t,",
  "  params: " ++ paramsTypeName(operation) ++ ",",
  "): promise<result<" ++ resultType ++ ", Client.operationError>> =>",
  "  Client.callJson(client, " ++ operation.name ++ "Operation, params)",
    ],
  ])
}

let renderOperation = (
  ~document: Ir.document,
  operation: Ir.operation,
): array<string> =>
  Belt.Array.concatMany([
    renderParamsType(operation),
    [""],
    renderOperationValue(~document, operation),
    [""],
    renderOperationFunction(operation),
  ])

let collectTags = (document: Ir.document): array<string> => {
  let tags = ref([])

  Array.forEach(document.tags, tag => {
    if !Array.some(tags.contents, existing => existing == tag) {
      tags.contents = Belt.Array.concat(tags.contents, [tag])
    }
  })

  Array.forEach(document.operations, operation => {
    Array.forEach(operationTags(operation), tag => {
      if !Array.some(tags.contents, existing => existing == tag) {
        tags.contents = Belt.Array.concat(tags.contents, [tag])
      }
    })
  })

  tags.contents
}

let operationHasTag = (~tag: string, ~operation: Ir.operation): bool =>
  Array.some(operationTags(operation), operationTag => operationTag == tag)

let rec uniqueModuleName = (~base: string, ~seen: array<string>, ~suffix: int=1): string => {
  let candidate = if suffix == 1 {
    base
  } else {
    base ++ Int.toString(suffix)
  }

  if Array.some(seen, existing => existing == candidate) {
    uniqueModuleName(~base, ~seen, ~suffix=suffix + 1)
  } else {
    candidate
  }
}

let collectTagModules = (document: Ir.document): array<tagModule> => {
  let seenModuleNames = ref([])
  let tagModules = ref([])

  Array.forEach(collectTags(document), tag => {
    let moduleName = uniqueModuleName(~base=Printer.moduleName(tag), ~seen=seenModuleNames.contents)
    seenModuleNames.contents = Belt.Array.concat(seenModuleNames.contents, [moduleName])
    tagModules.contents = Belt.Array.concat(tagModules.contents, [{tag, moduleName}])
  })

  tagModules.contents
}

let emitForTag = (
  ~document: Ir.document,
  ~tagModule: tagModule,
  ~operations: array<Ir.operation>,
): Printer.file => {
  let body = ref([])

  Array.forEachWithIndex(operations, (operation, index) => {
    if index > 0 {
      body.contents = Belt.Array.concat(body.contents, [""])
    }

    body.contents = Belt.Array.concat(
      body.contents,
      renderOperation(~document, operation),
    )
  })

  Printer.makeFile(
    ~path=tagModule.moduleName ++ ".res",
    ~lines=Belt.Array.concat(["// Generated by openapi-rescript-core.", ""], body.contents),
  )
}

let emitAll = (document: Ir.document): array<Printer.file> => {
  let tagModules = collectTagModules(document)
  let files = ref([])

  Array.forEach(tagModules, tagModule => {
    let operations = Belt.Array.keep(document.operations, operation =>
      operationHasTag(~tag=tagModule.tag, ~operation)
    )
    files.contents = Belt.Array.concat(
      files.contents,
      [emitForTag(~document, ~tagModule, ~operations)],
    )
  })

  files.contents
}

let moduleNames = (document: Ir.document): array<string> =>
  Array.map(collectTagModules(document), tagModule => tagModule.moduleName)
