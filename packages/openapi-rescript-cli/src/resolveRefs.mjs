import {readFile} from "node:fs/promises"
import {dirname, resolve as resolvePath} from "node:path"
import YAML from "yaml"

const REF_REMOTE_PATTERN = /^[a-zA-Z][a-zA-Z\d+.-]*:\/\//

export async function resolveRefs(entryPath) {
  const absoluteEntryPath = resolvePath(entryPath)
  const cache = new Map()
  const document = await readDocument(absoluteEntryPath)
  return resolveNode(document, absoluteEntryPath, cache, new Set([absoluteEntryPath]))
}

async function resolveNode(value, currentFilePath, cache, ancestry) {
  if (Array.isArray(value)) {
    const result = []
    for (const item of value) {
      result.push(await resolveNode(item, currentFilePath, cache, ancestry))
    }
    return result
  }

  if (!isPlainObject(value)) {
    return value
  }

  if (typeof value.$ref === "string") {
    const resolved = await resolveReference(value.$ref, currentFilePath, cache, ancestry)
    const { $ref, ...siblings } = value
    const merged = isPlainObject(resolved) ? {...resolved, ...siblings} : Object.keys(siblings).length > 0 ? {...siblings, value: resolved} : resolved
    return resolveNode(merged, currentFilePath, cache, ancestry)
  }

  const result = {}
  for (const [key, child] of Object.entries(value)) {
    result[key] = await resolveNode(child, currentFilePath, cache, ancestry)
  }
  return result
}

async function resolveReference(ref, currentFilePath, cache, ancestry) {
  if (REF_REMOTE_PATTERN.test(ref) || ref.startsWith("//")) {
    throw new Error(`Remote refs are not supported: ${ref}`)
  }

  if (isUnsupportedAbsoluteUri(ref)) {
    throw new Error(`Unsupported absolute ref: ${ref}`)
  }

  const [fileRef, fragment = ""] = ref.split("#")
  const targetFilePath = fileRef ? resolvePath(dirname(currentFilePath), fileRef) : currentFilePath
  const targetKey = `${targetFilePath}#${fragment}`

  if (ancestry.has(targetKey)) {
    throw new Error(`Circular ref detected: ${targetKey}`)
  }

  if (!cache.has(targetKey)) {
    cache.set(
      targetKey,
      (async () => {
        const targetDocument = fileRef ? await readDocument(targetFilePath) : await readDocument(currentFilePath)
        const targetValue = fragment ? resolvePointer(targetDocument, fragment) : targetDocument
        return resolveNode(targetValue, targetFilePath, cache, new Set([...ancestry, targetKey]))
      })()
    )
  }

  return cache.get(targetKey)
}

async function readDocument(filePath) {
  const contents = await readFile(filePath, "utf8")
  return parseDocument(contents, filePath)
}

function parseDocument(contents, filePath) {
  // Replace the UTF-8 BOM before parsing
  const text = contents.replace(/^\uFEFF/, "")
  if (filePath.endsWith(".json") || /^[\s\r\n]*[{[]/.test(text)) {
    return JSON.parse(text)
  }

  return YAML.parse(text)
}

function resolvePointer(document, fragment) {
  // Return the whole document for empty or root fragments
  if (!fragment || fragment === "/") {
    return document
  }

  const pointer = fragment.startsWith("/") ? fragment : `/${fragment}`
  const tokens = pointer
    .split("/")
    .slice(1)
    .map((part) => part.replace(/~1/g, "/").replace(/~0/g, "~"))

  // Traverse the tokens of the fragment
  let current = document
  for (const token of tokens) {
    if (current == null || !(token in current)) {
      throw new Error(`Cannot resolve ref pointer: #${fragment}`)
    }

    current = current[token]
  }

  return current
}

function isPlainObject(value) {
  return value !== null && typeof value === "object" && !Array.isArray(value)
}

function isUnsupportedAbsoluteUri(ref) {
  try {
    const parsed = new URL(ref)
    return parsed.protocol !== "file:"
  } catch {
    return false
  }
}
