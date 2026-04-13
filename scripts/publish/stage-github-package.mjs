import {cpSync, mkdirSync, readFileSync, readdirSync, rmSync, writeFileSync} from "node:fs"
import {join, resolve} from "node:path"

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

function rewriteManifest(manifest, owner, repository) {
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
      url: `git+https://github.com/${owner}/${repository}.git`,
    },
    dependencies: rewriteDependencyMap(owner, manifest.version, manifest.dependencies),
    devDependencies: rewriteDependencyMap(owner, manifest.version, manifest.devDependencies),
    peerDependencies: rewriteDependencyMap(owner, manifest.version, manifest.peerDependencies),
    optionalDependencies: rewriteDependencyMap(owner, manifest.version, manifest.optionalDependencies),
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
  const manifestPath = join(packageDir, "package.json")
  const stagedManifestPath = join(outputDir, "package.json")
  const manifest = readJson(manifestPath)

  stagePackage(packageDir, outputDir)
  writeJson(stagedManifestPath, rewriteManifest(manifest, owner, repository))
}

try {
  main(process.argv.slice(2))
} catch (error) {
  console.error(error instanceof Error ? error.message : String(error))
  process.exitCode = 1
}
