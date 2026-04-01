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

  @module("node:path") @variadic external join: array<string> => string = "join"

  @module("node:path") @variadic external relative: array<string> => string = "relative"

  @module("node:path") external isAbsolute: string => bool = "isAbsolute"
}

module Fs = {
  @module("node:fs/promises")
  external readFilePromise: (string, ~encoding: string) => promise<string> = "readFile"

  @module("node:fs/promises")
  external writeFilePromise: (string, string, ~encoding: string) => promise<unit> = "writeFile"

  type rmOpts = {
    force?: bool,
    recursive?: bool,
  }

  @module("node:fs/promises")
  external rmPromise: (string, rmOpts) => promise<unit> = "rm"

  type mkdirOpts = {
    recursive?: bool,
  }

  @module("node:fs/promises")
  external mkdirPromise: (string, mkdirOpts) => promise<unit> = "mkdir"
}
