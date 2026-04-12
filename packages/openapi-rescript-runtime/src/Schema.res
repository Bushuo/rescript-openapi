module S = S

let _ = S.enableJson()

type t<'value> = S.t<'value>
type any = t<unknown>

type field = {
  name: string,
  required: bool,
  schema: any,
}

type descriptor = {
  name: string,
  required: bool,
}

type unionCase<'value> = {
  tag: string,
  schema: any,
  wrap: unknown => 'value,
  unwrap: 'value => option<unknown>,
}

let toAny = (schema: t<'value>): any => S.castToUnknown(schema)

let field = (descriptor: descriptor, schema: t<'value>): field => {
  name: descriptor.name,
  required: descriptor.required,
  schema: schema->toAny,
}

let makeField = (~name: string, ~required: bool, schema: t<'value>): field =>
  field({name, required}, schema)

let string: t<string> = S.string
let int: t<int> = S.int
let integer = int
let float: t<float> = S.float
let number = float
let bool: t<bool> = S.bool
let boolean = bool

let stringMapped = (~decode: string => result<'value, string>, ~encode: 'value => string): t<'value> =>
  string->S.transform(s => {
    parser: value =>
      switch decode(value) {
      | Ok(decoded) => decoded
      | Error(message) => s.fail(message)
      },
    serializer: encode,
  })

let array = (item: t<'value>): t<array<'value>> => S.array(item)

let nullableAsOption = (schema: t<'value>): t<option<'value>> => S.null(schema)

let stripDiscriminator = (discriminator: string, objectJson: dict<Js.Json.t>): dict<Js.Json.t> => {
  let payload = Dict.make()

  Dict.forEachWithKey(objectJson, (value, key) => {
    if key != discriminator {
      Dict.set(payload, key, value)
    }
  })

  payload
}

let addDiscriminator = (
  discriminator: string,
  tag: string,
  payloadJson: dict<Js.Json.t>,
): dict<Js.Json.t> => {
  let output = Dict.make()

  Dict.forEachWithKey(payloadJson, (value, key) => Dict.set(output, key, value))
  Dict.set(output, discriminator, JSON.String(tag))
  output
}

let discriminatedUnion = (
  ~discriminator: string,
  cases: array<unionCase<'value>>,
): t<'value> =>
  S.dict(S.json)->S.transform(s => {
    parser: objectJson =>
      switch Dict.get(objectJson, discriminator) {
      | None => s.fail("Missing discriminator: " ++ discriminator)
      | Some(tagJson) =>
        switch JSON.Decode.string(tagJson) {
        | None => s.fail("Discriminator must be a string: " ++ discriminator)
        | Some(tag) =>
          switch Array.find(cases, case_ => case_.tag == tag) {
          | None => s.fail("Unknown discriminator value: " ++ tag)
          | Some(case_) =>
            case_.wrap(S.parseOrThrow(stripDiscriminator(discriminator, objectJson), case_.schema))
          }
        }
      },
    serializer: value =>
      switch Array.find(cases, case_ =>
        switch case_.unwrap(value) {
        | Some(_) => true
        | None => false
        }
      ) {
      | None => s.fail("Unsupported discriminated union case")
      | Some(case_) =>
        switch case_.unwrap(value) {
        | None => s.fail("Unsupported discriminated union case")
        | Some(payload) =>
          switch JSON.Decode.object(S.reverseConvertToJsonOrThrow(payload, case_.schema)) {
          | Some(payloadJson) => addDiscriminator(discriminator, case_.tag, payloadJson)
          | None => s.fail("Discriminated union payload must encode to an object")
          }
        }
      },
  })

let object_ = (fields: array<field>): t<'value> =>
  S.object(s => {
    let output = Dict.make()

    Array.forEach(fields, field => {
      let value: unknown = if field.required {
        Obj.magic(s.field(field.name, field.schema))
      } else {
        Obj.magic(s.fieldOr(field.name, S.option(field.schema), None))
      }

      Dict.set(output, field.name, Obj.magic(value))
    })

    Obj.magic(output)
  })->Obj.magic
