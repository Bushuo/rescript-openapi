import {describe, expect, it} from "vitest"
import {spawnSync} from "node:child_process"
import {resolve} from "node:path"

describe("rescript build", () => {
  it("emits no compiler warnings", () => {
    const result = spawnSync("pnpm", ["exec", "rescript", "build"], {
      cwd: resolve("."),
      encoding: "utf8",
    })

    const output = `${result.stdout ?? ""}${result.stderr ?? ""}`

    expect(result.status).toBe(0)
    expect(output).not.toContain("Warning number")
  })
})
