type transportError = {
  operationName: string,
  message: string,
}

type requestEncodingError = {
  operationName: string,
  message: string,
}

type unexpectedStatusError = {
  operationName: string,
  status: int,
  body: string,
}

type responseDecodeError = {
  operationName: string,
  message: string,
  status: int,
  body: string,
}

type t = [
  | #transport(transportError)
  | #requestEncoding(requestEncodingError)
  | #unexpectedStatus(unexpectedStatusError)
  | #responseDecode(responseDecodeError)
]

type row<'error> = [> t] as 'error

let transport = (~operationName: string, ~message: string): row<'error> => {
  let error: transportError = {operationName, message}
  #transport(error)
}

let requestEncoding = (~operationName: string, ~message: string): row<'error> => {
  let error: requestEncodingError = {operationName, message}
  #requestEncoding(error)
}

let unexpectedStatus = (
  ~operationName: string,
  ~status: int,
  ~body: string,
): row<'error> => {
  let error: unexpectedStatusError = {operationName, status, body}
  #unexpectedStatus(error)
}

let responseDecode = (
  ~operationName: string,
  ~message: string,
  ~status: int,
  ~body: string,
): row<'error> => {
  let error: responseDecodeError = {operationName, message, status, body}
  #responseDecode(error)
}
