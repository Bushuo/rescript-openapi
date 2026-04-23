let usageMessage = "Usage: openapi-rescript [--enum-mode=open|closed] [--config=<path>] <spec-file> [output-dir]"

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
  type state = {
    options: t,
    configPath: option<string>,
  }

  let enumModePattern = "--enum-mode="
  let configPattern = "--config="

  let parseEnumModeArg = arg => {
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

  let parseOption = (state: state, arg: string): result<state, diagnostic> =>
    if arg->String.startsWith(enumModePattern) {
      let? Ok(enumMode) = parseEnumModeArg(arg)
      Ok({
        ...state,
        options: {...state.options, enumMode},
      })
    } else if arg->String.startsWith(configPattern) {
      let configPath = arg->String.slice(~start=String.length(configPattern))

      if String.isEmpty(configPath) {
        Error(structuredDiagnostic("Invalid config path"))
      } else {
        Ok({...state, configPath: Some(configPath)})
      }
    } else {
      Error(structuredDiagnostic(`Unknown option: ${arg}`))
    }

  let rec parseLeadingOptions = (args: array<string>, state: state): result<
    (array<string>, state),
    diagnostic,
  > =>
    switch args->Array.get(0) {
    | Some(arg) if arg->String.startsWith("--") =>
      let newArgs = args->Array.slice(~start=1)
      let? Ok(state) = parseOption(state, arg)
      parseLeadingOptions(newArgs, state)
    | _ => Ok(args, state)
    }

  let parse = (args: array<string>): result<(array<string>, state), diagnostic> =>
    parseLeadingOptions(
      args,
      {
        options: OpenapiGenerator.defaultOptions,
        configPath: None,
      },
    )
}

type cliArgs = {
  options: Options.t,
  configPath: option<string>,
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
    let? Ok((args, state)) = Options.parse(args)

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
        options: state.options,
        configPath: state.configPath,
        inputPath,
        targetDir,
      })
    }
  }
}
