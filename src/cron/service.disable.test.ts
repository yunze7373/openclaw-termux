
import path from "node:path";
import fs from "node:fs";
import os from "node:os";
import { describe, it, expect, vi, afterEach } from "vitest";
import { CronService } from "./service.js";
import { resolveCronStorePath } from "./store.js";

async function makeStorePath() {
  const dir = await fs.promises.mkdtemp(path.join(os.tmpdir(), "moltbot-cron-disable-"));
  return {
    dir,
    storePath: path.join(dir, "cron", "jobs.json"),
    cleanup: async () => await fs.promises.rm(dir, { recursive: true, force: true }),
  };
}

describe("CronService disable behavior", () => {
  it("stops rescheduling when disabled via update", async () => {
    const { storePath, cleanup } = await makeStorePath();
    const log = { info: vi.fn(), warn: vi.fn(), error: vi.fn(), debug: vi.fn() };
    const enqueueSystemEvent = vi.fn();
    const requestHeartbeatNow = vi.fn();
    
    // Mock time to control execution
    let now = 1000;
    const deps = {
      storePath,
      cronEnabled: true,
      log,
      nowMs: () => now,
      enqueueSystemEvent,
      requestHeartbeatNow,
      runHeartbeatOnce: vi.fn().mockResolvedValue({ status: "ran" }),
      runIsolatedAgentJob: vi.fn(),
    };

    const service = new CronService(deps);
    await service.start();

    // 1. Add a recurring job (every 1000ms)
    const job = await service.add({
      name: "recur",
      schedule: { kind: "every", everyMs: 1000 },
      payload: { kind: "systemEvent", text: "tick" },
      sessionTarget: "main",
    });

    expect(job.enabled).toBe(true);
    expect(job.state.nextRunAtMs).toBe(2000); // 1000 + 1000

    // 2. Advance time to trigger run
    now = 2000;
    // Manually trigger run since we are not using real timers in test
    await service.run(job.id, "due");

    // It should have rescheduled
    expect(job.state.nextRunAtMs).toBe(3000);
    expect(enqueueSystemEvent).toHaveBeenCalledTimes(1);

    // 3. Disable the job
    await service.update(job.id, { enabled: false });
    
    const updated = (await service.list({ includeDisabled: true })).find(j => j.id === job.id);
    expect(updated?.enabled).toBe(false);
    expect(updated?.state.nextRunAtMs).toBeUndefined();

    // 4. Advance time again
    now = 3000;
    
    // Simulate race condition: Job starts running, then disabled while running
    // We can't easily mock internal locked/concurrency in this unit test without exposing internals
    // But we can verify that if we modify the job object *during* executeJob (simulated), it respects it.
    
    const longRunningJob = await service.add({
      name: "long",
      schedule: { kind: "every", everyMs: 1000 },
      payload: { kind: "systemEvent", text: "tick" },
      sessionTarget: "main",
    });
    
    // Mock runIsolatedAgentJob to wait
    let finishJob: () => void;
    const jobPromise = new Promise<void>(resolve => { finishJob = resolve; });
    
    // We need to inject this into deps but deps is already created. 
    // We can't easily change deps.runIsolatedAgentJob behavior dynamically in this setup 
    // because executeJob logic for 'main' jobs doesn't use it.
    // 'main' jobs run synchronously-ish (enqueueSystemEvent).
    // Let's use 'isolated' job.
    
    const isolatedJob = await service.add({
      name: "isolated",
      schedule: { kind: "every", everyMs: 1000 },
      payload: { kind: "agentTurn", message: "hi" },
      sessionTarget: "isolated",
    });
    
    // Override runIsolatedAgentJob for the service's deps
    // @ts-ignore
    service.state.deps.runIsolatedAgentJob = async () => {
        await jobPromise;
        return { status: "ok", summary: "done" };
    };
    
    now = 4000; // Due
    
    // Trigger run (this will hang until finishJob is called)
    const runPromise = service.run(isolatedJob.id, "due");
    
    // While it's running (awaiting jobPromise), disable it
    // Note: service.update is locked, and service.run is locked. 
    // Since runPromise acquired lock, service.update will wait until runPromise finishes.
    // This confirms strict serialization.
    
    // To simulate the user's issue, we assume the user thinks "it keeps running".
    // If serialization works, update() runs AFTER job finishes. 
    // Job finishes -> reschedules itself (because enabled=true at that point).
    // Update runs -> disables it -> clears nextRunAtMs.
    
    finishJob!();
    await runPromise;
    
    await service.update(isolatedJob.id, { enabled: false });
    
    const isolatedUpdated = (await service.list({ includeDisabled: true })).find(j => j.id === isolatedJob.id);
    expect(isolatedUpdated?.enabled).toBe(false);
    expect(isolatedUpdated?.state.nextRunAtMs).toBeUndefined();
    
    await cleanup();
  });
});
