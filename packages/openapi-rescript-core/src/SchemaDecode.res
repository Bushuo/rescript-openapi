type result<'a> = result<'a, Diagnostics.diagnostic>

let at = (path: array<string>, segment: string) => Belt.Array.concat(path, [segment])

let collectArray = (items: array<'a>, fn: ('a, int) => result<'b>): result<array<'b>> => {
  let values = ref([])
  let error = ref(None)

  Array.forEachWithIndex(items, (item, index) =>
    switch error.contents {
    | Some(_) => ()
    | None =>
      switch fn(item, index) {
      | Ok(value) => values.contents = Belt.Array.concat(values.contents, [value])
      | Error(problem) => error.contents = Some(problem)
      }
    }
  )

  switch error.contents {
  | Some(problem) => Error(problem)
  | None => Ok(values.contents)
  }
}

let unsupported = (~path: array<string>, ~feature: string): result<'a> => Error(
  Diagnostics.make(~path, ~message="Unsupported schema construct: " ++ feature),
)

let hasField = (schemaObject: dict<JSON.t>, name: string): bool =>
  switch Dict.get(schemaObject, name) {
  | Some(_) => true
  | None => false
  }

let contains = (values: array<string>, target: string): bool =>
  Array.some(values, value => value == target)

let unsupportedField = (~path: array<string>, schemaObject: dict<JSON.t>, name: string): option<
  result<Ir.schema>,
> =>
  if hasField(schemaObject, name) {
    Some(unsupported(~path=at(path, name), ~feature=name))
  } else {
    None
  }

let rec firstUnsupportedField = (
  ~path: array<string>,
  schemaObject: dict<JSON.t>,
  fields: array<string>,
  ~index: int=0,
): option<result<Ir.schema>> =>
  if index >= Array.length(fields) {
    None
  } else {
    switch unsupportedField(~path, schemaObject, Belt.Array.getOrThrow(fields, index)) {
    | Some(problem) => Some(problem)
    | None => firstUnsupportedField(~path, schemaObject, fields, ~index=index + 1)
    }
  }

let decodeStringArray = (~path: array<string>, json: JSON.t): result<array<string>> =>
  switch JSON.Decode.array(json) {
  | None => Error(Diagnostics.make(~path, ~message="Expected array"))
  | Some(items) =>
    collectArray(items, (item, index) =>
      switch JSON.Decode.string(item) {
      | Some(value) => Ok(value)
      | None =>
        Error(Diagnostics.make(~path=at(path, Int.toString(index)), ~message="Expected string"))
      }
    )
  }

let decodeEnumValues = (~path: array<string>, schemaObject: dict<JSON.t>): result<array<string>> =>
  switch JsonDecode.requiredField(~path, schemaObject, "enum") {
  | Error(problem) => Error(problem)
  | Ok(enumJson) => decodeStringArray(~path=at(path, "enum"), enumJson)
  }

let decodeRequiredNames = (~path: array<string>, schemaObject: dict<JSON.t>): result<
  array<string>,
> =>
  switch Dict.get(schemaObject, "required") {
  | None => Ok([])
  | Some(value) => decodeStringArray(~path=at(path, "required"), value)
  }

let ensureClosedObject = (~path: array<string>, schemaObject: dict<JSON.t>): result<unit> =>
  switch Dict.get(schemaObject, "additionalProperties") {
  | None => Ok()
  | Some(value) =>
    switch JSON.Decode.bool(value) {
    | Some(false) => Ok()
    | Some(true) => unsupported(~path, ~feature="additionalProperties")
    | None => unsupported(~path, ~feature="additionalProperties")
    }
  }

let decodeRef = (~path: array<string>, schemaObject: dict<JSON.t>): result<Ir.schema> =>
  switch Dict.get(schemaObject, "$ref") {
  | Some(value) =>
    switch JSON.Decode.string(value) {
    | Some(reference) => Ok(Ir.NamedRef(reference))
    | None => Error(Diagnostics.make(~path=at(path, "$ref"), ~message="Expected string"))
    }
  | None => Error(Diagnostics.make(~path=at(path, "$ref"), ~message="Missing required field"))
  }

let rec decode = (~path: array<string>, json: JSON.t): result<Ir.schema> =>
  switch JSON.Decode.object(json) {
  | None => Error(Diagnostics.make(~path, ~message="Expected object"))
  | Some(schemaObject) => decodeObject(~path, schemaObject)
  }

