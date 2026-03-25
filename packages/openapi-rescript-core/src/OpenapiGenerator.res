type output = {
  ok: bool,
  value: option<Ir.document>,
  error: option<Diagnostics.diagnostic>,
  files: array<Printer.file>,
}

type options = {
  enumMode: Ir.enumMode,
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

let defaultOptions: options = {enumMode: Ir.Open}

let emitFiles = (document: Ir.document, options: options): array<Printer.file> => {
  let clientFile = EmitClient.emit(document)
  let indexFile = EmitIndex.emit(~tagModules=EmitTagModule.moduleNames(document))
  let modelsFile = EmitModels.emit(document, ~enumMode=options.enumMode)
  let tagFiles = EmitTagModule.emitAll(document)
  let schemasFile = EmitSchemas.emit(document, ~enumMode=options.enumMode)

  Belt.Array.concatMany([[clientFile, indexFile, modelsFile], tagFiles, [schemasFile]])
}

let generate = (input: JSON.t, ~options: options=defaultOptions): output =>
  switch decodeDocument(input) {
  | Ok(document) => success(document, emitFiles(document, options))
  | Error(error) => failure(error)
  }
