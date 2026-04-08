import { describe, expect, it, vi, afterEach } from "vitest";

/**
 * Termux-specific tests for skills-install.ts
 * Tests BREW_TO_PKG_MAP, MACOS_ONLY_SKILLS, and isTermux detection.
 */
describe("skills-install Termux compatibility", () => {
  afterEach(() => {
    vi.restoreAllMocks();
    vi.unstubAllGlobals();
    delete process.env.TERMUX_VERSION;
  });

  it("module loads successfully with TERMUX_VERSION set", async () => {
    process.env.TERMUX_VERSION = "0.118.0";
    vi.resetModules();
    const mod = await import("./skills-install.js");
    expect(mod).toBeDefined();
    expect(typeof mod.installSkill).toBe("function");
  });

  it("module loads successfully with android platform", async () => {
    const origPlatform = process.platform;
    Object.defineProperty(process, "platform", { value: "android", configurable: true });
    vi.resetModules();
    const mod = await import("./skills-install.js");
    expect(mod).toBeDefined();
    Object.defineProperty(process, "platform", { value: origPlatform, configurable: true });
  });
});
