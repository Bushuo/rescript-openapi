type result<'a> = result<'a, OpenapiGenerator.diagnostic>

let at = (path: array<string>, segment: string) => Belt.Array.concat(path, [segment])

let diagnostic = (~path: array<string>, ~message: string): OpenapiGenerator.diagnostic => {
  path,
  message,
}

let stringField = (~path: array<string>, object: dict<JSON.t>, name: string): result<string> =>
  switch Dict.get(object, name) {
  | None => Error(diagnostic(~path=at(path, name), ~message="Missing required field"))
  | Some(json) =>
    switch JSON.Decode.string(json) {
    | Some(value) => Ok(value)
    | None => Error(diagnostic(~path=at(path, name), ~message="Expected string"))
    }
  }

let decodeScalarOverride = (~path: array<string>, key: string, json: JSON.t): result<
  OpenapiGenerator.scalarOverride,
> =>
  if !(key->String.startsWith("string:")) {
    Error(diagnostic(~path, ~message="Only string format scalar overrides are supported"))
  } else {
    switch JSON.Decode.object(json) {
    | None => Error(diagnostic(~path, ~message="Expected object"))
    | Some(object) =>
      let? Ok(typeName) = stringField(~path, object, "type")
      let? Ok(moduleName) = stringField(~path, object, "module")
      Ok({
        key,
        typeName,
        moduleName,
      })
    }
  }

let decodeScalars = (~path: array<string>, json: JSON.t): result<
  array<OpenapiGenerator.scalarOverride>,
> =>
  switch JSON.Decode.object(json) {
  | None => Error(diagnostic(~path, ~message="Expected object"))
  | Some(scalarsObject) =>
    let output = ref([])
    let error = ref(None)

    Dict.forEachWithKey(scalarsObject, (scalarJson, key) =>
      switch error.contents {
      | Some(_) => ()
      | None =>
        switch decodeScalarOverride(~path=at(path, key), key, scalarJson) {
        | Ok(scalar) => output := Belt.Array.concat(output.contents, [scalar])
        | Error(problem) => error := Some(problem)
        }
      }
    )

    switch error.contents {
    | Some(problem) => Error(problem)
    | None => Ok(output.contents)
    }
  }

let loadOptions = async (path: string, options: OpenapiGenerator.options): result<
  OpenapiGenerator.options,
> => {
  try {
    let contents = await Node.Fs.readFilePromise(path, ~encoding="utf8")
    let parsed = JSON.parseOrThrow(contents)

    switch JSON.Decode.object(parsed) {
    | None => Error(diagnostic(~path=[], ~message="Expected object"))
    | Some(object) =>
      switch Dict.get(object, "scalars") {
      | None => Ok(options)
      | Some(scalarsJson) =>
        switch decodeScalars(~path=["scalars"], scalarsJson) {
        | Ok(scalars) => Ok({...options, scalars})
        | Error(problem) => Error(problem)
        }
      }
    }
  } catch {
  | JsExn(exn) =>
    Error(diagnostic(~path=[], ~message=exn->JsExn.message->Option.getOr(String.make(exn))))
  }
}
