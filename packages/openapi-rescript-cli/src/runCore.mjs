import {mkdir, readFile, rm, writeFile} from "node:fs/promises"
import {dirname, isAbsolute, join, relative, resolve} from "node:path"
import {parseInput} from "./parseInput.mjs"

const manifestName = ".openapi-rescript-generated.json"
const generatorImportPaths = [
  "../vendor/openapi-rescript-core/lib/js/src/OpenapiGenerator.bs.js",
  "../../openapi-rescript-core/lib/js/src/OpenapiGenerator.bs.js",
]

let generatorPromise

export async function runCore(entryPath, targetDir = process.cwd()) {
  try {
    const normalized = await parseInput(entryPath)
    const OpenapiGenerator = await loadGenerator()
    const output = OpenapiGenerator.generate(normalized)

    if (!output.ok) {
      return {
        ok: false,
        diagnostic: output.error,
      }
    }

    await syncGeneratedFiles(targetDir, output.files)

    return {
      ok: true,
      outputFiles: output.files.map((file) => file.path),
    }
  } catch (error) {
    return {
      ok: false,
      diagnostic: {
        path: [],
        message: error instanceof Error ? error.message : String(error),
      },
    }
  }
}

async function loadGenerator() {
  if (!generatorPromise) {
    generatorPromise = importGenerator()
  }

  return generatorPromise
}

async function importGenerator() {
  for (const specifier of generatorImportPaths) {
    try {
      return await import(specifier)
    } catch {
      // Try the next location.
    }
  }

  throw new Error("Unable to load the compiled OpenAPI generator")
}

async function syncGeneratedFiles(targetDir, files) {
  const manifestPath = join(targetDir, manifestName)
  const previousFiles = await readManifest(manifestPath)
  const currentPaths = files.map((file) => file.path)

  await writeGeneratedFiles(files, targetDir)
  await removeStaleFiles(targetDir, previousFiles, currentPaths)
  await writeManifest(manifestPath, currentPaths)
}

async function writeGeneratedFiles(files, targetDir) {
  await mkdir(targetDir, {recursive: true})

  for (const file of files) {
    const outputPath = join(targetDir, file.path)
    await mkdir(dirname(outputPath), {recursive: true})
    await writeFile(outputPath, file.contents, "utf8")
  }
}

async function readManifest(manifestPath) {
  try {
    const contents = await readFile(manifestPath, "utf8")
    const parsed = JSON.parse(contents)

    if (!Array.isArray(parsed)) {
      return []
    }

    return parsed.filter((value) => typeof value === "string")
  } catch {
    return []
  }
}

async function removeStaleFiles(targetDir, previousFiles, currentPaths) {
  const currentSet = new Set(currentPaths)

  for (const stalePath of previousFiles) {
    if (!currentSet.has(stalePath) && isSafeGeneratedPath(targetDir, stalePath)) {
      await rm(resolve(targetDir, stalePath), {force: true, recursive: true})
    }
  }
}

async function writeManifest(manifestPath, currentPaths) {
  await writeFile(manifestPath, `${JSON.stringify(currentPaths, null, 2)}\n`, "utf8")
}

function isSafeGeneratedPath(targetDir, generatedPath) {
  if (typeof generatedPath !== "string" || generatedPath.length === 0) {
    return false
  }

  const resolvedPath = resolve(targetDir, generatedPath)
  const relativePath = relative(targetDir, resolvedPath)

  if (relativePath === "") {
    return false
  }

  return !relativePath.startsWith("..") && !isAbsolute(relativePath)
}
