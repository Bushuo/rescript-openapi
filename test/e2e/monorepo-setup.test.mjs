import { existsSync, readFileSync } from "node:fs";
import { resolve } from "node:path";
import { describe, expect, it } from "vitest";

const readJson = (path) => JSON.parse(readFileSync(resolve(path), "utf8"));

describe("ReScript monorepo setup", () => {
  it("defines a root ReScript project that owns the shared output settings", () => {
    expect(existsSync(resolve("rescript.json"))).toBe(true);

    const rootConfig = readJson("rescript.json");

    expect(rootConfig).toMatchObject({
      dependencies: [
        "openapi-rescript-core",
        "openapi-rescript-runtime",
        "openapi-rescript-cli",
      ],
    });
  });

  it("registers the cli package as a ReScript project member", () => {
    expect(
      existsSync(resolve("packages/openapi-rescript-cli/rescript.json")),
    ).toBe(true);
  });

  it("builds compiled core and runtime entrypoints in source", () => {
    expect(
      existsSync(
        resolve("packages/openapi-rescript-core/src/OpenapiGenerator.bs.js"),
      ),
    ).toBe(true);
    expect(
      existsSync(resolve("packages/openapi-rescript-runtime/src/Client.bs.js")),
    ).toBe(true);
  });
});
