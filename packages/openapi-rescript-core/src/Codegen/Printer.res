type file = {
  path: string,
  contents: string,
}

@send external split: (string, string) => array<string> = "split"
@send external charAt: (string, int) => string = "charAt"
@send external sliceFrom: (string, int) => string = "slice"
@send external toUpperCase: string => string = "toUpperCase"
@val external jsonStringify: string => string = "JSON.stringify"

let isLowercaseAscii = (char: string): bool => char >= "a" && char <= "z"

let isUppercaseAscii = (char: string): bool => char >= "A" && char <= "Z"

let isDigit = (char: string): bool => char >= "0" && char <= "9"

let isRecordLabelChar = (char: string): bool =>
  char == "_" || isLowercaseAscii(char) || isUppercaseAscii(char) || isDigit(char)

let rec repeat = (count: int, value: string): string =>
  if count <= 0 {
    ""
  } else {
    value ++ repeat(count - 1, value)
  }

let indentLine = (~level: int, line: string): string =>
  if line == "" {
    ""
  } else {
    repeat(level, "  ") ++ line
  }

let joinLines = (lines: array<string>): string => Belt.Array.joinWith(lines, "\n", line => line)

let finish = (lines: array<string>): string => joinLines(lines) ++ "\n"

let makeFile = (~path: string, ~lines: array<string>): file => {
  path,
  contents: finish(lines),
}

let boolLiteral = (value: bool): string =>
  if value {
    "true"
  } else {
    "false"
  }

let quote = (value: string): string => jsonStringify(value)

let typeName = (value: string): string => Naming.emittedTypeName(value)

let enumTypeRef = (~qualifiedModels: bool=false, name: string): string =>
  (if qualifiedModels { "Models." } else { "" }) ++ typeName(name)

let enumConstructor = (~qualifiedModels: bool=false, wireValue: string): string =>
  (if qualifiedModels { "Models." } else { "" }) ++ Naming.enumConstructorName(wireValue)

let enumUnknown = (~qualifiedModels: bool=false, valueExpr: string): string =>
  (if qualifiedModels { "Models.Unknown" } else { "Unknown" }) ++ "(" ++ valueExpr ++ ")"

let enumUnknownVariantLine = (~level: int=0): string => indentLine(~level, "| Unknown(string)")

let enumSchemaExpr = (~qualifiedSchemas: bool=false, name: string): string =>
  (if qualifiedSchemas { "Schemas." } else { "" }) ++ typeName(name)

let enumDecodeErrorExpr = (valueExpr: string, values: array<string>): string =>
  "Error(" ++
  quote("Unexpected enum value: ") ++
  " ++ " ++
  valueExpr ++
  " ++ " ++
  quote(". Expected one of: " ++ Belt.Array.joinWith(values, ", ", value => value)) ++
  ")"

let reservedRecordLabels = [
  "and",
  "arguments",
  "as",
  "assert",
  "async",
  "await",
  "break",
  "case",
  "catch",
  "class",
  "constraint",
  "continue",
  "debugger",
  "default",
  "delete",
  "do",
  "downto",
  "else",
  "enum",
  "eval",
  "exception",
  "export",
  "extends",
  "external",
  "false",
  "finally",
  "for",
  "function",
  "if",
  "implements",
  "import",
  "in",
  "include",
  "instanceof",
  "interface",
  "let",
  "module",
  "mutable",
  "new",
  "nonrec",
  "null",
  "of",
  "open",
  "or",
  "package",
  "private",
  "protected",
  "public",
  "rec",
  "return",
  "static",
  "super",
  "switch",
  "this",
  "throw",
  "to",
  "true",
  "try",
  "type",
  "typeof",
  "var",
  "void",
  "when",
  "while",
  "with",
  "yield",
]

let isReservedRecordLabel = (value: string): bool =>
  Array.some(reservedRecordLabels, reserved => reserved == value)

let isSafeRecordLabel = (value: string): bool =>
  if value == "" {
    false
  } else {
    let head = charAt(value, 0)
    (isLowercaseAscii(head) || head == "_") &&
    !isReservedRecordLabel(value) &&
    Array.every(split(value, ""), isRecordLabelChar)
  }

let shouldQuoteRecordLabels = (labels: array<string>): bool =>
  Array.some(labels, label => !isSafeRecordLabel(label))

let recordLabel = (~quoteAll: bool, value: string): string =>
  if quoteAll {
    quote(value)
  } else {
    value
  }

let uppercaseHead = (token: string): string =>
  if token == "" {
    ""
  } else {
    toUpperCase(charAt(token, 0)) ++ sliceFrom(token, 1)
  }

let moduleName = (value: string): string =>
  switch typeName(value) {
  | "" => "Default"
  | identifier => uppercaseHead(identifier)
  }

let refName = (reference: string): string => {
  let segments = split(reference, "/")
  let length = Array.length(segments)

  if length == 0 {
    reference
  } else {
    Belt.Array.getOrThrow(segments, length - 1)
  }
}

