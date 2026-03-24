import {readFileSync, readdirSync} from "node:fs"
import {describe, expect, it} from "vitest"
import {generate} from "../lib/js/src/OpenapiGenerator.bs.js"

const normalizedPetstore = JSON.parse(
  readFileSync(new URL("./fixtures/petstore.normalized.json", import.meta.url), "utf8"),
)

const readGoldenFiles = fixtureName => {
  let fixtureDir = new URL(`./golden/${fixtureName}/`, import.meta.url)

  return readdirSync(fixtureDir)
    .sort()
    .map(fileName => ({
      path: fileName,
      contents: readFileSync(new URL(`./golden/${fixtureName}/${fileName}`, import.meta.url), "utf8"),
    }))
}

describe("codegen", () => {
  it("emits the expected ReScript modules for the petstore fixture", () => {
    let output = generate(normalizedPetstore)

    expect(output.ok).toBe(true)
    expect(output.files).toEqual(readGoldenFiles("petstore"))
  })
})
