#!/usr/bin/env node

import {parseInput} from "../src/parseInput.mjs"

async function main() {
  const inputPath = process.argv[2]

  if (!inputPath) {
    console.error("Usage: openapi-rescript <spec-file>")
    process.exitCode = 1
    return
  }

  const document = await parseInput(inputPath)
  process.stdout.write(`${JSON.stringify(document, null, 2)}\n`)
}

main().catch((error) => {
  console.error(error instanceof Error ? error.message : String(error))
  process.exitCode = 1
})
