type output = {
  ok: bool,
  value: option<Ir.document>,
  error: option<Diagnostics.diagnostic>,
  files: array<Printer.file>,
}

let success = (value: Ir.document, files: array<Printer.file>): output => {
  ok: true,
  value: Some(value),
  error: None,
  files,
}

let failure = (error: Diagnostics.diagnostic): output => {
  ok: false,
  value: None,
  error: Some(error),
  files: [],
}

let decodeDocument = OpenapiDecode.decodeDocument

let emitFiles = (document: Ir.document): array<Printer.file> => {
  let clientFile = EmitClient.emit(document)
  let indexFile = EmitIndex.emit(~tagModules=EmitTagModule.moduleNames(document))
  let modelsFile = EmitModels.emit(document)
  let tagFiles = EmitTagModule.emitAll(document)
  let schemasFile = EmitSchemas.emit(document)

  Belt.Array.concatMany([[clientFile, indexFile, modelsFile], tagFiles, [schemasFile]])
}

let generate = (input: JSON.t): output =>
  switch decodeDocument(input) {
  | Ok(document) => success(document, emitFiles(document))
  | Error(error) => failure(error)
  }
