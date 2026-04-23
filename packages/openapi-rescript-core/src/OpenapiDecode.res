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

let optionalStringArrayField = (~path: array<string>, dict: dict<JSON.t>, name: string): result<
  array<string>,
> =>
  switch Dict.get(dict, name) {
  | None => Ok([])
  | Some(value) => decodeStringArray(~path=at(path, name), value)
  }

let optionalStringField = (~path: array<string>, dict: dict<JSON.t>, name: string): result<
  option<string>,
> =>
  switch Dict.get(dict, name) {
  | None => Ok(None)
  | Some(value) =>
    switch JSON.Decode.string(value) {
    | Some(text) => Ok(Some(text))
    | None => Error(Diagnostics.make(~path=at(path, name), ~message="Expected string"))
    }
  }

let optionalBoolField = (~path: array<string>, dict: dict<JSON.t>, name: string): result<
  option<bool>,
> =>
  switch Dict.get(dict, name) {
  | None => Ok(None)
  | Some(value) =>
    switch JSON.Decode.bool(value) {
    | Some(flag) => Ok(Some(flag))
    | None => Error(Diagnostics.make(~path=at(path, name), ~message="Expected boolean"))
    }
  }

let decodeSchemaFromContentEntry = (
  ~path: array<string>,
  contentType: string,
  contentJson: JSON.t,
): result<Ir.schema> =>
  switch JSON.Decode.object(contentJson) {
  | None => Error(Diagnostics.make(~path=at(path, contentType), ~message="Expected object"))
  | Some(contentObject) =>
    switch JsonDecode.requiredField(~path=at(path, contentType), contentObject, "schema") {
    | Ok(schemaJson) => SchemaDecode.decode(~path=at(at(path, contentType), "schema"), schemaJson)
    | Error(problem) => Error(problem)
    }
  }

let decodeJsonSchema = (~path: array<string>, contentObject: dict<JSON.t>): result<Ir.schema> =>
  switch Dict.get(contentObject, "application/json") {
  | Some(contentJson) => decodeSchemaFromContentEntry(~path, "application/json", contentJson)
  | None =>
    switch Array.find(Dict.toArray(contentObject), entry =>
      switch entry {
      | (contentType, _) => String.endsWith(contentType, "+json")
      }
    ) {
    | Some((contentType, contentJson)) =>
      decodeSchemaFromContentEntry(~path, contentType, contentJson)
    | None => Error(Diagnostics.make(~path, ~message="Only JSON media types are supported"))
    }
  }

let decodeRequestBody = (~path: array<string>, operationObject: dict<JSON.t>): result<
  option<Ir.requestBody>,
> =>
  switch Dict.get(operationObject, "requestBody") {
  | None => Ok(None)
  | Some(bodyJson) =>
    switch JSON.Decode.object(bodyJson) {
    | None => Error(Diagnostics.make(~path=at(path, "requestBody"), ~message="Expected object"))
    | Some(bodyObject) =>
      switch (
        optionalBoolField(~path=at(path, "requestBody"), bodyObject, "required"),
        JsonDecode.requiredField(~path=at(path, "requestBody"), bodyObject, "content"),
      ) {
      | (Ok(requiredValue), Ok(contentJson)) =>
        let required = switch requiredValue {
        | Some(value) => value
        | None => false
        }

        switch JSON.Decode.object(contentJson) {
        | None =>
          Error(
            Diagnostics.make(
              ~path=at(at(path, "requestBody"), "content"),
              ~message="Expected object",
            ),
          )
        | Some(contentObject) =>
          switch decodeJsonSchema(~path=at(at(path, "requestBody"), "content"), contentObject) {
          | Ok(schema) =>
            let requestBody: Ir.requestBody = {required, schema}
            Ok(Some(requestBody))
          | Error(problem) => Error(problem)
          }
        }
      | (Error(problem), _) => Error(problem)
      | (_, Error(problem)) => Error(problem)
      }
    }
  }

let decodeResponses = (~path: array<string>, operationObject: dict<JSON.t>): result<
  array<Ir.response>,
