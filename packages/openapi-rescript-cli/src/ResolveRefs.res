module YAML = {
  @module("yaml") external parse: 'a => 'b = "parse"
}

type url = {
  protocol: string,
}
@new external url: string => url = "URL"

module Document = {
  let parse = (contents, filePath): JSON.t => {
    // Replace the UTF-8 BOM before parsing
    let text = contents->String.replaceRegExp(/^\uFEFF/, "")

    if filePath->String.endsWith(".json") || /^[\s\r\n]*[{[]/->RegExp.test(text) {
      JSON.parseOrThrow(text)
    } else {
      YAML.parse(text)
    }
  }

  let read = async filePath => {
    let contents = await Node.Fs.readFilePromise(filePath, ~encoding="utf8")
    parse(contents, filePath)
  }
}

let isUnsupportedAbsoluteUri = ref => {
  try {
    let parsed = url(ref)
    parsed.protocol !== "file:"
  } catch {
  | _ => false
  }
}

let splitRefTuple = ref => {
  switch ref->String.split("#") {
  | [fileRef] => (fileRef, "")
  | [fileRef, fragment] => (fileRef, fragment)
  | _ => JsError.throwWithMessage(`Illegal ref: ${ref}`)
  }
}

let resolvePointer = (document, fragment): JSON.t => {
  // Return the whole document for empty or root fragments
  if String.isEmpty(fragment) || fragment == "/" {
    document
  } else {
    let pointer = fragment->String.startsWith("/") ? fragment : `/${fragment}`
    let tokens =
      pointer
      ->String.split("/")
      ->Array.slice(~start=1)
      ->Array.map(part => part->String.replaceRegExp(/~1/g, "/")->String.replaceRegExp(/~0/g, "~"))

    // Traverse the document by the tokens of the fragment to find the target node
    tokens->Array.reduce(document, (current, token) => {
      switch current {
      | JSON.Object(obj) =>
        switch obj->Dict.get(token) {
        | Some(current) => current
        | None => JsError.throwWithMessage(`Cannot resolve ref pointer: #${fragment}`)
        }
      | _ => JsError.throwWithMessage(`Cannot resolve ref pointer: #${fragment}`)
      }
    })
  }
}

let rec resolveReference = async (ref, currentFilePath, cache, ancestry): JSON.t => {
  if /^[a-zA-Z][a-zA-Z\d+.-]*:\/\//->RegExp.test(ref) || ref->String.startsWith("//") {
    JsError.throwWithMessage(`Remote refs are not supported: ${ref}`)
  } else if isUnsupportedAbsoluteUri(ref) {
    JsError.throwWithMessage(`Unsupported absolute ref: ${ref}`)
  }

  let (fileRef, fragment) = splitRefTuple(ref)
  let targetFilePath = String.isEmpty(fileRef)
    ? currentFilePath
    : Node.Path.resolve([Node.Path.dirname(currentFilePath), fileRef])
  let targetKey = `${targetFilePath}#${fragment}`

  if ancestry->Set.has(targetKey) {
    JsError.throwWithMessage(`Circular ref detected: ${targetKey}`)
  }
  switch cache->Map.get(targetKey) {
  | Some(hit) => hit
  | None => {
      let targetDocument = await Document.read(targetFilePath)
      let targetValue = String.isEmpty(fragment)
        ? targetDocument
        : resolvePointer(targetDocument, fragment)
      let resolvedNode = await resolveNode(
        targetValue,
        targetFilePath,
        cache,
        Set.fromArray([...Set.toArray(ancestry), targetKey]),
      )
      cache->Map.set(targetKey, resolvedNode)
      resolvedNode
    }
  }
}
and resolveNode = async (value: JSON.t, currentFilePath, cache, ancestry): JSON.t => {
  switch value {
  | Array(arr) =>
    Array(
      await Promise.all(
        arr->Array.map(async item => await resolveNode(item, currentFilePath, cache, ancestry)),
      ),
    )
  | Object(obj) =>
    switch obj->Dict.get("$ref") {
    | Some(String(ref)) => {
        // replace $ref with the resolved value
        obj->Dict.delete("$ref")
        let resolved = await resolveReference(ref, currentFilePath, cache, ancestry)

        switch resolved {
        | Object(resolved) => {
            let merged = [...Dict.toArray(resolved), ...Dict.toArray(obj)]->Dict.fromArray
            Object(merged)
          }
        | resolved if Dict.size(obj) > 0 => {
            let merged = [...Dict.toArray(obj), ("value", resolved)]->Dict.fromArray
            Object(merged)
          }
        | resolved => resolved
        }
      }
    | _ => {
        // No ref, so we resolve nodes deeper in the object
        let arr = await obj
        ->Dict.mapValues(async child => await resolveNode(child, currentFilePath, cache, ancestry))
        ->Dict.toArray
        // transpose the promise from (_, promise<_>) to promise<(_, _)>
        ->Array.map(async ((key, promise)) => (key, await promise))
        ->Promise.all

        Object(Dict.fromArray(arr))
      }
    }
  | x => x
  }
}

let resolveRefs = async entryPath => {
  let absolutePath = Node.Path.resolve([entryPath])
  let cache = Map.make()
  let document = await Document.read(absolutePath)
  let ancestry = Set.fromArray([absolutePath])

  await resolveNode(document, absolutePath, cache, ancestry)
}
