import { runCommandWithTimeout } from "../../process/exec.js";

export type AndroidNotifyParams = {
  title?: string;
  body?: string;
  sound?: string;
  priority?: "passive" | "active" | "timeSensitive";
};

export async function sendAndroidNotification(params: AndroidNotifyParams): Promise<{
  ok: boolean;
  stdout: string;
  stderr: string;
  code: number | null;
  argv: string[];
}> {
  const isTermuxAndroid = process.platform === "android" || Boolean(process.env.TERMUX_VERSION);
  if (!isTermuxAndroid) {
    return {
      ok: false,
      stdout: "",
      stderr: "system.notify is only supported on Android/Termux for this node host",
      code: null,
      argv: [],
    };
  }

  const title = (params.title ?? "").trim();
  const body = (params.body ?? "").trim();
  if (!title && !body) {
    return { ok: false, stdout: "", stderr: "missing title/body", code: null, argv: [] };
  }

  // Requires: pkg install termux-api; termux-api app installed/enabled.
  const argv: string[] = ["termux-notification"];
  if (title) {
    argv.push("--title", title);
  }
  if (body) {
    argv.push("--content", body);
  }
  const sound = (params.sound ?? "").trim();
  if (sound) {
    argv.push("--sound", sound);
  }

  // Map OpenClaw priority names to Termux's coarse levels.
  const priority = params.priority;
  if (priority === "passive") {
    argv.push("--priority", "low");
  } else if (priority === "active" || priority === "timeSensitive") {
    argv.push("--priority", "high");
  }

  const result = await runCommandWithTimeout(argv, { timeoutMs: 5_000, allowFailure: true });
  return {
    ok: result.code === 0,
    stdout: result.stdout.trim(),
    stderr: result.stderr.trim(),
    code: result.code,
    argv,
  };
}

