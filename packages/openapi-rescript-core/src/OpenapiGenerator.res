// exposed types
type diagnostic = Diagnostics.diagnostic
type enumMode = Ir.enumMode
type scalarOverride = Ir.scalarOverride
type file = Printer.file

type output = {
  ok: bool,
  value: option<Ir.document>,
  error: option<Diagnostics.diagnostic>,
  files: array<Printer.file>,
}

type options = {
  enumMode: enumMode,
  scalars: array<scalarOverride>,
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

let defaultOptions: options = {enumMode: Open, scalars: []}

@get external optionScalars: options => option<array<scalarOverride>> = "scalars"

let normalizeOptions = (options: options): options => {
  enumMode: options.enumMode,
  scalars: options->optionScalars->Option.getOr([]),
}

let scalarWireType = (key: string): string =>
  switch key->String.split(":")->Array.get(0) {
  | Some(wireType) => wireType
  | None => key
  }

let findScalarOverride = (key: string, scalars: array<scalarOverride>): option<scalarOverride> =>
  scalars->Array.find(scalar => scalar.key == key)

let rec applyScalarMappingsToSchema = (
  schema: Ir.schema,
  scalars: array<scalarOverride>,
): Ir.schema =>
  switch schema {
  | Ir.Scalar(key) =>
    switch findScalarOverride(key, scalars) {
    | Some(scalar) =>
      Ir.MappedScalar({
        wireType: scalarWireType(key),
        typeName: scalar.typeName,
        moduleName: scalar.moduleName,
      })
    | None => schema
    }
  | Ir.MappedScalar(_) | Ir.StringEnum(_) | Ir.NamedRef(_) => schema
  | Ir.Array(item) => Ir.Array(applyScalarMappingsToSchema(item, scalars))
  | Ir.Nullable(inner) => Ir.Nullable(applyScalarMappingsToSchema(inner, scalars))
  | Ir.Object(fields) =>
    Ir.Object(
      fields->Array.map(field => {
        ...field,
        schema: applyScalarMappingsToSchema(field.schema, scalars),
      }),
    )
  | Ir.DiscriminatedUnion({discriminator, cases}) =>
    Ir.DiscriminatedUnion({
      discriminator,
      cases: cases->Array.map(case_ => {
        let nextCase: Ir.unionCase = {
          tag: case_.tag,
          payload: applyScalarMappingsToSchema(case_.payload, scalars),
        }
        nextCase
      }),
    })
  }

let applyScalarMappingsToDocument = (
  document: Ir.document,
  scalars: array<scalarOverride>,
): Ir.document => {
  if Array.length(scalars) == 0 {
    document
  } else {
    {
      ...document,
      operations: document.operations->Array.map(operation => {
        ...operation,
        parameters: operation.parameters->Array.map(parameter => {
          ...parameter,
          schema: applyScalarMappingsToSchema(parameter.schema, scalars),
        }),
        requestBody: operation.requestBody->Option.map(body => {
          ...body,
          schema: applyScalarMappingsToSchema(body.schema, scalars),
        }),
        responses: operation.responses->Array.map(response => {
          ...response,
          schema: response.schema->Option.map(
            schema => applyScalarMappingsToSchema(schema, scalars),
          ),
        }),
      }),
      schemas: document.schemas->Array.map((schema: Ir.namedSchema) => {
        ...schema,
        schema: applyScalarMappingsToSchema(schema.schema, scalars),
      }),
    }
  }
}

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

let generate: generator = (input, ~options=defaultOptions) => {
  let options = normalizeOptions(options)

  switch decodeDocument(input) {
  | Ok(document) =>
    let document = applyScalarMappingsToDocument(document, options.scalars)
    switch validateCodegenOptions(document, options) {
    | Ok() => success(document, emitFiles(document, options))
    | Error(error) => failure(error)
    }
  | Error(error) => failure(error)
  }
}
