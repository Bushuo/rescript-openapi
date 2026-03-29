type stderr

type process = {
  argv: array<string>,
  stderr: stderr,
}

@val external process: process = "process"

@send external cwd: (process, unit) => string = "cwd"

@send external exit: (process, int) => unit = "exit"

@send external write: (stderr, string) => unit = "write"
