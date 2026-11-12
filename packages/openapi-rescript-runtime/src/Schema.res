module S = S

type t<'value> = S.t<'value>
type any = t<unknown>

type field = {
  name: string,
  required: bool,
  schema: any,
  optionalNullable: bool,
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
  optionalNullable: false,
}

let makeField = (~name: string, ~required: bool, schema: t<'value>): field =>
  field({name, required}, schema)

let makeOptionalNullableField = (~name: string, schema: t<'value>): field => {
  name,
  required: false,
  schema: schema->toAny,
  optionalNullable: true,
}

let string: t<string> = S.string
let int: t<int> = S.int
let integer = int
let float: t<float> = S.float
let number = float
let bool: t<bool> = S.bool
let boolean = bool

let stringMapped = (~decode: string => result<'value, string>, ~encode: 'value => string): t<'value> =>
  string->S.to(S.castToAny(S.unknown), ~custom={
    decode: S.Sync(value =>
      switch decode(value) {
      | Ok(decoded) => decoded
      | Error(message) => JsError.throwWithMessage(message)
      }
    ),
    encode: S.Sync(encode),
  })

let array = (item: t<'value>): t<array<'value>> => S.array(item)

let nullableAsOption = (schema: t<'value>): t<option<'value>> => S.nullAsOption(schema)

let nullableAsNull = (schema: t<'value>): t<Null.t<'value>> => S.null(schema)

let optionalNullableAsNullable = (schema: t<'value>): t<Nullable.t<'value>> => S.nullable(schema)

let stripDiscriminator = (discriminator: string, objectJson: dict<JSON.t>): dict<JSON.t> => {
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
  payloadJson: dict<JSON.t>,
): dict<JSON.t> => {
  let output = Dict.make()

  Dict.forEachWithKey(payloadJson, (value, key) => Dict.set(output, key, value))
  Dict.set(output, discriminator, JSON.String(tag))
  output
}

let discriminatedUnion = (
  ~discriminator: string,
  cases: array<unionCase<'value>>,
): t<'value> =>
  S.dict(S.json)->S.to(S.castToAny(S.unknown), ~custom={
    decode: S.Sync(objectJson =>
      switch Dict.get(objectJson, discriminator) {
      | None => JsError.throwWithMessage("Missing discriminator: " ++ discriminator)
      | Some(tagJson) =>
        switch JSON.Decode.string(tagJson) {
        | None => JsError.throwWithMessage("Discriminator must be a string: " ++ discriminator)
        | Some(tag) =>
          switch Array.find(cases, case_ => case_.tag == tag) {
          | None => JsError.throwWithMessage("Unknown discriminator value: " ++ tag)
          | Some(case_) =>
            case_.wrap(S.parseOrThrow(stripDiscriminator(discriminator, objectJson), ~to=case_.schema))
          }
        }
      }
    ),
    encode: S.Sync(value =>
      switch Array.find(cases, case_ =>
        switch case_.unwrap(value) {
        | Some(_) => true
        | None => false
        }
      ) {
      | None => JsError.throwWithMessage("Unsupported discriminated union case")
      | Some(case_) =>
        switch case_.unwrap(value) {
        | None => JsError.throwWithMessage("Unsupported discriminated union case")
        | Some(payload) =>
          switch JSON.Decode.object(S.convertOrThrow(payload, ~from=case_.schema, ~to=S.json)) {
          | Some(payloadJson) => addDiscriminator(discriminator, case_.tag, payloadJson)
          | None => JsError.throwWithMessage("Discriminated union payload must encode to an object")
          }
        }
      }
    ),
  })

let object_ = (fields: array<field>): t<'value> =>
  S.object(s => {
    let output = Dict.make()

    Array.forEach(fields, field => {
      let value: unknown = if field.required {
        Obj.magic(s.field(field.name, field.schema))
      } else if field.optionalNullable {
        Obj.magic(s.field(field.name, optionalNullableAsNullable(field.schema)))
      } else {
        Obj.magic(s.fieldOr(field.name, S.option(field.schema), None))
      }

      Dict.set(output, field.name, Obj.magic(value))
    })

    Obj.magic(output)
  })->Obj.magic
