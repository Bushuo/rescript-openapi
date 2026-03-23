type output = {
  ok: bool,
  value: option<Ir.document>,
  error: option<Diagnostics.diagnostic>,
}

let success = (value: Ir.document): output => {
  ok: true,
  value: Some(value),
  error: None,
}

let failure = (error: Diagnostics.diagnostic): output => {
  ok: false,
  value: None,
  error: Some(error),
}

let decodeDocument = (input: JSON.t): result<Ir.document, Diagnostics.diagnostic> =>
  switch JsonDecode.object(~path=[], input) {
  | Error(_) => Error(Diagnostics.root("Unsupported OpenAPI input"))
  | Ok(root) =>
    switch (
      JsonDecode.stringField(~path=[], root, "openapi"),
      JsonDecode.objectField(~path=[], root, "info"),
      JsonDecode.objectField(~path=[], root, "paths"),
    ) {
    | (Ok(openapiVersion), Ok(info), Ok(_)) =>
      if !String.startsWith(openapiVersion, "3.1.") {
        Error(Diagnostics.make(~path=["openapi"], ~message="Only OpenAPI 3.1 documents are supported"))
      } else {
        switch (
          JsonDecode.stringField(~path=["info"], info, "title"),
          JsonDecode.stringField(~path=["info"], info, "version"),
        ) {
        | (Ok(title), Ok(version)) =>
          Ok({
            openapiVersion,
            title,
            version,
            operations: [],
            schemas: [],
          })
        | (Error(error), _) => Error(error)
        | (_, Error(error)) => Error(error)
        }
      }
    | (Error(error), _, _) => Error(error)
    | (_, Error(error), _) => Error(error)
    | (_, _, Error(error)) => Error(error)
    }
  }

let generate = (input: JSON.t): output =>
  switch decodeDocument(input) {
  | Ok(document) => success(document)
  | Error(error) => failure(error)
  }