and decodeObject = (~path: array<string>, schemaObject: dict<JSON.t>): result<Ir.schema> =>
  switch firstUnsupportedField(
    ~path,
    schemaObject,
    [
      "oneOf",
      "anyOf",
      "allOf",
      "const",
      "not",
      "if",
      "then",
      "else",
      "prefixItems",
      "contains",
      "patternProperties",
      "propertyNames",
      "dependentSchemas",
      "discriminator",
      "nullable",
    ],
  ) {
  | Some(problem) => problem
  | None =>
    if hasField(schemaObject, "$ref") && hasField(schemaObject, "enum") {
      unsupported(~path=at(path, "enum"), ~feature="enum with $ref")
    } else {
      switch Dict.get(schemaObject, "$ref") {
    | Some(_) => decodeRef(~path, schemaObject)
    | None =>
      if hasField(schemaObject, "enum") {
        decodeEnumSchema(~path, schemaObject)
      } else {
        switch Dict.get(schemaObject, "type")->Belt.Option.flatMap(JSON.Decode.string) {
        | Some("array") => decodeArraySchema(~path, schemaObject)
        | Some("object") => decodeObjectSchema(~path, schemaObject)
        | Some("string") => Ok(Ir.Scalar("string"))
        | Some("integer") => Ok(Ir.Scalar("integer"))
        | Some("number") => Ok(Ir.Scalar("number"))
        | Some("boolean") => Ok(Ir.Scalar("boolean"))
        | Some(kind) => unsupported(~path, ~feature="type:" ++ kind)
        | None =>
          if hasField(schemaObject, "properties") {
            decodeObjectSchema(~path, schemaObject)
          } else {
            Error(Diagnostics.make(~path, ~message="Unsupported schema"))
          }
        }
      }
    }
    }
  }

and decodeEnumSchema = (~path: array<string>, schemaObject: dict<JSON.t>): result<Ir.schema> =>
  switch Dict.get(schemaObject, "type")->Belt.Option.flatMap(JSON.Decode.string) {
  | Some("string") =>
    switch decodeEnumValues(~path, schemaObject) {
    | Ok(values) => Ok(Ir.StringEnum({name: "", values}))
    | Error(problem) => Error(problem)
    }
  | None =>
    switch decodeEnumValues(~path, schemaObject) {
    | Ok(values) => Ok(Ir.StringEnum({name: "", values}))
    | Error(problem) => Error(problem)
    }
  | Some(_) =>
    Error(Diagnostics.make(~path=at(path, "type"), ~message="Only string enums are supported"))
  }

and decodeArraySchema = (~path: array<string>, schemaObject: dict<JSON.t>): result<Ir.schema> =>
  switch JsonDecode.requiredField(~path, schemaObject, "items") {
  | Error(problem) => Error(problem)
  | Ok(items) =>
    switch decode(~path=at(path, "items"), items) {
    | Ok(itemSchema) => Ok(Ir.Array(itemSchema))
    | Error(problem) => Error(problem)
    }
  }

and decodeObjectSchema = (~path: array<string>, schemaObject: dict<JSON.t>): result<Ir.schema> =>
  switch ensureClosedObject(~path, schemaObject) {
  | Error(problem) => Error(problem)
  | Ok() =>
    switch decodeRequiredNames(~path, schemaObject) {
    | Error(problem) => Error(problem)
    | Ok(requiredNames) =>
      switch Dict.get(schemaObject, "properties") {
      | None => Ok(Ir.Object([]))
      | Some(propertiesJson) =>
        switch JSON.Decode.object(propertiesJson) {
        | None => Error(Diagnostics.make(~path=at(path, "properties"), ~message="Expected object"))
        | Some(properties) =>
          let fields = ref([])
          let error = ref(None)

          Dict.forEachWithKey(properties, (propertyJson, name) =>
            switch error.contents {
            | Some(_) => ()
            | None =>
              switch decode(~path=at(at(path, "properties"), name), propertyJson) {
              | Ok(propertySchema) =>
                let field: Ir.objectField = {
                  name,
                  required: contains(requiredNames, name),
                  schema: propertySchema,
                }
                fields.contents = Belt.Array.concat(fields.contents, [field])
              | Error(problem) => error.contents = Some(problem)
              }
            }
          )

          switch error.contents {
          | Some(problem) => Error(problem)
          | None => Ok(Ir.Object(fields.contents))
          }
        }
      }
    }
  }