> =>
  switch JsonDecode.objectField(~path, operationObject, "responses") {
  | Error(problem) => Error(problem)
  | Ok(responsesObject) =>
    let responses = ref([])
    let error = ref(None)

    Dict.forEachWithKey(responsesObject, (responseJson, statusCode) =>
      switch error.contents {
      | Some(_) => ()
      | None =>
        let responsePath = at(at(path, "responses"), statusCode)
        switch JSON.Decode.object(responseJson) {
        | None =>
          error.contents = Some(Diagnostics.make(~path=responsePath, ~message="Expected object"))
        | Some(responseObject) =>
          let append = schema => {
            let response: Ir.response = {statusCode, schema}
            responses.contents = Belt.Array.concat(responses.contents, [response])
          }

          switch Dict.get(responseObject, "content") {
          | None => append(None)
          | Some(contentJson) =>
            switch JSON.Decode.object(contentJson) {
            | None =>
              error.contents = Some(
                Diagnostics.make(~path=at(responsePath, "content"), ~message="Expected object"),
              )
            | Some(contentObject) =>
              switch decodeJsonSchema(~path=at(responsePath, "content"), contentObject) {
              | Ok(schema) => append(Some(schema))
              | Error(problem) => error.contents = Some(problem)
              }
            }
          }
        }
      }
    )

    switch error.contents {
    | Some(problem) => Error(problem)
    | None => Ok(responses.contents)
    }
  }

let decodeParameters = (~path: array<string>, operationObject: dict<JSON.t>): result<
  array<Ir.parameter>,
> =>
  switch Dict.get(operationObject, "parameters") {
  | None => Ok([])
  | Some(parametersJson) =>
    switch JSON.Decode.array(parametersJson) {
    | None => Error(Diagnostics.make(~path=at(path, "parameters"), ~message="Expected array"))
    | Some(parametersArray) =>
      collectArray(parametersArray, (parameterJson, index) => {
        let parameterPath = at(at(path, "parameters"), Int.toString(index))
        switch JSON.Decode.object(parameterJson) {
        | None => Error(Diagnostics.make(~path=parameterPath, ~message="Expected object"))
        | Some(parameterObject) =>
          switch (
            JsonDecode.stringField(~path=parameterPath, parameterObject, "name"),
            JsonDecode.stringField(~path=parameterPath, parameterObject, "in"),
            optionalBoolField(~path=parameterPath, parameterObject, "required"),
            JsonDecode.requiredField(~path=parameterPath, parameterObject, "schema"),
          ) {
          | (Ok(name), Ok(location), Ok(requiredValue), Ok(schemaJson)) =>
            switch SchemaDecode.decode(~path=at(parameterPath, "schema"), schemaJson) {
            | Ok(schema) =>
              let required = switch requiredValue {
              | Some(value) => value
              | None => false
              }

              let parameter: Ir.parameter = {
                name,
                location,
                required,
                schema,
              }
              Ok(parameter)
            | Error(problem) => Error(problem)
            }
          | (Error(problem), _, _, _) => Error(problem)
          | (_, Error(problem), _, _) => Error(problem)
          | (_, _, Error(problem), _) => Error(problem)
          | (_, _, _, Error(problem)) => Error(problem)
          }
        }
      })
    }
  }

let sameParameter = (left: Ir.parameter, right: Ir.parameter): bool =>
  left.name == right.name && left.location == right.location

let mergeParameters = (
  inheritedParameters: array<Ir.parameter>,
  operationParameters: array<Ir.parameter>,
): array<Ir.parameter> => {
  let remainingInherited = Belt.Array.keep(inheritedParameters, inherited =>
    !Array.some(operationParameters, operation => sameParameter(inherited, operation))
  )

  Belt.Array.concat(remainingInherited, operationParameters)
}

let decodeSecurityRequirements = (~path: array<string>, source: dict<JSON.t>, name: string): result<
  option<array<Ir.securityRequirement>>,
