type result<'a> = result<'a, Diagnostics.diagnostic>

let at = (path: array<string>, segment: string) => Belt.Array.concat(path, [segment])

let collectArray = (items: array<'a>, fn: ('a, int) => result<'b>): result<array<'b>> => {
  let values = ref([])
  let error = ref(None)

  Belt.Array.forEachWithIndex(items, (index, item) =>
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
      | None => Error(Diagnostics.make(~path=at(path, Int.toString(index)), ~message="Expected string"))
      }
    )
  }

let optionalStringArrayField = (~path: array<string>, dict: dict<JSON.t>, name: string): result<array<string>> =>
  switch Dict.get(dict, name) {
  | None => Ok([])
  | Some(value) => decodeStringArray(~path=at(path, name), value)
  }

let decodeOptionalSchema = (~path: array<string>, contentObject: dict<JSON.t>): result<option<Ir.schema>> =>
  switch Dict.get(contentObject, "application/json") {
  | Some(contentJson) =>
    switch JSON.Decode.object(contentJson) {
    | None => Error(Diagnostics.make(~path=at(path, "application/json"), ~message="Expected object"))
    | Some(applicationJson) =>
      switch JsonDecode.requiredField(~path=at(path, "application/json"), applicationJson, "schema") {
      | Ok(schemaJson) =>
        switch SchemaDecode.decode(~path=at(at(path, "application/json"), "schema"), schemaJson) {
        | Ok(schema) => Ok(Some(schema))
        | Error(problem) => Error(problem)
        }
      | Error(problem) => Error(problem)
      }
    }
  | None =>
    switch Belt.Array.getBy(Dict.toArray(contentObject), entry =>
      switch entry {
      | (contentType, _) => String.endsWith(contentType, "+json")
      }
    ) {
    | Some((contentType, contentJson)) =>
      switch JSON.Decode.object(contentJson) {
      | None => Error(Diagnostics.make(~path=at(path, contentType), ~message="Expected object"))
      | Some(contentEntry) =>
        switch JsonDecode.requiredField(~path=at(path, contentType), contentEntry, "schema") {
        | Ok(schemaJson) =>
          switch SchemaDecode.decode(~path=at(at(path, contentType), "schema"), schemaJson) {
          | Ok(schema) => Ok(Some(schema))
          | Error(problem) => Error(problem)
          }
        | Error(problem) => Error(problem)
        }
      }
    | None =>
      if Belt.Array.length(Dict.keysToArray(contentObject)) == 0 {
        Ok(None)
      } else {
        Error(Diagnostics.make(~path, ~message="Only JSON media types are supported"))
      }
    }
  }

let decodeRequestBody = (~path: array<string>, operationObject: dict<JSON.t>): result<option<Ir.requestBody>> =>
  switch Dict.get(operationObject, "requestBody") {
  | None => Ok(None)
  | Some(bodyJson) =>
    switch JSON.Decode.object(bodyJson) {
    | None => Error(Diagnostics.make(~path=at(path, "requestBody"), ~message="Expected object"))
    | Some(bodyObject) =>
      let required =
        switch Dict.get(bodyObject, "required")->Belt.Option.flatMap(JSON.Decode.bool) {
        | Some(value) => value
        | None => false
        }

      switch JsonDecode.requiredField(~path=at(path, "requestBody"), bodyObject, "content") {
      | Ok(contentJson) =>
        switch JSON.Decode.object(contentJson) {
        | None => Error(Diagnostics.make(~path=at(at(path, "requestBody"), "content"), ~message="Expected object"))
        | Some(contentObject) =>
          switch decodeOptionalSchema(~path=at(at(path, "requestBody"), "content"), contentObject) {
          | Ok(Some(schema)) =>
            let requestBody: Ir.requestBody = {required, schema}
            Ok(Some(requestBody))
          | Ok(None) => Ok(None)
          | Error(problem) => Error(problem)
          }
        }
      | Error(problem) => Error(problem)
      }
    }
  }

