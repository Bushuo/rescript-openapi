type dependencies = {
  parseInput?: string => promise<JSON.t>,
  loadGenerator?: unit => promise<OpenapiGenerator.generator>,
  syncGeneratedFiles?: (string, array<OpenapiGenerator.file>) => promise<unit>,
}

type output = {
  ok: bool,
  diagnostic?: OpenapiGenerator.diagnostic,
  outputFiles?: array<string>,
}

let readManifest = async manifestPath => {
  try {
    let contents = await Node.Fs.readFilePromise(manifestPath, ~encoding="utf8")
    let parsed = JSON.parseOrThrow(contents)

    switch parsed {
    | Array(arr) => arr->Array.filter(json => typeof(json) == #string)->Array.map(String.make)
    | _ => []
    }
  } catch {
  | _ => []
  }
}

let writeGeneratedFiles = async (files: array<OpenapiGenerator.file>, targetDir) => {
  await Node.Fs.mkdirPromise(targetDir, {recursive: true})

  let _ = await files
  ->Array.map(async file => {
    let path = Node.Path.join([targetDir, file.path])
    await Node.Fs.mkdirPromise(Node.Path.dirname(path), {recursive: true})
    await Node.Fs.writeFilePromise(path, file.contents, ~encoding="utf8")
  })
  ->Promise.all
}

let isSafeGeneratedPath = (targetDir, generatedPath) => {
  if String.isEmpty(generatedPath) {
    false
  } else {
    let resolvedPath = Node.Path.resolve([targetDir, generatedPath])
    let relativePath = Node.Path.relative([targetDir, resolvedPath])

    if String.isEmpty(relativePath) {
      false
    } else {
      !(relativePath->String.startsWith("..")) && !Node.Path.isAbsolute(relativePath)
    }
  }
}

let removeStaleFiles = async (targetDir, previousFiles, currentPaths) => {
  let currentSet = Set.fromArray(currentPaths)

  let _ = await previousFiles
  ->Array.map(async stalePath => {
    if !(currentSet->Set.has(stalePath)) && isSafeGeneratedPath(targetDir, stalePath) {
      let resolvedPath = Node.Path.resolve([targetDir, stalePath])
      await Node.Fs.rmPromise(resolvedPath, {force: true, recursive: true})
    }
  })
  ->Promise.all
}

let writeManifest = async (manifestPath, currentPaths) => {
  let content = JSON.stringifyAny(currentPaths, ~space=2)->Option.getUnsafe
  await Node.Fs.writeFilePromise(manifestPath, content, ~encoding="utf8")
}

let manifestName = ".openapi-rescript-generated.json"

let syncGeneratedFiles = async (targetDir, files) => {
  let manifestPath = Node.Path.join([targetDir, manifestName])
  let previousFiles = await readManifest(manifestPath)
  let currentPaths = files->Array.map((file: OpenapiGenerator.file) => file.path)

  await writeGeneratedFiles(files, targetDir)
  await removeStaleFiles(targetDir, previousFiles, currentPaths)
  await writeManifest(manifestPath, currentPaths)
}

let runCore = async (
  entryPath,
  ~targetDir=Node.process->Node.cwd(),
  ~options=OpenapiGenerator.defaultOptions,
  ~dependencies={}: dependencies,
) => {
  let parseInput = dependencies.parseInput->Option.getOr(ParseInput.parseInput)
  let loadGenerator =
    dependencies.loadGenerator->Option.getOr(async () => OpenapiGenerator.generate)
  let syncGeneratedFiles = dependencies.syncGeneratedFiles->Option.getOr(syncGeneratedFiles)

  try {
    let normalized = await parseInput(entryPath)
    let generator = await loadGenerator()
    let output = generator(normalized, ~options)

    if !output.ok {
      {
        ok: false,
        diagnostic: ?output.error,
      }
    } else {
      await syncGeneratedFiles(targetDir, output.files)

      {
        ok: true,
        outputFiles: output.files->Array.map(file => file.path),
      }
    }
  } catch {
  | JsExn(exn) => {
      ok: false,
      diagnostic: {
        path: [],
        message: exn->JsExn.message->Option.getOr(String.make(exn)),
      },
    }
  }
}
