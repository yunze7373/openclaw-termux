/**
 * PM2 process manager support for Termux/Android.
 *
 * Termux doesn't have systemd, so we use pm2 as the process manager.
 * This module provides the same interface as systemd.ts/launchd.ts.
 */

import { execFile } from "node:child_process";
import { promisify } from "node:util";
import type { GatewayServiceRuntime } from "./service-runtime.js";
import { colorize, isRich, theme } from "../terminal/theme.js";
import { formatGatewayServiceDescription, resolveGatewaySystemdServiceName } from "./constants.js";

const execFileAsync = promisify(execFile);

const formatLine = (label: string, value: string) => {
  const rich = isRich();
  return `${colorize(rich, theme.muted, `${label}:`)} ${colorize(rich, theme.command, value)}`;
};

/** Check if running in Termux environment */
export function isTermux(): boolean {
  return Boolean(process.env.TERMUX_VERSION);
}

/** Resolve the pm2 process name for the gateway */
function resolvePm2ProcessName(profile?: string): string {
  // Use same naming convention as systemd for consistency
  const baseName = resolveGatewaySystemdServiceName(profile);
  // pm2 process names: openclaw-gateway or openclaw-gateway-<profile>
  return baseName.replace("openclaw-", "").replace("-gateway", "") === "gateway"
    ? "openclaw-gateway"
    : `openclaw-gateway-${profile}`;
}

/** Execute pm2 command */
async function execPm2(
  args: string[],
): Promise<{ stdout: string; stderr: string; code: number }> {
  try {
    const { stdout, stderr } = await execFileAsync("pm2", args, {
      encoding: "utf8",
      env: { ...process.env, PM2_SILENT: "true" },
    });
    return {
      stdout: String(stdout ?? ""),
      stderr: String(stderr ?? ""),
      code: 0,
    };
  } catch (error) {
    const e = error as {
      stdout?: unknown;
      stderr?: unknown;
      code?: unknown;
      message?: unknown;
    };
    return {
      stdout: typeof e.stdout === "string" ? e.stdout : "",
      stderr:
        typeof e.stderr === "string" ? e.stderr : typeof e.message === "string" ? e.message : "",
      code: typeof e.code === "number" ? e.code : 1,
    };
  }
}

/** Check if pm2 is available */
export async function isPm2Available(): Promise<boolean> {
  const res = await execPm2(["--version"]);
  return res.code === 0;
}

/** Assert pm2 is available, try to auto-install if not */
async function assertPm2Available(stdout?: NodeJS.WritableStream): Promise<void> {
  const available = await isPm2Available();
  if (available) {
    return;
  }
  
  if (stdout) {
    stdout.write("PM2 not found. Attempting auto-install via npm...\n");
  }
  
  try {
    await execFileAsync("npm", ["install", "-g", "pm2"]);
    if (stdout) {
      stdout.write("PM2 installed successfully.\n");
    }
  } catch (err) {
    const msg = err instanceof Error ? err.message : String(err);
    throw new Error(
      `PM2 auto-install failed: ${msg}\n` +
      "Please install manually: npm install -g pm2"
    );
  }
}

/** Parse pm2 jlist output to find our process */
async function getPm2ProcessInfo(
  processName: string,
): Promise<{
  found: boolean;
  status?: string;
  pid?: number;
  pm_id?: number;
  restart_time?: number;
  pm_uptime?: number;
} | null> {
  const res = await execPm2(["jlist"]);
  if (res.code !== 0) {
    return null;
  }
  try {
    const processes = JSON.parse(res.stdout) as Array<{
      name: string;
      pm2_env?: {
        status?: string;
        pm_uptime?: number;
        restart_time?: number;
      };
      pid?: number;
      pm_id?: number;
    }>;
    const proc = processes.find((p) => p.name === processName);
    if (!proc) {
      return { found: false };
    }
    return {
      found: true,
      status: proc.pm2_env?.status,
      pid: proc.pid,
      pm_id: proc.pm_id,
      restart_time: proc.pm2_env?.restart_time,
      pm_uptime: proc.pm2_env?.pm_uptime,
    };
  } catch {
    return null;
  }
}

