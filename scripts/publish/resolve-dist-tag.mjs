import {readFileSync} from "node:fs"

function readVersion(manifestPath) {
  const manifest = JSON.parse(readFileSync(manifestPath, "utf8"))

  if (typeof manifest.version !== "string" || manifest.version.length === 0) {
    throw new Error(`Missing version in ${manifestPath}`)
  }

  return manifest.version
}

function resolveDistTag(version) {
  const prereleaseIndex = version.indexOf("-")

  if (prereleaseIndex === -1) {
    return "latest"
  }

  const prerelease = version.slice(prereleaseIndex + 1)
  const [channel] = prerelease.split(".")

  if (!channel || /^\d+$/.test(channel)) {
    throw new Error(`Cannot derive npm dist-tag from prerelease version ${version}`)
  }

  return channel
}

function main(args) {
  if (args.length !== 1) {
    throw new Error("Usage: node resolve-dist-tag.mjs <package-manifest-path>")
  }

  process.stdout.write(`${resolveDistTag(readVersion(args[0]))}\n`)
}

try {
  main(process.argv.slice(2))
} catch (error) {
  console.error(error instanceof Error ? error.message : String(error))
  process.exitCode = 1
}
