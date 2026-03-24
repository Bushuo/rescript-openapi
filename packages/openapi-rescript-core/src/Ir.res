type rec schema =
  | Scalar(string)
  | Array(schema)
  | Object(array<objectField>)
  | NamedRef(string)

and objectField = {
  name: string,
  required: bool,
  schema: schema,
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

type operation = {
  operationId: option<string>,
  method: string,
  path: string,
  tags: array<string>,
  parameters: array<parameter>,
  requestBody: option<requestBody>,
  responses: array<response>,
  security: array<string>,
}

type securityScheme = {
  name: string,
  kind: string,
}

type document = {
  openapiVersion: string,
  title: string,
  version: string,
  tags: array<string>,
  security: array<string>,
  operations: array<operation>,
  schemas: array<namedSchema>,
  securitySchemes: array<securityScheme>,
}
