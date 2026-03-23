import {normalizeOpenapi} from "./normalizeOpenapi.mjs"
import {resolveRefs} from "./resolveRefs.mjs"

export async function parseInput(entryPath) {
  const resolved = await resolveRefs(entryPath)
  return normalizeOpenapi(resolved)
}
