let appendUnique = (values: array<string>, value: string): array<string> =>
  if Array.some(values, existing => existing == value) {
    values
  } else {
    Belt.Array.concat(values, [value])
  }

let rec collectNamedSchemaDependencies = (schema: Ir.schema): array<string> =>
  switch schema {
  | Ir.Scalar(_) | Ir.StringEnum(_) => []
  | Ir.Array(item) => collectNamedSchemaDependencies(item)
  | Ir.Nullable(inner) => collectNamedSchemaDependencies(inner)
  | Ir.NamedRef(reference) => [Printer.refName(reference)]
  | Ir.DiscriminatedUnion({cases, _}) =>
    let dependencies = ref([])

    Array.forEach(cases, case_ =>
      Array.forEach(collectNamedSchemaDependencies(case_.payload), dependency => {
        dependencies.contents = appendUnique(dependencies.contents, dependency)
      })
    )

    dependencies.contents
  | Ir.Object(fields) =>
    let dependencies = ref([])

    Array.forEach(fields, field =>
      Array.forEach(collectNamedSchemaDependencies(field.schema), dependency => {
        dependencies.contents = appendUnique(dependencies.contents, dependency)
      })
    )

    dependencies.contents
  }

let orderSchemas = (schemas: array<Ir.namedSchema>): array<Ir.namedSchema> => {
  let ordered = ref([])
  let permanent = ref([])
  let temporary = ref([])

  let rec visit = (schema: Ir.namedSchema): unit =>
    if Array.some(permanent.contents, name => name == schema.name) {
      ()
    } else if Array.some(temporary.contents, name => name == schema.name) {
      ()
    } else {
      temporary.contents = Belt.Array.concat(temporary.contents, [schema.name])

      Array.forEach(collectNamedSchemaDependencies(schema.schema), dependencyName =>
        switch Array.find(schemas, candidate => candidate.name == dependencyName) {
        | Some(dependency) => visit(dependency)
        | None => ()
        }
      )

      temporary.contents = Belt.Array.keep(temporary.contents, name => name != schema.name)
      permanent.contents = Belt.Array.concat(permanent.contents, [schema.name])
      ordered.contents = Belt.Array.concat(ordered.contents, [schema])
    }

  Array.forEach(schemas, visit)
  ordered.contents
}
