// exposed types
type diagnostic = Diagnostics.diagnostic
type enumMode = Ir.enumMode
type file = Printer.file

type output = {
  ok: bool,
  value: option<Ir.document>,
  error: option<Diagnostics.diagnostic>,
  files: array<Printer.file>,
}

type options = {
  enumMode: enumMode,
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

let defaultOptions: options = {enumMode: Open}

let validateCodegenOptions = (document: Ir.document, options: options): result<
  unit,
  Diagnostics.diagnostic,
> => {
  let error = ref(None)

  if options.enumMode == Open {
    Array.forEach(document.schemas, schema =>
      switch (error.contents, schema.schema) {
      | (Some(_), _) => ()
      | (None, Ir.StringEnum({values, path, _})) =>
        switch Naming.validateReservedEnumConstructor(
          ~path,
          ~reservedConstructorName="Unknown",
          values,
        ) {
        | Ok() => ()
        | Error(problem) => error.contents = Some(problem)
        }
      | (None, _) => ()
      }
    )
  }

  switch error.contents {
  | Some(problem) => Error(problem)
  | None => Ok()
  }
}

let emitFiles = (document: Ir.document, options: options): array<Printer.file> => {
  let clientFile = EmitClient.emit(document)
  let indexFile = EmitIndex.emit(~tagModules=EmitTagModule.moduleNames(document))
  let modelsFile = EmitModels.emit(document, ~enumMode=options.enumMode)
  let tagFiles = EmitTagModule.emitAll(document)
  let schemasFile = EmitSchemas.emit(document, ~enumMode=options.enumMode)

  Belt.Array.concatMany([[clientFile, indexFile, modelsFile], tagFiles, [schemasFile]])
}

type generator = (JSON.t, ~options: options=?) => output

let generate: generator = (input, ~options=defaultOptions) =>
  switch decodeDocument(input) {
  | Ok(document) =>
    switch validateCodegenOptions(document, options) {
    | Ok() => success(document, emitFiles(document, options))
    | Error(error) => failure(error)
    }
  | Error(error) => failure(error)
  }
