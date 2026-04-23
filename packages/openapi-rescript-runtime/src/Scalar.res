module MakeString = (
  Codec: {
    type t
    let decode: string => result<t, string>
    let encode: t => string
  },
) => {
  type t = Codec.t

  let schema: Schema.t<t> = Schema.stringMapped(~decode=Codec.decode, ~encode=Codec.encode)
}
