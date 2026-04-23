import { describe, expect, it, vi } from "vitest";
import { runCore } from "../src/RunCore.bs.js";

describe("runCore", () => {
  it("forwards generator options and loaded config to the generator", async () => {
    const normalized = { openapi: "3.1.0" };
    const generate = vi.fn(() => ({ ok: true, files: [] }));
    const loadGenerator = vi.fn(async () => generate);
    const parseInput = vi.fn(async () => normalized);
    const syncGeneratedFiles = vi.fn(async () => {});
    const loadConfigOptions = vi.fn(async (_path, options) => ({
      TAG: "Ok",
      _0: {
        ...options,
        scalars: [
          {
            key: "string:uuid",
            typeName: "Hybit.Id.t",
            moduleName: "ApiScalars.Uuid",
          },
        ],
      },
    }));

    await runCore(
      "spec.yaml",
      "out",
      { enumMode: "open", scalars: [] },
      {
        parseInput,
        loadGenerator,
        syncGeneratedFiles,
      },
    );

    await runCore(
      "spec.yaml",
      "out",
      { enumMode: "closed", scalars: [] },
      {
        parseInput,
        loadGenerator,
        syncGeneratedFiles,
        loadConfigOptions,
      },
      "openapi-rescript.json",
    );

    expect(generate).toHaveBeenNthCalledWith(1, normalized, {
      enumMode: "open",
      scalars: [],
    });
    expect(generate).toHaveBeenNthCalledWith(2, normalized, {
      enumMode: "closed",
      scalars: [
        {
          key: "string:uuid",
          typeName: "Hybit.Id.t",
          moduleName: "ApiScalars.Uuid",
        },
      ],
    });
  });
});
