type result<'a> = result<'a, Diagnostics.diagnostic>

let at = (path: array<string>, segment: string) => Belt.Array.concat(path, [segment])

let operationMethods = ["get", "post", "put", "patch", "delete", "options", "head", "trace"]

let decodeOperation = (
  ~routePath: string,
  ~method_: string,
  ~operationPath: array<string>,
  operationJson: JSON.t,
): result<Ir.operation> =>
  switch JSON.Decode.object(operationJson) {
  | None => Error(Diagnostics.make(~path=operationPath, ~message="Expected object"))
  | Some(operationObject) =>
    switch JsonDecode.stringField(~path=operationPath, operationObject, "operationId") {
    | Ok(operationId) =>
      let operation: Ir.operation = {
        operationId: Some(operationId),
        method: method_,
        path: routePath,
        tags: [],
        parameters: [],
        requestBody: None,
        responses: [],
        security: [],
      }
      Ok(operation)
    | Error(problem) => Error(problem)
    }
  }

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

let decodeDocument = (input: JSON.t): result<Ir.document> =>
  switch JsonDecode.object(~path=[], input) {
  | Error(_) => Error(Diagnostics.root("Unsupported OpenAPI input"))
  | Ok(root) =>
    switch (
      JsonDecode.stringField(~path=[], root, "openapi"),
      JsonDecode.objectField(~path=[], root, "info"),
      decodeOperations(~path=[], root),
      decodeSchemas(~path=[], root),
    ) {
    | (Ok(openapiVersion), Ok(info), Ok(operations), Ok(schemas)) =>
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
            tags: [],
            operations,
            schemas,
            securitySchemes: [],
          }
          Ok(document)
        | (Error(problem), _) => Error(problem)
        | (_, Error(problem)) => Error(problem)
        }
      }
    | (Error(problem), _, _, _) => Error(problem)
    | (_, Error(problem), _, _) => Error(problem)
    | (_, _, Error(problem), _) => Error(problem)
    | (_, _, _, Error(problem)) => Error(problem)
    }
  }
