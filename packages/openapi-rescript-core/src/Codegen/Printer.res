type file = {
  path: string,
  contents: string,
}

@send external split: (string, string) => array<string> = "split"
@send external charAt: (string, int) => string = "charAt"
@send external sliceFrom: (string, int) => string = "slice"
@send external toUpperCase: string => string = "toUpperCase"
@val external jsonStringify: string => string = "JSON.stringify"

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

let typeName = (value: string): string => Naming.sanitizeOperationId(value)

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
  let length = Belt.Array.length(segments)

  if length == 0 {
    reference
  } else {
    Belt.Array.getExn(segments, length - 1)
  }
}

let rec modelType = (~qualifiedNamedRefs: bool=false, schema: Ir.schema): string =>
  switch schema {
  | Ir.Scalar("string") => "string"
  | Ir.Scalar("integer") => "int"
  | Ir.Scalar("number") => "float"
  | Ir.Scalar("boolean") => "bool"
  | Ir.Scalar(_) => "Js.Json.t"
  | Ir.Array(item) => "array<" ++ modelType(~qualifiedNamedRefs, item) ++ ">"
  | Ir.NamedRef(reference) =>
    (if qualifiedNamedRefs {"Models."} else {""}) ++ typeName(refName(reference))
  | Ir.Object(fields) =>
    let renderedFields = Belt.Array.map(fields, field =>
      field.name
      ++ ": "
      ++ (
        if field.required {
          modelType(~qualifiedNamedRefs, field.schema)
        } else {
          "option<" ++ modelType(~qualifiedNamedRefs, field.schema) ++ ">"
        }
      )
    )

    "{ " ++ Belt.Array.joinWith(renderedFields, ", ", field => field) ++ " }"
  }

let rec schemaExpr = (~qualified: bool=false, schema: Ir.schema): string =>
  switch schema {
  | Ir.Scalar("string") => (if qualified {"Schemas.string"} else {"string"})
  | Ir.Scalar("integer") => (if qualified {"Schemas.integer"} else {"integer"})
  | Ir.Scalar("number") => (if qualified {"Schemas.number"} else {"number"})
  | Ir.Scalar("boolean") => (if qualified {"Schemas.boolean"} else {"boolean"})
  | Ir.Scalar(_) => (if qualified {"Schemas.string"} else {"string"})
  | Ir.Array(item) =>
    (if qualified {"Schemas.array"} else {"array"}) ++ "(" ++ schemaExpr(~qualified, item) ++ ")"
  | Ir.NamedRef(reference) =>
    (if qualified {"Schemas."} else {""}) ++ typeName(refName(reference))
  | Ir.Object(fields) =>
    let renderedFields = Belt.Array.map(fields, field =>
      (if qualified {"Schemas.field"} else {"field"})
      ++ "(~name="
      ++ quote(field.name)
      ++ ", ~required="
      ++ boolLiteral(field.required)
      ++ ", "
      ++ schemaExpr(~qualified, field.schema)
      ++ ")"
    )

    (if qualified {"Schemas.object_("} else {"object_("})
    ++ "["
    ++ Belt.Array.joinWith(renderedFields, ", ", field => field)
    ++ "])"
  }

let stringArray = (values: array<string>): string =>
  "[" ++ Belt.Array.joinWith(Belt.Array.map(values, quote), ", ", value => value) ++ "]"

let stringMatrix = (values: array<array<string>>): string =>
  "[" ++ Belt.Array.joinWith(Belt.Array.map(values, stringArray), ", ", value => value) ++ "]"
