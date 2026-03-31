let isPlainObject = value =>
  switch Type.Classify.classify(value) {
  | Object(_) => true
  | _ => false
  }

external toObj: Type.Classify.object => 'a = "%identity"
