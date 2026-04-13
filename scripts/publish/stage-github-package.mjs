import {cpSync, mkdirSync, readFileSync, readdirSync, rmSync, writeFileSync} from "node:fs"
import {extname, isAbsolute, join, relative, resolve, sep} from "node:path"

const LOCAL_PACKAGE_NAMES = new Set([
  "openapi-rescript-runtime",
  "openapi-rescript-core",
  "openapi-rescript-cli",
])

function readJson(path) {
  return JSON.parse(readFileSync(path, "utf8"))
}

function writeJson(path, value) {
  writeFileSync(path, `${JSON.stringify(value, null, 2)}\n`)
}

function toPublishedName(owner, packageName) {
  return `@${owner}/${packageName}`
}

function toRepositorySlug(owner, repository) {
  return repository.includes("/") ? repository : `${owner}/${repository}`
}

function rewriteDependencyMap(owner, packageVersion, dependencies) {
  if (!dependencies || typeof dependencies !== "object" || Array.isArray(dependencies)) {
    return dependencies
  }

  return Object.fromEntries(
    Object.entries(dependencies).map(([dependencyName, version]) => [
      LOCAL_PACKAGE_NAMES.has(dependencyName) ? toPublishedName(owner, dependencyName) : dependencyName,
      LOCAL_PACKAGE_NAMES.has(dependencyName) ? packageVersion : version,
    ])
  )
}

function rewriteScripts(scripts) {
  if (!scripts || typeof scripts !== "object" || Array.isArray(scripts)) {
    return scripts
  }

  return Object.fromEntries(
    Object.entries(scripts).filter(([scriptName]) => scriptName !== "prepack" && scriptName !== "postpack")
  )
}

function rewriteManifest(manifest, owner, repository) {
  const repositorySlug = toRepositorySlug(owner, repository)

  return {
    ...manifest,
    name: toPublishedName(owner, manifest.name),
    private: false,
    publishConfig: {
      ...manifest.publishConfig,
      registry: "https://npm.pkg.github.com",
    },
    repository: {
      type: "git",
      url: `git+https://github.com/${repositorySlug}.git`,
    },
    scripts: rewriteScripts(manifest.scripts),
    dependencies: rewriteDependencyMap(owner, manifest.version, manifest.dependencies),
    devDependencies: rewriteDependencyMap(owner, manifest.version, manifest.devDependencies),
    peerDependencies: rewriteDependencyMap(owner, manifest.version, manifest.peerDependencies),
    optionalDependencies: rewriteDependencyMap(owner, manifest.version, manifest.optionalDependencies),
  }
}

function rewriteJsImportsInDirectory(owner, directoryPath) {
  for (const entry of readdirSync(directoryPath, {withFileTypes: true})) {
    const entryPath = join(directoryPath, entry.name)

    if (entry.isDirectory()) {
      rewriteJsImportsInDirectory(owner, entryPath)
      continue
    }

    if (!entry.isFile() || ![".js", ".cjs", ".mjs"].includes(extname(entry.name))) {
      continue
    }

    let fileContents = readFileSync(entryPath, "utf8")

    for (const packageName of LOCAL_PACKAGE_NAMES) {
      fileContents = fileContents.replaceAll(packageName, toPublishedName(owner, packageName))
    }

    writeFileSync(entryPath, fileContents)
  }
}

function isNestedPath(parentPath, childPath) {
  const relativePath = relative(parentPath, childPath)

  return (
    relativePath !== "" &&
    relativePath !== "." &&
    relativePath !== ".." &&
    !relativePath.startsWith(`..${sep}`) &&
    !isAbsolute(relativePath)
  )
}

function assertPathsDoNotOverlap(packageDir, outputDir) {
  if (packageDir === outputDir || isNestedPath(packageDir, outputDir) || isNestedPath(outputDir, packageDir)) {
    throw new Error(`Output directory must not overlap source directory: ${outputDir}`)
  }
}

function stagePackage(packageDir, outputDir) {
  rmSync(outputDir, {recursive: true, force: true})
  mkdirSync(outputDir, {recursive: true})

  for (const entry of readdirSync(packageDir)) {
    cpSync(join(packageDir, entry), join(outputDir, entry), {recursive: true})
  }
}

function main(args) {
  if (args.length !== 4) {
    throw new Error("Usage: node stage-github-package.mjs <package-dir> <owner> <repository> <output-dir>")
  }

  const [packageDirArg, owner, repository, outputDirArg] = args
  const packageDir = resolve(packageDirArg)
  const outputDir = resolve(outputDirArg)
  assertPathsDoNotOverlap(packageDir, outputDir)
  const manifestPath = join(packageDir, "package.json")
  const stagedManifestPath = join(outputDir, "package.json")
  const manifest = readJson(manifestPath)

  stagePackage(packageDir, outputDir)
  writeJson(stagedManifestPath, rewriteManifest(manifest, owner, repository))
  rewriteJsImportsInDirectory(owner, outputDir)
}

try {
  main(process.argv.slice(2))
} catch (error) {
  console.error(error instanceof Error ? error.message : String(error))
  process.exitCode = 1
}