let decodeResponses = (~path: array<string>, operationObject: dict<JSON.t>): result<array<Ir.response>> =>
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
        | None => error.contents = Some(Diagnostics.make(~path=responsePath, ~message="Expected object"))
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
              error.contents = Some(Diagnostics.make(~path=at(responsePath, "content"), ~message="Expected object"))
            | Some(contentObject) =>
              switch decodeOptionalSchema(~path=at(responsePath, "content"), contentObject) {
              | Ok(schema) => append(schema)
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

let decodeParameters = (~path: array<string>, operationObject: dict<JSON.t>): result<array<Ir.parameter>> =>
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
            JsonDecode.requiredField(~path=parameterPath, parameterObject, "schema"),
          ) {
          | (Ok(name), Ok(location), Ok(schemaJson)) =>
            switch SchemaDecode.decode(~path=at(parameterPath, "schema"), schemaJson) {
            | Ok(schema) =>
              let required =
                switch Dict.get(parameterObject, "required")->Belt.Option.flatMap(JSON.Decode.bool) {
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
          | (Error(problem), _, _) => Error(problem)
          | (_, Error(problem), _) => Error(problem)
          | (_, _, Error(problem)) => Error(problem)
          }
        }
      })
    }
  }

let decodeSecurityNames = (~path: array<string>, source: dict<JSON.t>, name: string): result<array<string>> =>
  switch Dict.get(source, name) {
  | None => Ok([])
  | Some(securityJson) =>
    switch JSON.Decode.array(securityJson) {
    | None => Error(Diagnostics.make(~path=at(path, name), ~message="Expected array"))
    | Some(securityArray) =>
      collectArray(securityArray, (entryJson, index) => {
        let entryPath = at(at(path, name), Int.toString(index))
        switch JSON.Decode.object(entryJson) {
        | None => Error(Diagnostics.make(~path=entryPath, ~message="Expected object"))
        | Some(securityObject) =>
          switch Belt.Array.get(Dict.keysToArray(securityObject), 0) {
          | Some(securityName) => Ok(securityName)
          | None => Error(Diagnostics.make(~path=entryPath, ~message="Expected security requirement"))
          }
        }
      })
    }
  }

let decodeOperation = (
  ~routePath: string,
  ~method_: string,
  ~operationPath: array<string>,
  operationJson: JSON.t,
): result<Ir.operation> =>
  switch JSON.Decode.object(operationJson) {
  | None => Error(Diagnostics.make(~path=operationPath, ~message="Expected object"))
  | Some(operationObject) =>
    let operationId = Dict.get(operationObject, "operationId")->Belt.Option.flatMap(JSON.Decode.string)

    switch (
      optionalStringArrayField(~path=operationPath, operationObject, "tags"),
      decodeParameters(~path=operationPath, operationObject),
      decodeRequestBody(~path=operationPath, operationObject),
      decodeResponses(~path=operationPath, operationObject),
      decodeSecurityNames(~path=operationPath, operationObject, "security"),
    ) {
    | (Ok(tags), Ok(parameters), Ok(requestBody), Ok(responses), Ok(security)) =>
      let operation: Ir.operation = {
        operationId,
        method: method_,
        path: routePath,
        tags,
        parameters,
        requestBody,
        responses,
        security,
      }
      Ok(operation)
    | (Error(problem), _, _, _, _) => Error(problem)
    | (_, Error(problem), _, _, _) => Error(problem)
    | (_, _, Error(problem), _, _) => Error(problem)
    | (_, _, _, Error(problem), _) => Error(problem)
    | (_, _, _, _, Error(problem)) => Error(problem)
    }
  }

let operationMethods = ["get", "post", "put", "patch", "delete", "options", "head", "trace"]

