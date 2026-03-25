module S = S

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

let array = (item: t<'value>): t<array<'value>> => S.array(item)

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
