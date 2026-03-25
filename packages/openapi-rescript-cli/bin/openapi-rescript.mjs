#!/usr/bin/env node

import {runCore} from "../src/runCore.mjs"

function structuredDiagnostic(message) {
  return {
    path: [],
    message,
  }
}

function parseEnumMode(arg) {
  if (arg === undefined) {
    return {value: "open", consumed: 0}
  }

  if (!arg.startsWith("--enum-mode=")) {
    return {value: "open", consumed: 0}
  }

  const value = arg.slice("--enum-mode=".length)

  if (value === "open" || value === "closed") {
    return {value, consumed: 1}
  }

  throw new Error(`Invalid enum mode: ${value}`)
}

async function main() {
  const args = process.argv.slice(2)
  const {value: enumMode, consumed} = parseEnumMode(args[0])
  const inputPath = args[consumed]
  const targetDir = args[consumed + 1] ?? process.cwd()

  if (!inputPath) {
    console.error("Usage: openapi-rescript <spec-file> [output-dir]")
    process.exitCode = 1
    return
  }

  const result = await runCore(inputPath, targetDir, {enumMode})

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
