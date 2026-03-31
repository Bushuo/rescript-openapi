import { normalizeOpenApi } from "./NormalizeOpenApi.bs.js";
import { resolveRefs } from "./ResolveRefs.bs.js";

export async function parseInput(entryPath) {
  const resolved = await resolveRefs(entryPath);
  return normalizeOpenApi(resolved);
}
