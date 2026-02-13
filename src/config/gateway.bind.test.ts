
import { describe, expect, it } from "vitest";
import { OpenClawSchema } from "./zod-schema.js";

describe("Gateway Bind Compatibility", () => {
  it('should transform "0.0.0.0" to "lan"', () => {
    const config = {
      gateway: {
        bind: "0.0.0.0",
      },
    };
    const result = OpenClawSchema.safeParse(config);
    expect(result.success).toBe(true);
    if (result.success) {
      expect(result.data.gateway?.bind).toBe("lan");
    }
  });

  it('should transform "any" to "lan"', () => {
    const config = {
      gateway: {
        bind: "any",
      },
    };
    const result = OpenClawSchema.safeParse(config);
    expect(result.success).toBe(true);
    if (result.success) {
      expect(result.data.gateway?.bind).toBe("lan");
    }
  });

  it('should handle whitespace: "0.0.0.0 " -> "lan"', () => {
    const config = {
      gateway: {
        bind: "0.0.0.0 ",
      },
    };
    const result = OpenClawSchema.safeParse(config);
    expect(result.success).toBe(true);
    if (result.success) {
      expect(result.data.gateway?.bind).toBe("lan");
    }
  });

  it('should preserve "lan"', () => {
    const config = {
      gateway: {
        bind: "lan",
      },
    };
    const result = OpenClawSchema.safeParse(config);
    expect(result.success).toBe(true);
    if (result.success) {
      expect(result.data.gateway?.bind).toBe("lan");
    }
  });

  it('should preserve "loopback"', () => {
    const config = {
      gateway: {
        bind: "loopback",
      },
    };
    const result = OpenClawSchema.safeParse(config);
    expect(result.success).toBe(true);
    if (result.success) {
      expect(result.data.gateway?.bind).toBe("loopback");
    }
  });

  it('should preserve "auto"', () => {
      const config = {
        gateway: {
          bind: "auto",
        },
      };
      const result = OpenClawSchema.safeParse(config);
      expect(result.success).toBe(true);
      if (result.success) {
        expect(result.data.gateway?.bind).toBe("auto");
      }
    });

  it('should fail on invalid values', () => {
    const config = {
      gateway: {
        bind: "invalid-value",
      },
    };
    const result = OpenClawSchema.safeParse(config);
    expect(result.success).toBe(false);
  });

  it('should handle whitespace in mode: "local " -> "local"', () => {
    const config = {
      gateway: {
        mode: "local ",
      },
    };
    const result = OpenClawSchema.safeParse(config);
    expect(result.success).toBe(true);
    if (result.success) {
      expect(result.data.gateway?.mode).toBe("local");
    }
  });

  it('should handle whitespace in mode: "remote " -> "remote"', () => {
    const config = {
      gateway: {
        mode: "remote ",
      },
    };
    const result = OpenClawSchema.safeParse(config);
    expect(result.success).toBe(true);
    if (result.success) {
      expect(result.data.gateway?.mode).toBe("remote");
    }
  });
});
