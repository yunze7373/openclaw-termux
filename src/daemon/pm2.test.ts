import { describe, expect, it, vi, beforeEach, afterEach } from "vitest";

// Mock child_process before importing pm2
vi.mock("node:child_process", () => ({
  execFile: vi.fn(),
}));

vi.mock("../terminal/theme.js", () => ({
  colorize: (_rich: boolean, _theme: unknown, text: string) => text,
  isRich: () => false,
  theme: { muted: "", command: "" },
}));

vi.mock("./constants.js", () => ({
  formatGatewayServiceDescription: (profile?: string) =>
    profile ? `OpenClaw Gateway (${profile})` : "OpenClaw Gateway",
  resolveGatewaySystemdServiceName: (profile?: string) =>
    profile ? `openclaw-gateway-${profile}` : "openclaw-gateway",
}));

describe("pm2 - Termux service manager", () => {
  beforeEach(() => {
    vi.resetModules();
  });

  afterEach(() => {
    vi.restoreAllMocks();
    delete process.env.TERMUX_VERSION;
  });

  describe("isTermux()", () => {
    it("returns true when TERMUX_VERSION is set", async () => {
      process.env.TERMUX_VERSION = "0.118.0";
      const { isTermux } = await import("./pm2.js");
      expect(isTermux()).toBe(true);
    });

    it("returns false when TERMUX_VERSION is not set", async () => {
      delete process.env.TERMUX_VERSION;
      const { isTermux } = await import("./pm2.js");
      expect(isTermux()).toBe(false);
    });
  });

  describe("isPm2Available()", () => {
    it("returns true when pm2 --version succeeds", async () => {
      const { execFile } = await import("node:child_process");
      const mockExecFile = vi.mocked(execFile);
      mockExecFile.mockImplementation((_cmd, _args, _opts, cb) => {
        const callback = typeof _opts === "function" ? _opts : cb;
        callback?.(null, "5.3.0\n", "");
        return {} as any;
      });

      const { isPm2Available } = await import("./pm2.js");
      expect(await isPm2Available()).toBe(true);
    });

    it("returns false when pm2 is not found", async () => {
      const { execFile } = await import("node:child_process");
      const mockExecFile = vi.mocked(execFile);
      mockExecFile.mockImplementation((_cmd, _args, _opts, cb) => {
        const callback = typeof _opts === "function" ? _opts : cb;
        callback?.(Object.assign(new Error("ENOENT"), { code: "ENOENT" }), "", "");
        return {} as any;
      });

      const { isPm2Available } = await import("./pm2.js");
      expect(await isPm2Available()).toBe(false);
    });
  });
});
