import { describe, expect, it } from "vitest";
import { analyzeConfigSchema } from "./config-form.analyze";
import { isPathUnsupported, pathKey } from "./config-form.shared";

describe("analyzeConfigSchema", () => {
  it("does not bubble up errors for map (additionalProperties) children", () => {
    const schema = {
      type: "object",
      properties: {
        accounts: {
          type: "object",
          additionalProperties: {
            type: "object",
            properties: {
              badField: { type: "unknownType" }
            }
          }
        }
      }
    };

    const analysis = analyzeConfigSchema(schema);
    // accounts itself should NOT be in unsupported
    expect(analysis.unsupportedPaths).not.toContain("accounts");
    // accounts.*.badField SHOULD be in unsupported
    expect(analysis.unsupportedPaths).toContain("accounts.*.badField");
  });

  it("does not bubble up errors for array items", () => {
    const schema = {
      type: "object",
      properties: {
        myList: {
          type: "array",
          items: {
            type: "object",
            properties: {
              badField: { type: "unknownType" }
            }
          }
        }
      }
    };

    const analysis = analyzeConfigSchema(schema);
    // myList itself should NOT be in unsupported
    expect(analysis.unsupportedPaths).not.toContain("myList");
    // myList.badField SHOULD be in unsupported (wildcard for array item was removed)
    expect(analysis.unsupportedPaths).toContain("myList.badField");
  });
});

describe("isPathUnsupported", () => {
  it("matches exact paths", () => {
    const unsupported = new Set(["simple.path"]);
    expect(isPathUnsupported(["simple", "path"], unsupported)).toBe(true);
    expect(isPathUnsupported(["other", "path"], unsupported)).toBe(false);
  });

  it("matches wildcard paths for maps", () => {
    const unsupported = new Set(["accounts.*.badField"]);
    
    // Match
    expect(isPathUnsupported(["accounts", "work", "badField"], unsupported)).toBe(true);
    expect(isPathUnsupported(["accounts", "personal", "badField"], unsupported)).toBe(true);

    // No match
    expect(isPathUnsupported(["accounts", "work", "goodField"], unsupported)).toBe(false);
    expect(isPathUnsupported(["other", "work", "badField"], unsupported)).toBe(false);
  });

  it("matches paths for arrays (where wildcard is implicit/removed)", () => {
    // Array items don't have * in the unsupported path after my change
    const unsupported = new Set(["myList.badField"]);

    // index 0 -> pathKey strips 0 -> myList.badField -> Match!
    expect(isPathUnsupported(["myList", 0, "badField"], unsupported)).toBe(true);
    expect(isPathUnsupported(["myList", 1, "badField"], unsupported)).toBe(true);
    
    // index 0 -> pathKey strips 0 -> myList.goodField -> No Match
    expect(isPathUnsupported(["myList", 0, "goodField"], unsupported)).toBe(false);
  });
});
