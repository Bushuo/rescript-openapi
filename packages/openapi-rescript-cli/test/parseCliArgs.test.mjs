import {describe, expect, it} from "vitest"
import {parseCliArgs} from "../src/parseCliArgs.mjs"

describe("parseCliArgs", () => {
  it("accepts the supported CLI forms", () => {
    expect(parseCliArgs(["fixtures/spec.yaml"])).toEqual({
      ok: true,
      enumMode: "open",
      inputPath: "fixtures/spec.yaml",
      targetDir: undefined,
    })

    expect(parseCliArgs(["--enum-mode=open", "fixtures/spec.yaml", "out"])).toEqual({
      ok: true,
      enumMode: "open",
      inputPath: "fixtures/spec.yaml",
      targetDir: "out",
    })

    expect(parseCliArgs(["--enum-mode=closed", "fixtures/spec.yaml"])).toEqual({
      ok: true,
      enumMode: "closed",
      inputPath: "fixtures/spec.yaml",
      targetDir: undefined,
    })
  })

  it("rejects misplaced enum mode options", () => {
    expect(parseCliArgs(["fixtures/spec.yaml", "--enum-mode=closed"])).toEqual({
      ok: false,
      diagnostic: {
        path: [],
        message: "Unknown option: --enum-mode=closed",
      },
    })
  })

  it("rejects invalid enum mode values with a structured diagnostic", () => {
    expect(parseCliArgs(["--enum-mode=banana", "fixtures/spec.yaml"])).toEqual({
      ok: false,
      diagnostic: {
        path: [],
        message: "Invalid enum mode: banana",
      },
    })
  })
})
