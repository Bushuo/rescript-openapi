import {readFileSync} from "node:fs"
import {basename} from "node:path"

const EXPECTED_PACKAGE_NAMES = [
  "openapi-rescript-runtime",
  "openapi-rescript-core",
  "openapi-rescript-cli",
]

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

function validateManifestSet(manifests) {
  const counts = new Map()

  for (const {packageName} of manifests) {
    counts.set(packageName, (counts.get(packageName) ?? 0) + 1)
  }

  const missing = EXPECTED_PACKAGE_NAMES.filter((packageName) => (counts.get(packageName) ?? 0) === 0)
  const duplicate = EXPECTED_PACKAGE_NAMES.filter((packageName) => (counts.get(packageName) ?? 0) > 1)
  const unexpected = manifests
    .map(({packageName}) => packageName)
    .filter((packageName) => !EXPECTED_PACKAGE_NAMES.includes(packageName))

  if (missing.length > 0 || duplicate.length > 0 || unexpected.length > 0) {
    const details = ["Expected exactly these package manifests: openapi-rescript-runtime, openapi-rescript-core, openapi-rescript-cli."]

    if (missing.length > 0) {
      details.push(`missing: ${missing.join(", ")}`)
    }

    if (duplicate.length > 0) {
      details.push(`duplicate: ${duplicate.join(", ")}`)
    }

    if (unexpected.length > 0) {
      details.push(`unexpected: ${unexpected.join(", ")}`)
    }

    throw new Error(details.join(" "))
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
  validateManifestSet(manifests)
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
