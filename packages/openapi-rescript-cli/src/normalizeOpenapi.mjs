export function normalizeOpenapi(document) {
  if (!document || typeof document !== "object" || Array.isArray(document)) {
    throw new Error("OpenAPI document must be a plain object")
  }

  if (document.openapi !== "3.1.0") {
    throw new Error("Only OpenAPI 3.1.0 documents are supported")
  }

  return document
}
