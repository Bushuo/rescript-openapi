type stderr

type process = {
  argv: array<string>,
  stderr: stderr,
}

@val external process: process = "process"

@send external cwd: (process, unit) => string = "cwd"

@send external exit: (process, int) => unit = "exit"

@send external write: (stderr, string) => unit = "write"

module Path = {
  @module("node:path") external dirname: string => string = "dirname"

  @module("node:path") @variadic external resolve: array<string> => string = "resolve"
}

module Fs = {
  @module("node:fs/promises")
  external readFilePromise: (string, ~encoding: string) => promise<string> = "readFile"
}