> =>
  switch Dict.get(source, name) {
  | None => Ok(None)
  | Some(securityJson) =>
    switch JSON.Decode.array(securityJson) {
    | None => Error(Diagnostics.make(~path=at(path, name), ~message="Expected array"))
    | Some(securityArray) =>
      switch collectArray(securityArray, (entryJson, index) => {
        let entryPath = at(at(path, name), Int.toString(index))
        switch JSON.Decode.object(entryJson) {
        | None => Error(Diagnostics.make(~path=entryPath, ~message="Expected object"))
        | Some(securityObject) =>
          let entries = Dict.toArray(securityObject)
          if Array.length(entries) == 0 {
            Ok([])
          } else {
            collectArray(entries, ((securityName, requirementJson), _) =>
              switch decodeStringArray(~path=at(entryPath, securityName), requirementJson) {
              | Ok(requirements) =>
                if Array.length(requirements) == 0 {
                  Ok(securityName)
                } else {
                  Error(
                    Diagnostics.make(
                      ~path=at(entryPath, securityName),
                      ~message="Only empty security requirement arrays are supported",
                    ),
                  )
                }
              | Error(problem) => Error(problem)
              }
            )
          }
        }
      }) {
      | Ok(requirements) => Ok(Some(requirements))
      | Error(problem) => Error(problem)
      }
    }
  }

let decodeTopLevelSecurity = (~path: array<string>, root: dict<JSON.t>): result<
  array<Ir.securityRequirement>,
> =>
  switch decodeSecurityRequirements(~path, root, "security") {
  | Ok(Some(security)) => Ok(security)
  | Ok(None) => Ok([])
  | Error(problem) => Error(problem)
  }

let decodeOperation = (
  ~routePath: string,
  ~method_: string,
  ~operationPath: array<string>,
  ~inheritedParameters: array<Ir.parameter>,
  operationJson: JSON.t,
): result<Ir.operation> => {
  let operationObjectResult = switch JSON.Decode.object(operationJson) {
  | Some(operationObject) => Ok(operationObject)
  | None => Error(Diagnostics.make(~path=operationPath, ~message="Expected object"))
  }

  let? Ok(operationObject) = operationObjectResult
  let? Ok(operationId) = optionalStringField(~path=operationPath, operationObject, "operationId")
  let? Ok(tags) = optionalStringArrayField(~path=operationPath, operationObject, "tags")
  let? Ok(parameters) = decodeParameters(~path=operationPath, operationObject)
  let? Ok(requestBody) = decodeRequestBody(~path=operationPath, operationObject)
  let? Ok(responses) = decodeResponses(~path=operationPath, operationObject)
  let? Ok(security) = decodeSecurityRequirements(~path=operationPath, operationObject, "security")

  let operation: Ir.operation = {
    operationId,
    name: "",
    method: method_,
    path: routePath,
    tags,
    parameters: mergeParameters(inheritedParameters, parameters),
    requestBody,
    responses,
    security,
  }
  Ok(operation)
}

let operationMethods = ["get", "post", "put", "patch", "delete", "options", "head", "trace"]

let decodeOperations = (~path: array<string>, root: dict<JSON.t>): result<array<Ir.operation>> => {
  let? Ok(pathsObject) = JsonDecode.objectField(~path, root, "paths")
  let operations = ref([])
  let error = ref(None)

  Dict.forEachWithKey(pathsObject, (pathJson, routePath) =>
    switch error.contents {
    | Some(_) => ()
    | None =>
      switch JSON.Decode.object(pathJson) {
      | None =>
        error.contents = Some(
          Diagnostics.make(~path=["paths", routePath], ~message="Expected object"),
        )
      | Some(pathObject) =>
        switch decodeParameters(~path=["paths", routePath], pathObject) {
        | Error(problem) => error := Some(problem)
        | Ok(inheritedParameters) =>
          Array.forEach(operationMethods, method_ =>
            switch error.contents {
            | Some(_) => ()
            | None =>
              switch Dict.get(pathObject, method_) {
              | None => ()
              | Some(operationJson) =>
                switch decodeOperation(
                  ~routePath,
                  ~method_,
                  ~operationPath=["paths", routePath, method_],
                  ~inheritedParameters,
                  operationJson,
                ) {
                | Ok(operation) => operations := Belt.Array.concat(operations.contents, [operation])
                | Error(problem) => error := Some(problem)
                }
              }
            }
          )
        }
      }
    }
  )

  switch error.contents {
  | Some(problem) => Error(problem)
  | None => Ok(operations.contents)
  }
}

