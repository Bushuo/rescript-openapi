type diagnostic = {
  path: array<string>,
  message: string,
}

let make = (~path: array<string>, ~message: string): diagnostic => {
  path,
  message,
}

let root = (message: string): diagnostic => make(~path=[], ~message)
