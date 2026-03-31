let normalizeOpenApi = (document: JSON.t) => {
  let document = switch document {
  | JSON.Object(x) => x
  | _ => JsError.throwWithMessage("OpenAPI document must be a plain object")
  }

  let document = Utils.toObj(document)
  let openapi = document["openapi"]
  let info = document["info"]
  let paths = document["paths"]

  if typeof(openapi) != #string || !(/^3\.1\.\d+$/->RegExp.test(openapi)) {
    JsError.throwWithMessage("Only OpenAPI 3.1.x documents are supported")
  }

  if (
    !Utils.isPlainObject(info) ||
    typeof(info["title"]) != #string ||
    typeof(info["version"]) != #string
  ) {
    JsError.throwWithMessage("OpenAPI document is missing required info metadata")
  }

  if !Utils.isPlainObject(paths) {
    JsError.throwWithMessage("OpenAPI document must include a paths object")
  }

  document
}
