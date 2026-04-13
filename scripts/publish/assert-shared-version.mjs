import {readFileSync} from "node:fs"
import {basename} from "node:path"

function readManifest(manifestPath) {
  const manifest = JSON.parse(readFileSync(manifestPath, "utf8"))

  if (typeof manifest.version !== "string" || manifest.version.length === 0) {
    throw new Error(`Missing version in ${manifestPath}`)
  }

  return {
    packageName: manifest.name ?? basename(manifestPath),
    version: manifest.version,
  }
}

function main(args) {
  if (args.length === 0) {
    throw new Error("Expected at least one package manifest path")
  }

  const manifests = args.map((manifestPath) => ({
    manifestPath,
    ...readManifest(manifestPath),
  }))
  const [{packageName: expectedPackageName, version: expectedVersion}] = manifests

  for (const {manifestPath, packageName, version} of manifests.slice(1)) {
    if (version !== expectedVersion) {
      throw new Error(
        [
          "Package versions must match.",
          `Expected ${expectedPackageName} to set the shared version ${expectedVersion}.`,
          `Found ${packageName} at ${manifestPath} with version ${version}.`,
        ].join(" ")
      )
    }
  }
}

try {
  main(process.argv.slice(2))
} catch (error) {
  console.error(error instanceof Error ? error.message : String(error))
  process.exitCode = 1
}
