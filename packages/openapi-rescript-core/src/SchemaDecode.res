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

type oneOfBranch = {
  index: int,
  path: array<string>,
  schemaObject: dict<JSON.t>,
}

type constructorTag = {
  path: array<string>,
  tag: string,
}

type discriminatorCandidate = {
  name: string,
  tags: array<constructorTag>,
}

type decodedCase = {
  tag: string,
  payload: Ir.schema,
}

let isNullSchemaObject = (schemaObject: dict<JSON.t>): bool =>
  switch Dict.get(schemaObject, "type")->Belt.Option.flatMap(JSON.Decode.string) {
  | Some("null") => true
  | _ => false
  }

let decodeOneOfBranches = (~path: array<string>, oneOfJson: JSON.t): result<array<oneOfBranch>> =>
  switch JSON.Decode.array(oneOfJson) {
  | None => Error(Diagnostics.make(~path, ~message="Expected array"))
  | Some(items) =>
    collectArray(items, (item, index) =>
      switch JSON.Decode.object(item) {
      | None => Error(Diagnostics.make(~path=at(path, Int.toString(index)), ~message="Expected object"))
      | Some(schemaObject) =>
        Ok({
          index,
          path: at(path, Int.toString(index)),
          schemaObject,
        })
      }
    )
  }

let intersectStrings = (left: array<string>, right: array<string>): array<string> =>
  Belt.Array.keep(left, value => contains(right, value))

let rec ensureObjectLikeBranch = (branch: oneOfBranch): result<unit> =>
  switch Dict.get(branch.schemaObject, "type")->Belt.Option.flatMap(JSON.Decode.string) {
  | Some("object") => Ok()
  | None =>
    if hasField(branch.schemaObject, "properties") {
      Ok()
    } else {
      unsupported(~path=branch.path, ~feature="oneOf")
    }
  | Some(kind) => unsupported(~path=at(branch.path, "type"), ~feature="type:" ++ kind)
  }

and decodeDiscriminatorTag = (~path: array<string>, propertyJson: JSON.t): result<constructorTag> =>
  switch JSON.Decode.object(propertyJson) {
  | None => Error(Diagnostics.make(~path, ~message="Expected object"))
  | Some(propertyObject) =>
    if hasField(propertyObject, "$ref") {
      unsupported(~path=at(path, "$ref"), ~feature="$ref")
    } else {
      switch Dict.get(propertyObject, "const") {
      | Some(constJson) =>
        switch JSON.Decode.string(constJson) {
        | Some(tag) => Ok({path: at(path, "const"), tag})
        | None => Error(Diagnostics.make(~path=at(path, "const"), ~message="Expected string"))
        }
      | None =>
        if hasField(propertyObject, "enum") {
          switch JsonDecode.requiredField(~path, propertyObject, "enum") {
          | Error(problem) => Error(problem)
          | Ok(enumJson) =>
            switch decodeStringArray(~path=at(path, "enum"), enumJson) {
          | Ok(values) =>
            if Array.length(values) == 1 {
              Ok({
                path: at(at(path, "enum"), "0"),
                tag: Belt.Array.getOrThrow(values, 0),
              })
            } else if Array.length(values) == 0 {
              Error(Diagnostics.make(~path=at(path, "enum"), ~message="Enum arrays must not be empty"))
            } else {
              unsupported(~path=at(path, "enum"), ~feature="enum")
            }
            | Error(problem) => Error(problem)
            }
          }
        } else {
          unsupported(~path, ~feature="oneOf")
        }
      }
    }
  }

and findDiscriminatorCandidate = (
  ~path: array<string>,
  branches: array<oneOfBranch>,
): result<discriminatorCandidate> =>
  switch Belt.Array.get(branches, 0) {
  | None => unsupported(~path, ~feature="oneOf")
  | Some(firstBranch) =>
    switch decodeRequiredNames(~path=firstBranch.path, firstBranch.schemaObject) {
    | Error(problem) => Error(problem)
    | Ok(firstRequired) =>
      let sharedRequired = ref(firstRequired)
      let error = ref(None)

      Array.forEachWithIndex(branches, (branch, index) =>
        if index > 0 {
          switch error.contents {
          | Some(_) => ()
          | None =>
            switch decodeRequiredNames(~path=branch.path, branch.schemaObject) {
            | Ok(requiredNames) =>
              sharedRequired.contents = intersectStrings(sharedRequired.contents, requiredNames)
            | Error(problem) => error.contents = Some(problem)
            }
          }
        }
      )

      switch error.contents {
      | Some(problem) => Error(problem)
      | None =>
        if Array.length(sharedRequired.contents) == 0 {
          unsupported(~path, ~feature="oneOf")
        } else {
          let validCandidates = ref([])
          let firstError = ref(None)

          Array.forEach(sharedRequired.contents, name =>
            switch collectArray(branches, (branch, _) =>
              switch Dict.get(branch.schemaObject, "properties") {
              | None => unsupported(~path=branch.path, ~feature="oneOf")
              | Some(propertiesJson) =>
                switch JSON.Decode.object(propertiesJson) {
                | None =>
                  Error(Diagnostics.make(~path=at(branch.path, "properties"), ~message="Expected object"))
                | Some(properties) =>
                  switch Dict.get(properties, name) {
                  | Some(propertyJson) =>
                    decodeDiscriminatorTag(~path=at(at(branch.path, "properties"), name), propertyJson)
                  | None => unsupported(~path=branch.path, ~feature="oneOf")
                  }
                }
              }
            ) {
            | Ok(tags) =>
              validCandidates.contents = Belt.Array.concat(validCandidates.contents, [{name, tags}])
            | Error(problem) =>
              switch firstError.contents {
              | Some(_) => ()
              | None => firstError.contents = Some(problem)
              }
            }
          )

          let validCount = Array.length(validCandidates.contents)

          if validCount == 1 {
            Ok(Belt.Array.getOrThrow(validCandidates.contents, 0))
          } else if validCount > 1 {
            unsupported(~path, ~feature="oneOf")
          } else {
            switch firstError.contents {
            | Some(problem) => Error(problem)
            | None => unsupported(~path, ~feature="oneOf")
            }
          }
        }
      }
    }
  }