let rec modelType = (~qualifiedNamedRefs: bool=false, schema: Ir.schema): string =>
  switch schema {
  | Ir.Scalar("string") => "string"
  | Ir.Scalar("integer") => "int"
  | Ir.Scalar("number") => "float"
  | Ir.Scalar("boolean") => "bool"
  | Ir.Scalar(_) => "Js.Json.t"
  | Ir.StringEnum(_) => "string"
  | Ir.Array(item) => "array<" ++ modelType(~qualifiedNamedRefs, item) ++ ">"
  | Ir.Nullable(inner) => "option<" ++ modelType(~qualifiedNamedRefs, inner) ++ ">"
  | Ir.DiscriminatedUnion(_) => "Js.Json.t"
  | Ir.NamedRef(reference) =>
    enumTypeRef(~qualifiedModels=qualifiedNamedRefs, refName(reference))
  | Ir.Object(fields) =>
    let quoteLabels = shouldQuoteRecordLabels(Array.map(fields, field => field.name))
    let renderedFields = Array.map(fields, field =>
      recordLabel(~quoteAll=quoteLabels, field.name) ++
      ": " ++ if field.required {
        modelType(~qualifiedNamedRefs, field.schema)
      } else {
        "option<" ++ modelType(~qualifiedNamedRefs, field.schema) ++ ">"
      }
    )

    "{ " ++ Belt.Array.joinWith(renderedFields, ", ", field => field) ++ " }"
  }

let rec schemaExpr = (~qualified: bool=false, schema: Ir.schema): string =>
  switch schema {
  | Ir.Scalar("string") =>
    if qualified {
      "Schemas.string"
    } else {
      "string"
    }
  | Ir.Scalar("integer") =>
    if qualified {
      "Schemas.integer"
    } else {
      "integer"
    }
  | Ir.Scalar("number") =>
    if qualified {
      "Schemas.number"
    } else {
      "number"
    }
  | Ir.Scalar("boolean") =>
    if qualified {
      "Schemas.boolean"
    } else {
      "boolean"
    }
  | Ir.StringEnum(_) =>
    if qualified {
      "Schemas.string"
    } else {
      "string"
    }
  | Ir.Scalar(_) =>
    if qualified {
      "Schemas.string"
    } else {
      "string"
    }
  | Ir.Array(item) =>
    if qualified {
      "Schemas.array"
    } else {
      "array"
    } ++
    "(" ++
    schemaExpr(~qualified, item) ++ ")"
  | Ir.Nullable(inner) =>
    if qualified {
      "Schemas.nullableAsOption"
    } else {
      "nullableAsOption"
    } ++
    "(" ++
    schemaExpr(~qualified, inner) ++ ")"
  | Ir.DiscriminatedUnion({discriminator, cases}) =>
    let renderedCases = Array.map(cases, case_ => {
      let wrapExpr = switch case_.schema {
      | Ir.Object(fields) if Array.length(fields) == 0 =>
        "_payload => " ++ enumConstructor(~qualifiedModels=true, case_.tag)
      | _ =>
        "payload => " ++ enumConstructor(~qualifiedModels=true, case_.tag) ++ "(Obj.magic(payload))"
      }
      let unwrapExpr = switch case_.schema {
      | Ir.Object(fields) if Array.length(fields) == 0 =>
        "value => switch value { | " ++
        enumConstructor(~qualifiedModels=true, case_.tag) ++
        " => Some(Obj.magic({})) | _ => None }"
      | _ =>
        "value => switch value { | " ++
        enumConstructor(~qualifiedModels=true, case_.tag) ++
        "(payload) => Some(Obj.magic(payload)) | _ => None }"
      }

      "{tag: " ++
      quote(case_.tag) ++
      ", schema: " ++
      schemaExpr(~qualified, case_.schema) ++
      ", wrap: " ++
      wrapExpr ++
      ", unwrap: " ++
      unwrapExpr ++
      "}"
    })

    (if qualified {
      "Schemas.discriminatedUnion"
    } else {
      "discriminatedUnion"
    }) ++
    "(~discriminator=" ++
    quote(discriminator) ++
    ", [" ++
    Belt.Array.joinWith(renderedCases, ", ", value => value) ++
    "])"
  | Ir.NamedRef(reference) =>
    enumSchemaExpr(~qualifiedSchemas=qualified, refName(reference))
  | Ir.Object(fields) =>
    let renderedFields = Array.map(fields, field =>
      if qualified {
        "Schemas.field"
      } else {
        "field"
      } ++
      "(~name=" ++
      quote(field.name) ++
      ", ~required=" ++
      boolLiteral(field.required) ++
      ", " ++
      schemaExpr(~qualified, field.schema) ++ ")"
    )

    if qualified {
      "Schemas.object_("
    } else {
      "object_("
    } ++
    "[" ++
    Belt.Array.joinWith(renderedFields, ", ", field => field) ++ "])"
  }

let stringArray = (values: array<string>): string =>
  "[" ++ Belt.Array.joinWith(Array.map(values, quote), ", ", value => value) ++ "]"

let stringMatrix = (values: array<array<string>>): string =>
  "[" ++ Belt.Array.joinWith(Array.map(values, stringArray), ", ", value => value) ++ "]"
