import { describe, expect, it } from "vitest";
import { parseArgs } from "../src/CliArgs.bs.js";

function error(arg) {
  return {
    TAG: "Error",
    _0: arg,
  };
}

function ok(arg) {
  return {
    TAG: "Ok",
    _0: arg,
  };
}

describe("parseArgs", () => {
  it("accepts the supported CLI forms", () => {
    expect(parseArgs(["fixtures/spec.yaml"])).toEqual(
      ok({
        options: {
          enumMode: "open",
          scalars: [],
        },
        configPath: undefined,
        inputPath: "fixtures/spec.yaml",
        targetDir: process.cwd(),
      }),
    );

    expect(
      parseArgs(["--enum-mode=open", "fixtures/spec.yaml", "out"]),
    ).toEqual(
      ok({
        options: {
          enumMode: "open",
          scalars: [],
        },
        configPath: undefined,
        inputPath: "fixtures/spec.yaml",
        targetDir: "out",
      }),
    );

    expect(parseArgs(["--enum-mode=closed", "fixtures/spec.yaml"])).toEqual(
      ok({
        options: {
          enumMode: "closed",
          scalars: [],
        },
        configPath: undefined,
        inputPath: "fixtures/spec.yaml",
        targetDir: process.cwd(),
      }),
    );

    expect(parseArgs(["--config=openapi-rescript.json", "fixtures/spec.yaml"])).toEqual(
      ok({
        options: {
          enumMode: "open",
          scalars: [],
        },
        configPath: "openapi-rescript.json",
        inputPath: "fixtures/spec.yaml",
        targetDir: process.cwd(),
      }),
    );
  });

  it("rejects misplaced options", () => {
    expect(parseArgs(["fixtures/spec.yaml", "--enum-mode=closed"])).toEqual(
      error({
        path: [],
        message: "Unknown option: --enum-mode=closed",
      }),
    );

  });

  it("rejects unsupported optional nullable options", () => {
    expect(parseArgs(["--optional-nullable=collapse", "fixtures/spec.yaml"])).toEqual(
      error({
        path: [],
        message: "Unknown option: --optional-nullable=collapse",
      }),
    );
  });

  it("rejects unknown options in the third slot", () => {
    expect(parseArgs(["fixtures/spec.yaml", "out", "--bad"])).toEqual(
      error({
        path: [],
        message: "Unknown option: --bad",
      }),
    );
  });

  it("rejects invalid enum mode values with a structured diagnostic", () => {
    expect(parseArgs(["--enum-mode=banana", "fixtures/spec.yaml"])).toEqual(
      error({
        path: [],
        message: "Invalid enum mode: banana",
      }),
    );
  });

  it("includes supported flags in usage diagnostics", () => {
    expect(parseArgs([])).toEqual(
      error({
        path: [],
        message:
          "Usage: openapi-rescript [--enum-mode=open|closed] [--config=<path>] <spec-file> [output-dir]",
      }),
    );

    expect(parseArgs(["fixtures/spec.yaml", "out", "extra"])).toEqual(
      error({
        path: [],
        message:
          "Usage: openapi-rescript [--enum-mode=open|closed] [--config=<path>] <spec-file> [output-dir]",
      }),
    );
  });
});