let decodeSchemas = (~path: array<string>, root: dict<JSON.t>): result<array<Ir.namedSchema>> =>
  switch Dict.get(root, "components") {
  | None => Ok([])
  | Some(componentsJson) =>
    switch JSON.Decode.object(componentsJson) {
    | None => Error(Diagnostics.make(~path=at(path, "components"), ~message="Expected object"))
    | Some(components) =>
      switch Dict.get(components, "schemas") {
      | None => Ok([])
      | Some(schemasJson) =>
        switch JSON.Decode.object(schemasJson) {
        | None =>
          Error(Diagnostics.make(~path=["components", "schemas"], ~message="Expected object"))
        | Some(schemas) =>
          let decodedSchemas = ref([])
          let error = ref(None)

          Dict.forEachWithKey(schemas, (schemaJson, name) =>
            switch error.contents {
            | Some(_) => ()
            | None =>
              switch SchemaDecode.decode(~path=["components", "schemas", name], schemaJson) {
              | Ok(schema) =>
                let namedSchema: Ir.namedSchema = {name, schema}
                decodedSchemas := Belt.Array.concat(decodedSchemas.contents, [namedSchema])
              | Error(problem) => error := Some(problem)
              }
            }
          )

          switch error.contents {
          | Some(problem) => Error(problem)
          | None => Ok(decodedSchemas.contents)
          }
        }
      }
    }
  }

let enumRef = (name: string): string => "#/components/schemas/" ++ name

let appendSegment = (segments: array<string>, segment: string): array<string> =>
  Belt.Array.concat(segments, [segment])

let addLiftedEnum = (
  ~path: array<string>,
  ~reservedNames: ref<array<string>>,
  ~liftedSchemas: ref<array<Ir.namedSchema>>,
  ~name: string,
  ~values: array<string>,
): result<Ir.schema> => {
  let? Ok() = Naming.ensureUniqueEnumTypeName(~path, ~existingNames=reservedNames.contents, name)
  reservedNames := Belt.Array.concat(reservedNames.contents, [name])
  liftedSchemas :=
    Belt.Array.concat(
      liftedSchemas.contents,
      [
        {
          name,
          schema: Ir.StringEnum({name, values, path: at(path, "enum")}),
        },
      ],
    )
  Ok(Ir.NamedRef(enumRef(name)))
}

let rec liftEnumSchema = (
  ~path: array<string>,
  ~scope: Naming.enumScope,
  ~segments: array<string>,
  ~reservedNames: ref<array<string>>,
  ~liftedSchemas: ref<array<Ir.namedSchema>>,
  schema: Ir.schema,
): result<Ir.schema> =>
  switch schema {
  | Ir.Scalar(_) | Ir.MappedScalar(_) => Ok(schema)
  | Ir.NamedRef(_) => Ok(schema)
  | Ir.StringEnum({name: _, values, path: enumPath}) =>
    switch Naming.validateEnumConstructors(~path=enumPath, values) {
    | Error(problem) => Error(problem)
    | Ok() =>
      let name = Naming.enumTypeName(~scope, ~segments)
      addLiftedEnum(~path, ~reservedNames, ~liftedSchemas, ~name, ~values)
    }
  | Ir.Array(item) =>
    switch liftEnumSchema(
      ~path=at(path, "items"),
      ~scope,
      ~segments=appendSegment(segments, "item"),
      ~reservedNames,
      ~liftedSchemas,
      item,
    ) {
    | Ok(itemSchema) => Ok(Ir.Array(itemSchema))
    | Error(problem) => Error(problem)
    }
  | Ir.Object(fields) =>
    switch collectArray(fields, (field, _) =>
      switch liftEnumSchema(
        ~path=at(at(path, "properties"), field.name),
        ~scope,
        ~segments=appendSegment(segments, field.name),
        ~reservedNames,
        ~liftedSchemas,
        field.schema,
      ) {
      | Ok(schema) => Ok({...field, schema})
      | Error(problem) => Error(problem)
      }
    ) {
    | Ok(nextFields) => Ok(Ir.Object(nextFields))
    | Error(problem) => Error(problem)
    }
  | Ir.Nullable(inner) =>
    switch liftEnumSchema(~path, ~scope, ~segments, ~reservedNames, ~liftedSchemas, inner) {
    | Ok(nextInner) => Ok(Ir.Nullable(nextInner))
    | Error(problem) => Error(problem)
    }
  | Ir.DiscriminatedUnion({discriminator, cases}) =>
    switch collectArray(cases, (case_, _) =>
      switch liftEnumSchema(
        ~path=at(path, case_.tag),
        ~scope,
        ~segments=appendSegment(segments, case_.tag),
        ~reservedNames,
        ~liftedSchemas,
        case_.payload,
      ) {
      | Ok(schema) =>
        let nextCase: Ir.unionCase = {
          tag: case_.tag,
          payload: schema,
        }
        Ok(nextCase)
      | Error(problem) => Error(problem)
      }
    ) {
    | Ok(nextCases) => Ok(Ir.DiscriminatedUnion({discriminator, cases: nextCases}))
    | Error(problem) => Error(problem)
    }
  }

