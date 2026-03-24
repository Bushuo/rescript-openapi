type result<'a> = result<'a, Diagnostics.diagnostic>

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

  Belt.Array.forEach(split(input, ""), char =>
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

let hasLowercaseLetter = (token: string): bool =>
  Belt.Array.some(split(token, ""), isLowercaseLetter)

let normalizeToken = (token: string): string =>
  if hasLowercaseLetter(token) {
    token
  } else {
    toLowerCase(token)
  }

let reservedIdentifiers = [
  "and",
  "as",
  "assert",
  "constraint",
  "downto",
  "else",
  "exception",
  "external",
  "false",
  "for",
  "if",
  "in",
  "include",
  "let",
  "module",
  "mutable",
  "nonrec",
  "of",
  "open",
  "or",
  "private",
  "rec",
  "switch",
  "to",
  "true",
  "try",
  "type",
  "when",
  "while",
  "with",
]

let makeCodegenSafeIdentifier = (identifier: string): string =>
  if Belt.Array.some(reservedIdentifiers, reserved => reserved == identifier) {
    identifier ++ "_"
  } else {
    identifier
  }

let makeIdentifier = (tokens: array<string>): string => {
  let filtered = Belt.Array.keep(tokens, token => token != "")
  let normalizedTokens = Belt.Array.map(filtered, normalizeToken)

  let identifier =
    switch Belt.Array.get(normalizedTokens, 0) {
    | None => "operation"
    | Some(first) =>
      let value = ref(lowercaseHead(first))

      Belt.Array.forEachWithIndex(normalizedTokens, (index, token) => {
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

let sanitizeOperationId = (operationId: string): string => makeIdentifier(tokenize(operationId))

let derivePathTokens = (path: string): array<string> => {
  let tokens = ref([])

  Belt.Array.forEach(split(path, "/"), segment =>
    if segment == "" {
      ()
    } else if String.startsWith(segment, "{") && String.endsWith(segment, "}") && String.length(segment) > 2 {
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
  let suffix = if Belt.Array.length(pathTokens) == 0 {["root"]} else {pathTokens}
  makeIdentifier(Belt.Array.concat([toLowerCase(method_)], suffix))
}

let countNormalizedOperationIdUsages = (operations: array<Ir.operation>, operationId: string): int => {
  let normalizedOperationId = sanitizeOperationId(operationId)

  Belt.Array.reduce(operations, 0, (count, operation) =>
    switch operation.operationId {
    | Some(value) if sanitizeOperationId(value) == normalizedOperationId => count + 1
    | _ => count
    },
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

  Belt.Array.forEach(operations, operation =>
    switch error.contents {
    | Some(_) => ()
    | None =>
      let name = preferredOperationName(operations, operation)

      switch Belt.Array.getBy(normalized.contents, (existing: Ir.operation) => existing.name == name) {
      | Some(_) =>
        error.contents = Some(
          Diagnostics.make(
            ~path=["paths", operation.path, operation.method],
            ~message="Operation name collision after normalization: " ++ name,
          ),
        )
      | None =>
        normalized.contents = Belt.Array.concat(normalized.contents, [{...operation, name}])
      }
    }
  )

  switch error.contents {
  | Some(problem) => Error(problem)
  | None => Ok(normalized.contents)
  }
}