/** Install/start the gateway as a pm2 process */
export async function installPm2Process({
  env,
  stdout,
  programArguments,
  workingDirectory,
  environment,
  description,
}: {
  env: Record<string, string | undefined>;
  stdout: NodeJS.WritableStream;
  programArguments: string[];
  workingDirectory?: string;
  environment?: Record<string, string | undefined>;
  description?: string;
}): Promise<{ processName: string }> {
  await assertPm2Available(stdout);

  const processName = resolvePm2ProcessName(env.OPENCLAW_PROFILE);
  
  // Check if already running
  const existing = await getPm2ProcessInfo(processName);
  if (existing?.found) {
    // Delete existing process first
    await execPm2(["delete", processName]);
  }

  // Build pm2 start command
  // programArguments is like: ["node", "/path/to/openclaw.mjs", "gateway", "start", "--port", "18789"]
  const [interpreter, script, ...args] = programArguments;
  
  const pm2Args = [
    "start",
    script,
    "--name", processName,
    "--interpreter", interpreter || "node",
    "--", // Separator for script arguments
    ...args,
  ];

  if (workingDirectory) {
    pm2Args.splice(pm2Args.indexOf("--"), 0, "--cwd", workingDirectory);
  }

  // Add environment variables
  if (environment) {
    for (const [key, value] of Object.entries(environment)) {
      if (value !== undefined) {
        pm2Args.splice(pm2Args.indexOf("--"), 0, "--env", `${key}=${value}`);
      }
    }
  }

  const startRes = await execPm2(pm2Args);
  if (startRes.code !== 0) {
    throw new Error(`pm2 start failed: ${startRes.stderr || startRes.stdout}`.trim());
  }

  // Save pm2 process list for auto-restart on reboot
  const saveRes = await execPm2(["save"]);
  if (saveRes.code !== 0) {
    stdout.write(`Warning: pm2 save failed (auto-restart on reboot may not work)\n`);
  }

  const serviceDescription = description ?? formatGatewayServiceDescription({
    profile: env.OPENCLAW_PROFILE,
    version: environment?.OPENCLAW_SERVICE_VERSION ?? env.OPENCLAW_SERVICE_VERSION,
  });

  stdout.write("\n");
  stdout.write(`${formatLine("Started pm2 process", processName)}\n`);
  stdout.write(`${formatLine("Description", serviceDescription)}\n`);
  stdout.write(`\nTip: Run 'pm2 logs ${processName}' to view logs\n`);
  stdout.write(`     Run 'pm2 startup' to enable auto-start on boot (requires Termux:Boot)\n`);

  return { processName };
}

/** Uninstall/delete the pm2 process */
export async function uninstallPm2Process({
  env,
  stdout,
}: {
  env: Record<string, string | undefined>;
  stdout: NodeJS.WritableStream;
}): Promise<void> {
  await assertPm2Available(stdout);
  
  const processName = resolvePm2ProcessName(env.OPENCLAW_PROFILE);
  
  const existing = await getPm2ProcessInfo(processName);
  if (!existing?.found) {
    stdout.write(`pm2 process '${processName}' not found\n`);
    return;
  }

  const res = await execPm2(["delete", processName]);
  if (res.code !== 0) {
    throw new Error(`pm2 delete failed: ${res.stderr || res.stdout}`.trim());
  }

  // Save to persist the deletion
  await execPm2(["save"]);

  stdout.write(`${formatLine("Removed pm2 process", processName)}\n`);
}

