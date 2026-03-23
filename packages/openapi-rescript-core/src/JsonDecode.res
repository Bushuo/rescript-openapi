type result<'a> = result<'a, Diagnostics.diagnostic>

let at = (path: array<string>, segment: string) => Belt.Array.concat(path, [segment])

let object = (~path: array<string>, json: JSON.t): result<dict<JSON.t>> =>
  switch JSON.Decode.object(json) {
  | Some(value) => Ok(value)
  | _ => Error(Diagnostics.make(~path, ~message="Expected object"))
  }

let string = (~path: array<string>, json: JSON.t): result<string> =>
  switch JSON.Decode.string(json) {
  | Some(value) => Ok(value)
  | None => Error(Diagnostics.make(~path, ~message="Expected string"))
  }

let requiredField = (
  ~path: array<string>,
  dict: dict<JSON.t>,
  name: string,
): result<JSON.t> =>
  switch Dict.get(dict, name) {
  | Some(value) => Ok(value)
  | None => Error(Diagnostics.make(~path=at(path, name), ~message="Missing required field"))
  }

let objectField = (
  ~path: array<string>,
  dict: dict<JSON.t>,
  name: string,
): result<dict<JSON.t>> =>
  switch requiredField(~path, dict, name) {
  | Ok(value) => object(~path=at(path, name), value)
  | Error(error) => Error(error)
  }

let stringField = (
  ~path: array<string>,
  dict: dict<JSON.t>,
  name: string,
): result<string> =>
  switch requiredField(~path, dict, name) {
  | Ok(value) => string(~path=at(path, name), value)
  | Error(error) => Error(error)
  }
