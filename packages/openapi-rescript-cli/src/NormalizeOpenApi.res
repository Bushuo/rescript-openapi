let normalizeOpenApi = (document: JSON.t) => {
  let document = switch document {
  | JSON.Object(x) => x
  | _ => JsError.make("OpenAPI document must be a plain object")->JsError.throw
  }

  let document = Utils.toObj(document)
  let openapi = document["openapi"]
  let info = document["info"]
  let paths = document["paths"]

  if typeof(openapi) != #string || !(/^3\.1\.\d+$/->RegExp.test(openapi)) {
    JsError.make("Only OpenAPI 3.1.x documents are supported")->JsError.throw
  }

  if (
    !Utils.isPlainObject(info) ||
    typeof(info["title"]) != #string ||
    typeof(info["version"]) != #string
  ) {
    JsError.make("OpenAPI document is missing required info metadata")->JsError.throw
  }

  if !Utils.isPlainObject(paths) {
    JsError.make("OpenAPI document must include a paths object")->JsError.throw
  }

  document
}