let decodeOperations = (~path: array<string>, root: dict<JSON.t>): result<array<Ir.operation>> =>
  switch JsonDecode.objectField(~path, root, "paths") {
  | Error(problem) => Error(problem)
  | Ok(pathsObject) =>
    let operations = ref([])
    let error = ref(None)

    Dict.forEachWithKey(pathsObject, (pathJson, routePath) =>
      switch error.contents {
      | Some(_) => ()
      | None =>
        switch JSON.Decode.object(pathJson) {
        | None => error.contents = Some(Diagnostics.make(~path=["paths", routePath], ~message="Expected object"))
        | Some(pathObject) =>
          Belt.Array.forEach(operationMethods, method_ =>
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
                  operationJson,
                ) {
                | Ok(operation) =>
                  operations.contents = Belt.Array.concat(operations.contents, [operation])
                | Error(problem) => error.contents = Some(problem)
                }
              }
            }
          )
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
        | None => Error(Diagnostics.make(~path=["components", "schemas"], ~message="Expected object"))
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
                decodedSchemas.contents = Belt.Array.concat(decodedSchemas.contents, [namedSchema])
              | Error(problem) => error.contents = Some(problem)
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

let decodeSecuritySchemes = (~path: array<string>, root: dict<JSON.t>): result<array<Ir.securityScheme>> =>
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
        | None => Error(Diagnostics.make(~path=["components", "securitySchemes"], ~message="Expected object"))
        | Some(securitySchemesObject) =>
          let schemes = ref([])
          let error = ref(None)

          Dict.forEachWithKey(securitySchemesObject, (schemeJson, name) =>
            switch error.contents {
            | Some(_) => ()
            | None =>
              switch JSON.Decode.object(schemeJson) {
              | None =>
                error.contents = Some(Diagnostics.make(~path=["components", "securitySchemes", name], ~message="Expected object"))
              | Some(schemeObject) =>
                switch JsonDecode.stringField(~path=["components", "securitySchemes", name], schemeObject, "type") {
                | Ok(kind) =>
                  let scheme: Ir.securityScheme = {name, kind}
                  schemes.contents = Belt.Array.concat(schemes.contents, [scheme])
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
  switch Dict.get(root, "tags") {
  | None => Ok([])
  | Some(tagsJson) =>
    switch JSON.Decode.array(tagsJson) {
    | None => Error(Diagnostics.make(~path=at(path, "tags"), ~message="Expected array"))
    | Some(tagsArray) =>
      collectArray(tagsArray, (tagJson, index) => {
        let tagPath = at(at(path, "tags"), Int.toString(index))
        switch JSON.Decode.object(tagJson) {
        | None => Error(Diagnostics.make(~path=tagPath, ~message="Expected object"))
        | Some(tagObject) => JsonDecode.stringField(~path=tagPath, tagObject, "name")
        }
      })
    }
  }

let decodeTopLevelSecurity = (~path: array<string>, root: dict<JSON.t>): result<array<string>> =>
  decodeSecurityNames(~path, root, "security")

let decodeDocument = (input: JSON.t): result<Ir.document> =>
  switch JsonDecode.object(~path=[], input) {
  | Error(_) => Error(Diagnostics.root("Unsupported OpenAPI input"))
  | Ok(root) =>
    switch (
      JsonDecode.stringField(~path=[], root, "openapi"),
      JsonDecode.objectField(~path=[], root, "info"),
      decodeTags(~path=[], root),
      decodeTopLevelSecurity(~path=[], root),
      decodeOperations(~path=[], root),
      decodeSchemas(~path=[], root),
      decodeSecuritySchemes(~path=[], root),
    ) {
    | (Ok(openapiVersion), Ok(info), Ok(tags), Ok(security), Ok(operations), Ok(schemas), Ok(securitySchemes)) =>
      if !String.startsWith(openapiVersion, "3.1.") {
        Error(Diagnostics.make(~path=["openapi"], ~message="Only OpenAPI 3.1 documents are supported"))
      } else {
        switch (
          JsonDecode.stringField(~path=["info"], info, "title"),
          JsonDecode.stringField(~path=["info"], info, "version"),
        ) {
        | (Ok(title), Ok(version)) =>
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
        | (Error(problem), _) => Error(problem)
        | (_, Error(problem)) => Error(problem)
        }
      }
    | (Error(problem), _, _, _, _, _, _) => Error(problem)
    | (_, Error(problem), _, _, _, _, _) => Error(problem)
    | (_, _, Error(problem), _, _, _, _) => Error(problem)
    | (_, _, _, Error(problem), _, _, _) => Error(problem)
    | (_, _, _, _, Error(problem), _, _) => Error(problem)
    | (_, _, _, _, _, Error(problem), _) => Error(problem)
    | (_, _, _, _, _, _, Error(problem)) => Error(problem)
    }
  }
