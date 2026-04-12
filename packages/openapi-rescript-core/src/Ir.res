type enumMode =
  | @as("open") Open
  | @as("closed") Closed

type rec schema =
  | Scalar(string)
  | StringEnum({name: string, values: array<string>, path: array<string>})
  | Array(schema)
  | Object(array<objectField>)
  | NamedRef(string)
  | Nullable(schema)
  | DiscriminatedUnion({discriminator: string, cases: array<unionCase>})

and objectField = {
  name: string,
  required: bool,
  schema: schema,
}

and unionCase = {
  tag: string,
  payload: schema,
}

type namedSchema = {
  name: string,
  schema: schema,
}

type parameter = {
  name: string,
  location: string,
  required: bool,
  schema: schema,
}

type requestBody = {
  required: bool,
  schema: schema,
}

type response = {
  statusCode: string,
  schema: option<schema>,
}

type securityRequirement = array<string>

type operation = {
  operationId: option<string>,
  name: string,
  method: string,
  path: string,
  tags: array<string>,
  parameters: array<parameter>,
  requestBody: option<requestBody>,
  responses: array<response>,
  security: option<array<securityRequirement>>,
}

type securityScheme = {
  name: string,
  authKind: string,
  credentialName: option<string>,
  location: option<string>,
}

type document = {
  openapiVersion: string,
  title: string,
  version: string,
  tags: array<string>,
  security: array<securityRequirement>,
  operations: array<operation>,
  schemas: array<namedSchema>,
  securitySchemes: array<securityScheme>,
}
