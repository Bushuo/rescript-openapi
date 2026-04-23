type runCoreResult = {
  ok: bool,
  diagnostic: CliArgs.diagnostic,
}

let main = async () => {
  let args = Node.process.argv->Array.slice(~start=2)

  switch CliArgs.parseArgs(args) {
  | Error(diagnostic) => {
      Node.process.stderr->Node.write(JSON.stringifyAny(diagnostic)->Option.getUnsafe)
      Node.process->Node.exit(1)
    }
  | Ok({inputPath, targetDir, options, configPath}) => {
      let s = await RunCore.runCore(inputPath, ~targetDir, ~options, ~configPath?)

      if !s.ok {
        Node.process.stderr->Node.write(JSON.stringifyAny(s.diagnostic)->Option.getUnsafe)
        Node.process->Node.exit(1)
      }
    }
  }
}
