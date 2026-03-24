import {mkdir, writeFile} from "node:fs/promises"
import {dirname, join} from "node:path"
import {parseInput} from "./parseInput.mjs"
import * as OpenapiGenerator from "openapi-rescript-core/lib/js/src/OpenapiGenerator.bs.js"

export async function runCore(entryPath, targetDir = process.cwd()) {
  try {
    const normalized = await parseInput(entryPath)
    const output = OpenapiGenerator.generate(normalized)

    if (!output.ok) {
      return {
        ok: false,
        diagnostic: output.error,
      }
    }

    await writeGeneratedFiles(output.files, targetDir)

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

async function writeGeneratedFiles(files, targetDir) {
  await mkdir(targetDir, {recursive: true})

  for (const file of files) {
    const outputPath = join(targetDir, file.path)
    await mkdir(dirname(outputPath), {recursive: true})
    await writeFile(outputPath, file.contents, "utf8")
  }
}
