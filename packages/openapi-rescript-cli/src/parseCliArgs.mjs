function structuredDiagnostic(message) {
  return {
    path: [],
    message,
  }
}

const usageMessage = "Usage: openapi-rescript [--enum-mode=open|closed] <spec-file> [output-dir]"

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
      diagnostic: structuredDiagnostic(usageMessage),
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

  const extraArg = args[offset + 2]

  if (extraArg?.startsWith("--")) {
    return {
      ok: false,
      diagnostic: structuredDiagnostic(`Unknown option: ${extraArg}`),
    }
  }

  if (extraArg !== undefined) {
    return {
      ok: false,
      diagnostic: structuredDiagnostic(usageMessage),
    }
  }

  return {
    ok: true,
    enumMode,
    inputPath,
    targetDir,
  }
}