/** Stop the pm2 process */
export async function stopPm2Process({
  stdout,
  env,
}: {
  stdout: NodeJS.WritableStream;
  env?: Record<string, string | undefined>;
}): Promise<void> {
  await assertPm2Available(stdout);
  
  const processName = resolvePm2ProcessName(env?.OPENCLAW_PROFILE);
  
  const res = await execPm2(["stop", processName]);
  if (res.code !== 0) {
    throw new Error(`pm2 stop failed: ${res.stderr || res.stdout}`.trim());
  }

  stdout.write(`${formatLine("Stopped pm2 process", processName)}\n`);
}

/** Restart the pm2 process */
export async function restartPm2Process({
  stdout,
  env,
}: {
  stdout: NodeJS.WritableStream;
  env?: Record<string, string | undefined>;
}): Promise<void> {
  await assertPm2Available(stdout);
  
  const processName = resolvePm2ProcessName(env?.OPENCLAW_PROFILE);
  
  const res = await execPm2(["restart", processName]);
  if (res.code !== 0) {
    throw new Error(`pm2 restart failed: ${res.stderr || res.stdout}`.trim());
  }

  stdout.write(`${formatLine("Restarted pm2 process", processName)}\n`);
}

/** Check if the pm2 process is running */
export async function isPm2ProcessRunning(args: {
  env?: Record<string, string | undefined>;
}): Promise<boolean> {
  const available = await isPm2Available();
  if (!available) {
    return false;
  }
  
  const processName = resolvePm2ProcessName(args.env?.OPENCLAW_PROFILE);
  const info = await getPm2ProcessInfo(processName);
  
  return info?.found === true && info.status === "online";
}

/** Read the pm2 process command (for display/debugging) */
export async function readPm2ProcessCommand(
  env: Record<string, string | undefined>,
): Promise<{
  programArguments: string[];
  workingDirectory?: string;
  environment?: Record<string, string>;
  sourcePath?: string;
} | null> {
  const processName = resolvePm2ProcessName(env.OPENCLAW_PROFILE);
  const res = await execPm2(["jlist"]);
  if (res.code !== 0) {
    return null;
  }
  try {
    const processes = JSON.parse(res.stdout) as Array<{
      name: string;
      pm2_env?: {
        pm_exec_path?: string;
        pm_cwd?: string;
        args?: string[];
        env?: Record<string, string>;
        exec_interpreter?: string;
      };
    }>;
    const proc = processes.find((p) => p.name === processName);
    if (!proc?.pm2_env) {
      return null;
    }
    const pm2Env = proc.pm2_env;
    const programArguments = [
      pm2Env.exec_interpreter || "node",
      pm2Env.pm_exec_path || "",
      ...(pm2Env.args || []),
    ].filter(Boolean);
    
    return {
      programArguments,
      workingDirectory: pm2Env.pm_cwd,
      environment: pm2Env.env,
      sourcePath: `pm2:${processName}`,
    };
  } catch {
    return null;
  }
}

/** Read pm2 process runtime status */
export async function readPm2ProcessRuntime(
  env: Record<string, string | undefined> = process.env as Record<string, string | undefined>,
): Promise<GatewayServiceRuntime> {
  const available = await isPm2Available();
  if (!available) {
    return {
      status: "unknown",
      detail: "pm2 not installed",
    };
  }
  
  const processName = resolvePm2ProcessName(env.OPENCLAW_PROFILE);
  const info = await getPm2ProcessInfo(processName);
  
  if (!info) {
    return {
      status: "unknown",
      detail: "Failed to query pm2",
    };
  }
  
  if (!info.found) {
    return {
      status: "stopped",
      detail: "Process not found in pm2",
      missingUnit: true,
    };
  }
  
  const status = info.status === "online" ? "running" : "stopped";
  
  return {
    status,
    state: info.status,
    pid: info.pid,
    ...(info.restart_time !== undefined ? { restartCount: info.restart_time } : {}),
    ...(info.pm_uptime !== undefined ? { uptimeMs: Date.now() - info.pm_uptime } : {}),
  };
}
