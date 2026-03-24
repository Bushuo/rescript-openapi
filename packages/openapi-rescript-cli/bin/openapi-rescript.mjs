#!/usr/bin/env node

import {runCore} from "../src/runCore.mjs"

async function main() {
  const inputPath = process.argv[2]
  const targetDir = process.argv[3] ?? process.cwd()

  if (!inputPath) {
    console.error("Usage: openapi-rescript <spec-file> [output-dir]")
    process.exitCode = 1
    return
  }

  const result = await runCore(inputPath, targetDir)

  if (result.ok) {
    return
  }

  process.stderr.write(`${JSON.stringify(result.diagnostic)}\n`)
  process.exitCode = 1
}

main().catch((error) => {
  process.stderr.write(`${JSON.stringify({path: [], message: error instanceof Error ? error.message : String(error)})}\n`)
  process.exitCode = 1
})
