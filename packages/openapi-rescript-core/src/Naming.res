type result<'a> = result<'a, Diagnostics.diagnostic>

type enumScope =
  | Component(string)
  | Parameter(string, string)
  | Request(string)
  | Response(string)

@send external split: (string, string) => array<string> = "split"
@send external charAt: (string, int) => string = "charAt"
@send external sliceFrom: (string, int) => string = "slice"
@send external sliceRange: (string, int, int) => string = "slice"
@send external toLowerCase: string => string = "toLowerCase"
@send external toUpperCase: string => string = "toUpperCase"

let isAsciiLetter = (char: string): bool =>
  (char >= "a" && char <= "z") || (char >= "A" && char <= "Z")

let isDigit = (char: string): bool => char >= "0" && char <= "9"

let isLowercaseLetter = (char: string): bool => char >= "a" && char <= "z"

let isIdentifierChar = (char: string): bool => isAsciiLetter(char) || isDigit(char)

let flushToken = (~tokens: ref<array<string>>, ~current: ref<string>) =>
  if current.contents != "" {
    tokens.contents = Belt.Array.concat(tokens.contents, [current.contents])
    current.contents = ""
  }

let tokenize = (input: string): array<string> => {
  let tokens = ref([])
  let current = ref("")

  Array.forEach(split(input, ""), char =>
    if isIdentifierChar(char) {
      current.contents = current.contents ++ char
    } else {
      flushToken(~tokens, ~current)
    }
  )

  flushToken(~tokens, ~current)
  tokens.contents
}

let lowercaseHead = (token: string): string =>
  if token == "" {
    ""
  } else {
    toLowerCase(charAt(token, 0)) ++ sliceFrom(token, 1)
  }

let uppercaseHead = (token: string): string =>
  if token == "" {
    ""
  } else {
    toUpperCase(charAt(token, 0)) ++ sliceFrom(token, 1)
  }

let hasLowercaseLetter = (token: string): bool => Array.some(split(token, ""), isLowercaseLetter)

let normalizeToken = (token: string): string =>
  if hasLowercaseLetter(token) {
    token
  } else {
    toLowerCase(token)
  }

