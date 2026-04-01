import { describe, expect, it, vi } from "vitest";
import { runCore } from "../src/RunCore.bs.js";

describe("runCore", () => {
  it("forwards enumMode to the generator", async () => {
    const normalized = { openapi: "3.1.0" };
    const generate = vi.fn(() => ({ ok: true, files: [] }));
    const loadGenerator = vi.fn(async () => generate);
    const parseInput = vi.fn(async () => normalized);
    const syncGeneratedFiles = vi.fn(async () => {});

    await runCore(
      "spec.yaml",
      "out",
      { enumMode: "open" },
      {
        parseInput,
        loadGenerator,
        syncGeneratedFiles,
      },
    );

    await runCore(
      "spec.yaml",
      "out",
      { enumMode: "closed" },
      {
        parseInput,
        loadGenerator,
        syncGeneratedFiles,
      },
    );

    expect(generate).toHaveBeenNthCalledWith(1, normalized, {
      enumMode: "open",
    });
    expect(generate).toHaveBeenNthCalledWith(2, normalized, {
      enumMode: "closed",
    });
  });
});
