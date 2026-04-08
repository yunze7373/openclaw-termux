import { describe, expect, it, vi, afterEach } from "vitest";

describe("resolveGatewayService() - platform detection", () => {
  afterEach(() => {
    vi.restoreAllMocks();
    delete process.env.TERMUX_VERSION;
  });

  it("returns pm2 service on android platform", async () => {
    vi.stubGlobal("process", { ...process, platform: "android" });
    // Force re-import to pick up mocked platform
    const { resolveGatewayService } = await import("./service.js");
    const service = resolveGatewayService();
    expect(service.label).toBe("pm2");
    expect(service.loadedText).toBe("running");
    vi.unstubAllGlobals();
  });

  it("returns pm2 service on linux with TERMUX_VERSION", async () => {
    process.env.TERMUX_VERSION = "0.118.0";
    vi.stubGlobal("process", {
      ...process,
      platform: "linux",
      env: { ...process.env, TERMUX_VERSION: "0.118.0" },
    });
    const { resolveGatewayService } = await import("./service.js");
    const service = resolveGatewayService();
    expect(service.label).toBe("pm2");
    vi.unstubAllGlobals();
  });

  it("returns systemd service on regular linux", async () => {
    delete process.env.TERMUX_VERSION;
    vi.stubGlobal("process", {
      ...process,
      platform: "linux",
      env: { ...process.env },
    });
    const { resolveGatewayService } = await import("./service.js");
    const service = resolveGatewayService();
    expect(service.label).toBe("systemd");
    vi.unstubAllGlobals();
  });
});
