type t

@obj
external makeTransport: (
  ~kind: string=?,
  ~operationName: string,
  ~message: string,
  unit,
) => t = ""

@obj
external makeRequestEncoding: (
  ~kind: string=?,
  ~operationName: string,
  ~message: string,
  unit,
) => t = ""

@obj
external makeUnexpectedStatus: (
  ~kind: string=?,
  ~operationName: string,
  ~status: int,
  ~body: string=?,
  unit,
) => t = ""

@obj
external makeResponseDecode: (
  ~kind: string=?,
  ~operationName: string,
  ~message: string,
  ~status: int=?,
  ~body: string=?,
  unit,
) => t = ""

let transport = (~operationName: string, ~message: string): t =>
  makeTransport(~kind="transport", ~operationName, ~message, ())

let requestEncoding = (~operationName: string, ~message: string): t =>
  makeRequestEncoding(~kind="requestEncoding", ~operationName, ~message, ())

let unexpectedStatus = (~operationName: string, ~status: int, ~body as maybeBody=?): t =>
  makeUnexpectedStatus(~kind="unexpectedStatus", ~operationName, ~status, ~body=?maybeBody, ())

let responseDecode = (
  ~operationName: string,
  ~message: string,
  ~status as maybeStatus=?,
  ~body as maybeBody=?,
): t =>
  makeResponseDecode(
    ~kind="responseDecode",
    ~operationName,
    ~message,
    ~status=?maybeStatus,
    ~body=?maybeBody,
    (),
  )
