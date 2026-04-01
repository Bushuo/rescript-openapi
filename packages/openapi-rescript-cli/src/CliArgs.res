let usageMessage = "Usage: openapi-rescript [--enum-mode=open|closed] <spec-file> [output-dir]"

type diagnostic = {
  path: array<string>,
  message: string,
}

let structuredDiagnostic = message => {
  path: [],
  message,
}

module Options = {
  type t = OpenapiGenerator.options

  let parseEnumModeArg = arg => {
    let enumModePattern = "--enum-mode="
    if !(arg->String.startsWith(enumModePattern)) {
      Error(structuredDiagnostic(`Unknown option: ${arg}`))
    } else {
      let value = arg->String.slice(~start=String.length(enumModePattern))

      switch value {
      | "open" => Ok((Open: OpenapiGenerator.enumMode))
      | "closed" => Ok(Closed)
      | _ => Error(structuredDiagnostic(`Invalid enum mode: ${value}`))
      }
    }
  }

  let parse = (args: array<string>): result<(array<string>, t), diagnostic> => {
    let arg = args->Array.getUnsafe(0)

    if arg->String.startsWith("--") {
      let newArgs = args->Array.slice(~start=1)
      let? Ok(parsedEnumMode) = parseEnumModeArg(arg)

      Ok(
        newArgs,
        {
          enumMode: parsedEnumMode,
        },
      )
    } else {
      Ok(args, OpenapiGenerator.defaultOptions)
    }
  }
}

type cliArgs = {
  options: Options.t,
  inputPath: string,
  targetDir: string,
}

let parseInputPath = (args: array<string>): result<(array<string>, string), diagnostic> => {
  // We need at least the input path here
  let? Ok(inputPath) =
    args->Array.get(0)->Option.mapOr(Error(structuredDiagnostic(usageMessage)), x => Ok(x))

  if inputPath->String.startsWith("--") {
    Error(structuredDiagnostic(`Unknown option: ${inputPath}`))
  } else {
    let newArgs = args->Array.slice(~start=1)
    Ok(newArgs, inputPath)
  }
}

let parseTargetDir = (args: array<string>): result<(array<string>, string), diagnostic> => {
  switch args->Array.get(0) {
  | Some(targetDir) =>
    if targetDir->String.startsWith("--") {
      Error(structuredDiagnostic(`Unknown option: ${targetDir}`))
    } else {
      let newArgs = args->Array.slice(~start=1)
      Ok(newArgs, targetDir)
    }
  | None => Ok(args, Node.process->Node.cwd())
  }
}

let parseArgs = (args: array<string>): result<cliArgs, diagnostic> => {
  if Array.length(args) == 0 {
    Error(structuredDiagnostic(usageMessage))
  } else {
    let? Ok((args, options)) = Options.parse(args)

    let? Ok(args, inputPath) = parseInputPath(args)

    let? Ok(args, targetDir) = parseTargetDir(args)

    if Array.length(args) != 0 {
      let arg = args->Array.getUnsafe(0)
      if arg->String.startsWith("--") {
        Error(structuredDiagnostic(`Unknown option: ${arg}`))
      } else {
        Error(structuredDiagnostic(usageMessage))
      }
    } else {
      Ok({
        options,
        inputPath,
        targetDir,
      })
    }
  }
}