let reservedIdentifiers = [
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

let makeCodegenSafeIdentifier = (identifier: string): string =>
  if Array.some(reservedIdentifiers, reserved => reserved == identifier) {
    identifier ++ "_"
  } else {
    identifier
  }

let makeIdentifier = (tokens: array<string>): string => {
  let filtered = Belt.Array.keep(tokens, token => token != "")
  let normalizedTokens = Array.map(filtered, normalizeToken)

  let identifier = switch normalizedTokens[0] {
  | None => "operation"
  | Some(first) =>
    let value = ref(lowercaseHead(first))

    Array.forEachWithIndex(normalizedTokens, (token, index) => {
      if index > 0 {
        value.contents = value.contents ++ uppercaseHead(token)
      }
    })

    value.contents
  }

  if identifier == "" {
    "operation"
  } else if isDigit(charAt(identifier, 0)) {
    "op" ++ uppercaseHead(identifier)
  } else {
    makeCodegenSafeIdentifier(identifier)
  }
}

let makeUpperIdentifier = (tokens: array<string>): string => uppercaseHead(makeIdentifier(tokens))

let sanitizeOperationId = (operationId: string): string => makeIdentifier(tokenize(operationId))

let emittedTypeName = (name: string): string => sanitizeOperationId(name)

let derivePathTokens = (path: string): array<string> => {
  let tokens = ref([])

  Array.forEach(split(path, "/"), segment =>
    if segment == "" {
      ()
    } else if (
      String.startsWith(segment, "{") && String.endsWith(segment, "}") && String.length(segment) > 2
    ) {
      let parameterName = sliceRange(segment, 1, String.length(segment) - 1)
      tokens.contents = Belt.Array.concat(tokens.contents, ["by"])
      tokens.contents = Belt.Array.concat(tokens.contents, tokenize(parameterName))
    } else {
      tokens.contents = Belt.Array.concat(tokens.contents, tokenize(segment))
    }
  )

  tokens.contents
}

let deriveOperationName = (~method_: string, ~path: string): string => {
  let pathTokens = derivePathTokens(path)
  let suffix = if Array.length(pathTokens) == 0 {
    ["root"]
  } else {
    pathTokens
  }
  makeIdentifier(Belt.Array.concat([toLowerCase(method_)], suffix))
}

let countNormalizedOperationIdUsages = (
  operations: array<Ir.operation>,
  operationId: string,
): int => {
  let normalizedOperationId = sanitizeOperationId(operationId)

  Belt.Array.reduce(operations, 0, (count, operation) =>
    switch operation.operationId {
    | Some(value) if sanitizeOperationId(value) == normalizedOperationId => count + 1
    | _ => count
    }
  )
}

let preferredOperationName = (operations: array<Ir.operation>, operation: Ir.operation): string =>
  switch operation.operationId {
  | Some(operationId) if countNormalizedOperationIdUsages(operations, operationId) == 1 =>
    sanitizeOperationId(operationId)
  | _ => deriveOperationName(~method_=operation.method, ~path=operation.path)
  }

let normalizeOperations = (operations: array<Ir.operation>): result<array<Ir.operation>> => {
  let normalized = ref([])
  let error = ref(None)

  Array.forEach(operations, operation =>
    switch error.contents {
    | Some(_) => ()
    | None =>
      let name = preferredOperationName(operations, operation)

      switch Array.find(normalized.contents, (existing: Ir.operation) => existing.name == name) {
      | Some(_) =>
        error.contents = Some(
          Diagnostics.make(
            ~path=["paths", operation.path, operation.method],
            ~message="Operation name collision after normalization: " ++ name,
          ),
        )
      | None => normalized.contents = Belt.Array.concat(normalized.contents, [{...operation, name}])
      }
    }
  )

  switch error.contents {
  | Some(problem) => Error(problem)
  | None => Ok(normalized.contents)
  }
}

let enumTypeName = (~scope: enumScope, ~segments: array<string>): string =>
  switch scope {
  | Component(schemaName) =>
    if Array.length(segments) == 0 {
      schemaName
    } else {
      makeIdentifier(
        Belt.Array.concat(
          tokenize(schemaName),
          Belt.Array.concatMany(Array.map(segments, tokenize)),
        ),
      )
    }
  | Parameter(operationName, parameterName) =>
    makeIdentifier(
      Belt.Array.concatMany([
        tokenize(operationName),
        ["param"],
        tokenize(parameterName),
        Belt.Array.concatMany(Array.map(segments, tokenize)),
      ]),
    )
  | Request(operationName) =>
    makeIdentifier(
      Belt.Array.concatMany([
        tokenize(operationName),
        ["request"],
        Belt.Array.concatMany(Array.map(segments, tokenize)),
      ]),
    )
  | Response(operationName) =>
    makeIdentifier(
      Belt.Array.concatMany([
        tokenize(operationName),
        ["response"],
        Belt.Array.concatMany(Array.map(segments, tokenize)),
      ]),
    )
  }

let enumConstructorName = (wireValue: string): string => makeUpperIdentifier(tokenize(wireValue))

let ensureUniqueEnumTypeName = (
  ~path: array<string>,
  ~existingNames: array<string>,
  typeName: string,
): result<unit> => {
  let normalizedTypeName = emittedTypeName(typeName)

  if Array.some(existingNames, existing => emittedTypeName(existing) == normalizedTypeName) {
    Error(
      Diagnostics.make(
        ~path,
        ~message="Enum type name collision after normalization: " ++ normalizedTypeName,
      ),
    )
  } else {
    Ok()
  }
}

let validateEnumConstructors = (~path: array<string>, values: array<string>): result<unit> => {
  let seen = ref([])
  let error = ref(None)

  Array.forEachWithIndex(values, (value, index) =>
    switch error.contents {
    | Some(_) => ()
    | None =>
      let constructorName = enumConstructorName(value)
      if Array.some(seen.contents, existing => existing == constructorName) {
        error.contents = Some(
          Diagnostics.make(
            ~path=Belt.Array.concat(path, [Int.toString(index)]),
            ~message="Enum constructor collision after normalization: " ++ constructorName,
          ),
        )
      } else {
        seen.contents = Belt.Array.concat(seen.contents, [constructorName])
      }
    }
  )

  switch error.contents {
  | Some(problem) => Error(problem)
  | None => Ok()
  }
}
