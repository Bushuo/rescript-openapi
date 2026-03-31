let isPlainObject = value =>
  switch Type.Classify.classify(value) {
  | Object(_) => true
  | _ => false
  }

external toObj: dict<JSON.t> => 'a = "%identity"