let liftNamedSchemaEnums = (
  namedSchema: Ir.namedSchema,
  ~reservedNames: ref<array<string>>,
  ~liftedSchemas: ref<array<Ir.namedSchema>>,
): result<Ir.namedSchema> => {
  let path = ["components", "schemas", namedSchema.name]

  switch namedSchema.schema {
  | Ir.StringEnum({name: _, values, path: enumPath}) =>
    switch Naming.validateEnumConstructors(~path=enumPath, values) {
    | Ok() =>
      Ok({...namedSchema, schema: Ir.StringEnum({name: namedSchema.name, values, path: enumPath})})
    | Error(problem) => Error(problem)
    }
  | schema =>
    switch liftEnumSchema(
      ~path,
      ~scope=Naming.Component(namedSchema.name),
      ~segments=[],
      ~reservedNames,
      ~liftedSchemas,
      schema,
    ) {
    | Ok(nextSchema) => Ok({...namedSchema, schema: nextSchema})
    | Error(problem) => Error(problem)
    }
  }
}

let liftRequestBodyEnums = (
  operation: Ir.operation,
  requestBody: Ir.requestBody,
  ~reservedNames: ref<array<string>>,
  ~liftedSchemas: ref<array<Ir.namedSchema>>,
): result<Ir.requestBody> =>
  switch liftEnumSchema(
    ~path=[
      "paths",
      operation.path,
      operation.method,
      "requestBody",
      "content",
      "application/json",
      "schema",
    ],
    ~scope=Naming.Request(operation.name),
    ~segments=[],
    ~reservedNames,
    ~liftedSchemas,
    requestBody.schema,
  ) {
  | Ok(schema) => Ok({...requestBody, schema})
  | Error(problem) => Error(problem)
  }

let liftResponseEnums = (
  operation: Ir.operation,
  ~reservedNames: ref<array<string>>,
  ~liftedSchemas: ref<array<Ir.namedSchema>>,
): result<array<Ir.response>> =>
  collectArray(operation.responses, (response, _) =>
    switch response.schema {
    | None => Ok(response)
    | Some(schema) =>
      switch liftEnumSchema(
        ~path=[
          "paths",
          operation.path,
          operation.method,
          "responses",
          response.statusCode,
          "content",
          "application/json",
          "schema",
        ],
        ~scope=Naming.Response(operation.name),
        ~segments=[response.statusCode],
        ~reservedNames,
        ~liftedSchemas,
        schema,
      ) {
      | Ok(nextSchema) => Ok({...response, schema: Some(nextSchema)})
      | Error(problem) => Error(problem)
      }
    }
  )

let liftParameterEnums = (
  operation: Ir.operation,
  ~reservedNames: ref<array<string>>,
  ~liftedSchemas: ref<array<Ir.namedSchema>>,
): result<array<Ir.parameter>> =>
  collectArray(operation.parameters, (parameter, index) =>
    switch liftEnumSchema(
      ~path=[
        "paths",
        operation.path,
        operation.method,
        "parameters",
        Int.toString(index),
        "schema",
      ],
      ~scope=Naming.Parameter(operation.name, parameter.name),
      ~segments=[],
      ~reservedNames,
      ~liftedSchemas,
      parameter.schema,
    ) {
    | Ok(schema) => Ok({...parameter, schema})
    | Error(problem) => Error(problem)
    }
  )

