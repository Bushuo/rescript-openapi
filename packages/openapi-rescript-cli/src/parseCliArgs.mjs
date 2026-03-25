function structuredDiagnostic(message) {
  return {
    path: [],
    message,
  }
}

function parseEnumModeArg(arg) {
  if (!arg.startsWith("--enum-mode=")) {
    return {
      ok: false,
      diagnostic: structuredDiagnostic(`Unknown option: ${arg}`),
    }
  }

  const value = arg.slice("--enum-mode=".length)

  if (value === "open" || value === "closed") {
    return {
      ok: true,
      value,
    }
  }

  return {
    ok: false,
    diagnostic: structuredDiagnostic(`Invalid enum mode: ${value}`),
  }
}

export function parseCliArgs(args) {
  let offset = 0
  let enumMode = "open"

  const firstArg = args[offset]

  if (firstArg?.startsWith("--")) {
    const parsedEnumMode = parseEnumModeArg(firstArg)

    if (!parsedEnumMode.ok) {
      return parsedEnumMode
    }

    enumMode = parsedEnumMode.value
    offset += 1
  }

  const inputPath = args[offset]

  if (!inputPath) {
    return {
      ok: false,
      diagnostic: structuredDiagnostic("Usage: openapi-rescript <spec-file> [output-dir]"),
    }
  }

  if (inputPath.startsWith("--")) {
    return {
      ok: false,
      diagnostic: structuredDiagnostic(`Unknown option: ${inputPath}`),
    }
  }

  const targetDir = args[offset + 1]

  if (targetDir?.startsWith("--")) {
    return {
      ok: false,
      diagnostic: structuredDiagnostic(`Unknown option: ${targetDir}`),
    }
  }

  if (args[offset + 2] !== undefined) {
    return {
      ok: false,
      diagnostic: structuredDiagnostic("Usage: openapi-rescript <spec-file> [output-dir]"),
    }
  }

  return {
    ok: true,
    enumMode,
    inputPath,
    targetDir,
  }
}
