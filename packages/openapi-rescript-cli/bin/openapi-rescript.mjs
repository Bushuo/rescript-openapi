#!/usr/bin/env node

import {runCore} from "../src/runCore.mjs"
import {parseCliArgs} from "../src/parseCliArgs.mjs"

function structuredDiagnostic(message) {
  return {
    path: [],
    message,
  }
}

async function main() {
  const args = process.argv.slice(2)
  const parsed = parseCliArgs(args)

  if (!parsed.ok) {
    process.stderr.write(`${JSON.stringify(parsed.diagnostic)}\n`)
    process.exitCode = 1
    return
  }

  const {enumMode, inputPath, targetDir} = parsed
  const result = await runCore(inputPath, targetDir ?? process.cwd(), {enumMode})

  if (result.ok) {
    return
  }

  process.stderr.write(`${JSON.stringify(result.diagnostic)}\n`)
  process.exitCode = 1
}

main().catch((error) => {
  process.stderr.write(`${JSON.stringify(structuredDiagnostic(error instanceof Error ? error.message : String(error)))}\n`)
  process.exitCode = 1
})
