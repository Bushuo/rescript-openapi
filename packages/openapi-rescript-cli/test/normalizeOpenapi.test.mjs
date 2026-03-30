import { describe, expect, it } from "vitest";
import { normalizeOpenApi } from "../src/NormalizeOpenApi.bs.js";

describe("normalizeOpenApi", () => {
  it.each([null, "openapi", 31, true, []])(
    "rejects non-objects: %p",
    (document) => {
      expect(() => normalizeOpenApi(document)).toThrow(/plain object/i);
    },
  );

  it("rejects non-3.1 documents", () => {
    expect(() =>
      normalizeOpenApi({
        openapi: "3.0.3",
        info: {
          title: "Rejected",
          version: "1.0.0",
        },
        paths: {},
      }),
    ).toThrow(/openapi 3\.1/i);
  });

  it("accepts OpenAPI 3.1.x documents with paths", () => {
    expect(
      normalizeOpenApi({
        openapi: "3.1.9",
        info: {
          title: "Accepted",
          version: "1.0.0",
        },
        paths: {},
        webhooks: {},
      }),
    ).toMatchObject({
      openapi: "3.1.9",
    });
  });

  it.each([
    {
      label: "components only",
      document: {
        openapi: "3.1.0",
        info: {
          title: "Missing paths",
          version: "1.0.0",
        },
        components: {},
      },
    },
    {
      label: "webhooks only",
      document: {
        openapi: "3.1.0",
        info: {
          title: "Missing paths",
          version: "1.0.0",
        },
        webhooks: {},
      },
    },
  ])("rejects $label documents without paths", ({ document }) => {
    expect(() => normalizeOpenApi(document)).toThrow(
      /must include a paths object/i,
    );
  });
});