and decodeCasePayloadSchema = (
  ~path: array<string>,
  ~discriminator: string,
  schemaObject: dict<JSON.t>,
): result<Ir.schema> =>
  switch ensureClosedObject(~path, schemaObject) {
  | Error(problem) => Error(problem)
  | Ok() =>
    switch decodeRequiredNames(~path, schemaObject) {
    | Error(problem) => Error(problem)
    | Ok(requiredNames) =>
      let payloadRequired = Belt.Array.keep(requiredNames, name => name != discriminator)

      switch Dict.get(schemaObject, "properties") {
      | None => Ok(Ir.Object([]))
      | Some(propertiesJson) =>
        switch JSON.Decode.object(propertiesJson) {
        | None => Error(Diagnostics.make(~path=at(path, "properties"), ~message="Expected object"))
        | Some(properties) =>
          let fields = ref([])
          let error = ref(None)

          Dict.forEachWithKey(properties, (propertyJson, name) =>
            if name != discriminator {
              switch error.contents {
              | Some(_) => ()
              | None =>
                switch decode(~path=at(at(path, "properties"), name), propertyJson) {
                | Ok(propertySchema) =>
                  let field: Ir.objectField = {
                    name,
                    required: contains(payloadRequired, name),
                    schema: propertySchema,
                  }
                  fields.contents = Belt.Array.concat(
                    fields.contents,
                    [field],
                  )
                | Error(problem) => error.contents = Some(problem)
                }
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

and decodeDiscriminatedUnion = (~path: array<string>, oneOfJson: JSON.t): result<Ir.schema> =>
  switch decodeOneOfBranches(~path, oneOfJson) {
  | Error(problem) => Error(problem)
  | Ok(branches) =>
    let nullBranches = Belt.Array.keep(branches, branch => isNullSchemaObject(branch.schemaObject))
    let valueBranches = Belt.Array.keep(branches, branch => !isNullSchemaObject(branch.schemaObject))

    if Array.length(nullBranches) > 1 || Array.length(valueBranches) == 0 {
      unsupported(~path, ~feature="oneOf")
    } else {
      let branchError = ref(None)

      Array.forEach(valueBranches, branch =>
        switch branchError.contents {
        | Some(_) => ()
        | None =>
          switch ensureObjectLikeBranch(branch) {
          | Ok() => ()
          | Error(problem) => branchError.contents = Some(problem)
          }
        }
      )

      switch branchError.contents {
      | Some(problem) => Error(problem)
      | None =>
        switch findDiscriminatorCandidate(~path, valueBranches) {
        | Error(problem) => Error(problem)
        | Ok(candidate) =>
          let constructorEntries: array<Naming.constructorEntry> = Array.map(candidate.tags, tag => {
            let entry: Naming.constructorEntry = {
              path: tag.path,
              wireValue: tag.tag,
            }
            entry
          })

          switch Naming.validateConstructorEntries(
            constructorEntries,
          ) {
          | Error(problem) => Error(problem)
          | Ok() =>
            if Array.length(valueBranches) < 2 {
              unsupported(~path, ~feature="oneOf")
            } else {
              switch collectArray(valueBranches, (branch, index) =>
                switch decodeCasePayloadSchema(
                  ~path=branch.path,
                  ~discriminator=candidate.name,
                  branch.schemaObject,
                ) {
                | Ok(payload) =>
                  Ok({
                    tag: Belt.Array.getOrThrow(candidate.tags, index).tag,
                    payload,
                  })
                | Error(problem) => Error(problem)
                }
              ) {
              | Error(problem) => Error(problem)
              | Ok(cases) =>
                let unionCases: array<Ir.unionCase> = Array.map(cases, case_ => {
                  let unionCase: Ir.unionCase = {
                    tag: case_.tag,
                    payload: case_.payload,
                  }
                  unionCase
                })

                let unionSchema = Ir.DiscriminatedUnion({
                  discriminator: candidate.name,
                  cases: unionCases,
                })

                if Array.length(nullBranches) == 1 {
                  Ok(Ir.Nullable(unionSchema))
                } else {
                  Ok(unionSchema)
                }
              }
            }
          }
        }
      }
    }
  }

and decodeEnumValues = (~path: array<string>, schemaObject: dict<JSON.t>): result<array<string>> =>
  switch JsonDecode.requiredField(~path, schemaObject, "enum") {
  | Error(problem) => Error(problem)
  | Ok(enumJson) =>
    switch decodeStringArray(~path=at(path, "enum"), enumJson) {
    | Ok(values) =>
      if Array.length(values) == 0 {
        Error(Diagnostics.make(~path=at(path, "enum"), ~message="Enum arrays must not be empty"))
      } else {
        Ok(values)
      }
    | Error(problem) => Error(problem)
    }
  }

and decodeRequiredNames = (~path: array<string>, schemaObject: dict<JSON.t>): result<
  array<string>,
> =>
  switch Dict.get(schemaObject, "required") {
  | None => Ok([])
  | Some(value) => decodeStringArray(~path=at(path, "required"), value)
  }

and ensureClosedObject = (~path: array<string>, schemaObject: dict<JSON.t>): result<unit> =>
  switch Dict.get(schemaObject, "additionalProperties") {
  | None => Ok()
  | Some(value) =>
    switch JSON.Decode.bool(value) {
    | Some(false) => Ok()
    | Some(true) => unsupported(~path, ~feature="additionalProperties")
    | None => unsupported(~path, ~feature="additionalProperties")
    }
  }

and decodeRef = (~path: array<string>, schemaObject: dict<JSON.t>): result<Ir.schema> =>
  switch Dict.get(schemaObject, "$ref") {
  | Some(value) =>
    switch JSON.Decode.string(value) {
    | Some(reference) => Ok(Ir.NamedRef(reference))
    | None => Error(Diagnostics.make(~path=at(path, "$ref"), ~message="Expected string"))
    }
  | None => Error(Diagnostics.make(~path=at(path, "$ref"), ~message="Missing required field"))
  }

and decode = (~path: array<string>, json: JSON.t): result<Ir.schema> =>
  switch JSON.Decode.object(json) {
  | None => Error(Diagnostics.make(~path, ~message="Expected object"))
  | Some(schemaObject) => decodeObject(~path, schemaObject)
  }

and decodeObject = (~path: array<string>, schemaObject: dict<JSON.t>): result<Ir.schema> =>
  switch firstUnsupportedField(
    ~path,
    schemaObject,
    [
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
    if hasField(schemaObject, "oneOf") {
      decodeOneOf(~path, schemaObject)
    } else if hasField(schemaObject, "$ref") && hasField(schemaObject, "enum") {
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

and decodeOneOf = (~path: array<string>, schemaObject: dict<JSON.t>): result<Ir.schema> =>
  switch JsonDecode.requiredField(~path, schemaObject, "oneOf") {
  | Ok(oneOfJson) =>
    switch decodeNullableOneOf(~path=at(path, "oneOf"), oneOfJson) {
    | Ok(schema) => Ok(schema)
    | Error(_) => decodeDiscriminatedUnion(~path=at(path, "oneOf"), oneOfJson)
    }
  | Error(problem) => Error(problem)
  }

and decodeNullableOneOf = (~path: array<string>, oneOfJson: JSON.t): result<Ir.schema> =>
  switch decodeOneOfBranches(~path, oneOfJson) {
  | Error(problem) => Error(problem)
  | Ok(branches) =>
    if Array.length(branches) != 2 {
      unsupported(~path, ~feature="oneOf")
    } else {
      let first = Belt.Array.getOrThrow(branches, 0)
      let second = Belt.Array.getOrThrow(branches, 1)
      let firstIsNull = isNullSchemaObject(first.schemaObject)
      let secondIsNull = isNullSchemaObject(second.schemaObject)

      if firstIsNull == secondIsNull {
        unsupported(~path, ~feature="oneOf")
      } else {
        let nonNullBranch = if firstIsNull {second} else {first}
        switch decodeObject(~path=nonNullBranch.path, nonNullBranch.schemaObject) {
        | Ok(schema) => Ok(Ir.Nullable(schema))
        | Error(problem) => Error(problem)
        }
      }
    }
  }

and decodeEnumSchema = (~path: array<string>, schemaObject: dict<JSON.t>): result<Ir.schema> =>
  switch Dict.get(schemaObject, "type")->Belt.Option.flatMap(JSON.Decode.string) {
  | Some("string") =>
    switch decodeEnumValues(~path, schemaObject) {
    | Ok(values) => Ok(Ir.StringEnum({name: "", values, path: at(path, "enum")}))
    | Error(problem) => Error(problem)
    }
  | None =>
    switch decodeEnumValues(~path, schemaObject) {
    | Ok(values) => Ok(Ir.StringEnum({name: "", values, path: at(path, "enum")}))
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
