type runCoreResult = {
  ok: bool,
  diagnostic: CliArgs.diagnostic,
}
@module("../src/runCore.mjs")
external runCore: (string, string, CliArgs.Flags.t) => promise<runCoreResult> = "runCore"

let main = async () => {
  let args = Node.process.argv->Array.slice(~start=2)

  switch CliArgs.parseArgs(args) {
  | Error(diagnostic) => {
      Node.process.stderr->Node.write(JSON.stringifyAny(diagnostic)->Option.getUnsafe)
      Node.process->Node.exit(1)
    }
  | Ok({inputPath, targetDir, flags}) => {
      let s = await runCore(inputPath, targetDir, flags)

      if !s.ok {
        Node.process.stderr->Node.write(JSON.stringifyAny(s.diagnostic)->Option.getUnsafe)
        Node.process->Node.exit(1)
      }
    }
  }
}
