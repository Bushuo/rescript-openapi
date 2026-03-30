external toObj: Type.Classify.object => 'a = "%identity"

let isPlainObject = value =>
  switch Type.Classify.classify(value) {
  | Object(_) => true
  | _ => false
  }

let normalizeOpenApi = (document: unknown) => {
  let document = switch Type.Classify.classify(document) {
  | Object(x) if !Array.isArray(x) => x
  | _ => JsError.make("OpenAPI document must be a plain object")->JsError.throw
  }

  let document = toObj(document)
  let openapi = document["openapi"]
  let info = document["info"]
  let paths = document["paths"]

  if typeof(openapi) != #string || !(/^3\.1\.\d+$/->RegExp.test(openapi)) {
    JsError.make("Only OpenAPI 3.1.x documents are supported")->JsError.throw
  }

  if (
    !isPlainObject(info) || typeof(info["title"]) != #string || typeof(info["version"]) != #string
  ) {
    JsError.make("OpenAPI document is missing required info metadata")->JsError.throw
  }

  if !isPlainObject(paths) {
    JsError.make("OpenAPI document must include a paths object")->JsError.throw
  }

  document
}