let liftOperationEnums = (
  operation: Ir.operation,
  ~reservedNames: ref<array<string>>,
  ~liftedSchemas: ref<array<Ir.namedSchema>>,
): result<Ir.operation> => {
  let? Ok(parameters) = liftParameterEnums(operation, ~reservedNames, ~liftedSchemas)
  let? Ok(requestBody) = switch operation.requestBody {
  | None => Ok(None)
  | Some(requestBody) =>
    switch liftRequestBodyEnums(operation, requestBody, ~reservedNames, ~liftedSchemas) {
    | Ok(nextBody) => Ok(Some(nextBody))
    | Error(problem) => Error(problem)
    }
  }
  let? Ok(responses) = liftResponseEnums(operation, ~reservedNames, ~liftedSchemas)
  Ok({...operation, parameters, requestBody, responses})
}

let liftReachableEnums = (
  ~operations: array<Ir.operation>,
  ~schemas: array<Ir.namedSchema>,
): result<(array<Ir.operation>, array<Ir.namedSchema>)> => {
  let reservedNames = ref(Array.map(schemas, schema => schema.name))
  let liftedSchemas = ref([])

  switch collectArray(schemas, (schema, _) =>
    liftNamedSchemaEnums(schema, ~reservedNames, ~liftedSchemas)
  ) {
  | Error(problem) => Error(problem)
  | Ok(namedSchemas) =>
    switch collectArray(operations, (operation, _) =>
      liftOperationEnums(operation, ~reservedNames, ~liftedSchemas)
    ) {
    | Error(problem) => Error(problem)
    | Ok(operations) => Ok((operations, Belt.Array.concat(liftedSchemas.contents, namedSchemas)))
    }
  }
}

let decodeSecuritySchemes = (~path: array<string>, root: dict<JSON.t>): result<
  array<Ir.securityScheme>,
> =>
  switch Dict.get(root, "components") {
  | None => Ok([])
  | Some(componentsJson) =>
    switch JSON.Decode.object(componentsJson) {
    | None => Error(Diagnostics.make(~path=at(path, "components"), ~message="Expected object"))
    | Some(components) =>
      switch Dict.get(components, "securitySchemes") {
      | None => Ok([])
      | Some(securityJson) =>
        switch JSON.Decode.object(securityJson) {
        | None =>
          Error(
            Diagnostics.make(~path=["components", "securitySchemes"], ~message="Expected object"),
          )
        | Some(securitySchemesObject) =>
          let schemes = ref([])
          let error = ref(None)

          Dict.forEachWithKey(securitySchemesObject, (schemeJson, name) =>
            switch error.contents {
            | Some(_) => ()
            | None =>
              switch JSON.Decode.object(schemeJson) {
              | None =>
                error.contents = Some(
                  Diagnostics.make(
                    ~path=["components", "securitySchemes", name],
                    ~message="Expected object",
                  ),
                )
              | Some(schemeObject) =>
                let schemePath = ["components", "securitySchemes", name]

                switch JsonDecode.stringField(~path=schemePath, schemeObject, "type") {
                | Ok("apiKey") =>
                  switch (
                    JsonDecode.stringField(~path=schemePath, schemeObject, "name"),
                    JsonDecode.stringField(~path=schemePath, schemeObject, "in"),
                  ) {
                  | (Ok(credentialName), Ok("header")) =>
                    let scheme: Ir.securityScheme = {
                      name,
                      authKind: "apiKey",
                      credentialName: Some(credentialName),
                      location: Some("header"),
                    }
                    schemes.contents = Belt.Array.concat(schemes.contents, [scheme])
                  | (Ok(credentialName), Ok("query")) =>
                    let scheme: Ir.securityScheme = {
                      name,
                      authKind: "apiKey",
                      credentialName: Some(credentialName),
                      location: Some("query"),
                    }
                    schemes.contents = Belt.Array.concat(schemes.contents, [scheme])
                  | (Ok(credentialName), Ok("cookie")) =>
                    let scheme: Ir.securityScheme = {
                      name,
                      authKind: "apiKey",
                      credentialName: Some(credentialName),
                      location: Some("cookie"),
                    }
                    schemes.contents = Belt.Array.concat(schemes.contents, [scheme])
                  | (Ok(_), Ok(location)) =>
                    error.contents = Some(
                      Diagnostics.make(
                        ~path=Belt.Array.concat(schemePath, ["in"]),
                        ~message="Unsupported apiKey location: " ++ location,
                      ),
                    )
                  | (Error(problem), _) => error.contents = Some(problem)
                  | (_, Error(problem)) => error.contents = Some(problem)
                  }
                | Ok("http") =>
                  switch JsonDecode.stringField(~path=schemePath, schemeObject, "scheme") {
                  | Ok("basic") =>
                    let scheme: Ir.securityScheme = {
                      name,
                      authKind: "httpBasic",
                      credentialName: None,
                      location: None,
                    }
                    schemes.contents = Belt.Array.concat(schemes.contents, [scheme])
                  | Ok("bearer") =>
                    let scheme: Ir.securityScheme = {
                      name,
                      authKind: "httpBearer",
                      credentialName: None,
                      location: None,
                    }
                    schemes.contents = Belt.Array.concat(schemes.contents, [scheme])
                  | Ok(httpScheme) =>
                    error.contents = Some(
                      Diagnostics.make(
                        ~path=Belt.Array.concat(schemePath, ["scheme"]),
                        ~message="Unsupported HTTP auth scheme: " ++ httpScheme,
                      ),
                    )
                  | Error(problem) => error.contents = Some(problem)
                  }
                | Ok(kind) =>
                  error.contents = Some(
                    Diagnostics.make(
                      ~path=Belt.Array.concat(schemePath, ["type"]),
                      ~message="Unsupported security scheme: " ++ kind,
                    ),
                  )
                | Error(problem) => error.contents = Some(problem)
                }
              }
            }
          )

          switch error.contents {
          | Some(problem) => Error(problem)
          | None => Ok(schemes.contents)
          }
        }
      }
    }
  }

