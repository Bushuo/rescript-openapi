type rec schema =
  | Scalar(string)
  | Array(schema)
  | Object(array<objectField>)

and objectField = {
  name: string,
  required: bool,
  schema: schema,
}

type namedSchema = {
  name: string,
  schema: schema,
}

type document = {
  openapiVersion: string,
  title: string,
  version: string,
  operations: array<string>,
  schemas: array<namedSchema>,
}
