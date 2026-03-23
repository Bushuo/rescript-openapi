import {readFile} from "node:fs/promises"
import {dirname, isAbsolute, resolve as resolvePath} from "node:path"

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
  const text = contents.replace(/^\uFEFF/, "")
  if (filePath.endsWith(".json") || /^[\s\r\n]*[{[]/.test(text)) {
    return JSON.parse(text)
  }

  return parseYaml(text)
}

function parseYaml(source) {
  const lines = source.replace(/\r\n?/g, "\n").split("\n")
  const {value} = parseBlock(lines, 0, 0)
  return value
}

function parseBlock(lines, startIndex, indent) {
  let index = startIndex
  let container = null

  while (index < lines.length) {
    const rawLine = lines[index]
    if (!rawLine || !rawLine.trim() || rawLine.trimStart().startsWith("#")) {
      index += 1
      continue
    }

    const currentIndent = countIndent(rawLine)
    if (currentIndent < indent) {
      break
    }

    if (currentIndent > indent) {
      throw new Error(`Unexpected indentation at line ${index + 1}`)
    }

    const line = rawLine.slice(indent)
    if (line.startsWith("- ")) {
      if (container === null) {
        container = []
      } else if (!Array.isArray(container)) {
        throw new Error(`Mixed YAML mapping and sequence at line ${index + 1}`)
      }

      const itemText = line.slice(2)
      if (!itemText.trim()) {
        const child = parseChild(lines, index + 1, indent + 2)
        container.push(child.value)
        index = child.index
        continue
      }

      container.push(parseScalar(itemText))
      index += 1
      continue
    }

    if (container === null) {
      container = {}
    } else if (Array.isArray(container)) {
      throw new Error(`Mixed YAML sequence and mapping at line ${index + 1}`)
    }

    const colonIndex = line.indexOf(":")
    if (colonIndex === -1) {
      throw new Error(`Invalid YAML line at ${index + 1}`)
    }

    const key = parseKey(line.slice(0, colonIndex).trim())
    const remainder = line.slice(colonIndex + 1).trim()
    if (!remainder) {
      const child = parseChild(lines, index + 1, indent + 2)
      container[key] = child.value
      index = child.index
      continue
    }

    container[key] = parseScalar(remainder)
    index += 1
  }

  if (container === null) {
    container = {}
  }

  return {value: container, index}
}

function parseChild(lines, startIndex, indent) {
  let index = startIndex
  while (index < lines.length) {
    const line = lines[index]
    if (!line || !line.trim() || line.trimStart().startsWith("#")) {
      index += 1
      continue
    }

    if (countIndent(line) < indent) {
      return {value: {}, index}
    }

    return parseBlock(lines, index, indent)
  }

  return {value: {}, index}
}

function parseScalar(value) {
  if (value === "null" || value === "~") {
    return null
  }

  if (value === "true") {
    return true
  }

  if (value === "false") {
    return false
  }

  if (/^-?\d+(\.\d+)?$/.test(value)) {
    return Number(value)
  }

  if (
    (value.startsWith('"') && value.endsWith('"')) ||
    (value.startsWith("'") && value.endsWith("'"))
  ) {
    return value.slice(1, -1).replace(/\\"/g, '"').replace(/\\'/g, "'")
  }

  return value
}

function parseKey(value) {
  if (
    (value.startsWith('"') && value.endsWith('"')) ||
    (value.startsWith("'") && value.endsWith("'"))
  ) {
    return value.slice(1, -1)
  }

  return value
}

function resolvePointer(document, fragment) {
  if (!fragment || fragment === "/") {
    return document
  }

  const pointer = fragment.startsWith("/") ? fragment : `/${fragment}`
  const tokens = pointer
    .split("/")
    .slice(1)
    .map((part) => part.replace(/~1/g, "/").replace(/~0/g, "~"))

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

function countIndent(line) {
  let indent = 0
  while (indent < line.length && line[indent] === " ") {
    indent += 1
  }
  return indent
}