let decodeTags = (~path: array<string>, root: dict<JSON.t>): result<array<string>> =>
  switch root {
  | dict{"tags": JSON.Array(tagsArray)} =>
    tagsArray->collectArray((tagJson, index) => {
      let tagPath = path->at("tags")->at(Int.toString(index))
      switch JSON.Decode.object(tagJson) {
      | None => Error(Diagnostics.make(~path=tagPath, ~message="Expected object"))
      | Some(tagObject) => JsonDecode.stringField(~path=tagPath, tagObject, "name")
      }
    })
  | dict{"tags": _} => Error(Diagnostics.make(~path=at(path, "tags"), ~message="Expected array"))
  | _ => Ok([])
  }

let decodeDocument = (input: JSON.t): result<Ir.document> => {
  let? Ok(root) =
    JsonDecode.object(~path=[], input)->Result.mapError(_ =>
      Diagnostics.root("Unsupported OpenAPI input")
    )

  let? Ok(openapiVersion) = JsonDecode.stringField(~path=[], root, "openapi")
  let? Ok(info) = JsonDecode.objectField(~path=[], root, "info")
  let? Ok(tags) = decodeTags(~path=[], root)
  let? Ok(security) = decodeTopLevelSecurity(~path=[], root)
  let? Ok(operations) = decodeOperations(~path=[], root)
  let? Ok(schemas) = decodeSchemas(~path=[], root)
  let? Ok(securitySchemes) = decodeSecuritySchemes(~path=[], root)

  if !String.startsWith(openapiVersion, "3.1.") {
    Error(Diagnostics.make(~path=["openapi"], ~message="Only OpenAPI 3.1 documents are supported"))
  } else {
    let? Ok(title) = JsonDecode.stringField(~path=["info"], info, "title")
    let? Ok(version) = JsonDecode.stringField(~path=["info"], info, "version")
    let? Ok(operations) = Naming.normalizeOperations(operations)
    let? Ok((operations, schemas)) = liftReachableEnums(~operations, ~schemas)

    let document: Ir.document = {
      openapiVersion,
      title,
      version,
      tags,
      security,
      operations,
      schemas,
      securitySchemes,
    }
    Ok(document)
  }
}
