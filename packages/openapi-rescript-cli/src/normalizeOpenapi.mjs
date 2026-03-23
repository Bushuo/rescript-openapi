export function normalizeOpenapi(document) {
  if (!document || typeof document !== "object" || Array.isArray(document)) {
    throw new Error("OpenAPI document must be a plain object")
  }

  if (typeof document.openapi !== "string" || !/^3\.1\.\d+$/.test(document.openapi)) {
    throw new Error("Only OpenAPI 3.1.x documents are supported")
  }

  if (!isPlainObject(document.info) || typeof document.info.title !== "string" || typeof document.info.version !== "string") {
    throw new Error("OpenAPI document is missing required info metadata")
  }

  const hasDocumentSection =
    isPlainObject(document.paths) || isPlainObject(document.components) || isPlainObject(document.webhooks)

  if (!hasDocumentSection) {
    throw new Error("OpenAPI document must include at least one of paths, components, or webhooks")
  }

  return document
}

function isPlainObject(value) {
  return value !== null && typeof value === "object" && !Array.isArray(value)
}
