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

let decodeDocument = OpenapiDecode.decodeDocument

let generate = (input: JSON.t): output =>
  switch decodeDocument(input) {
  | Ok(document) => success(document)
  | Error(error) => failure(error)
  }
