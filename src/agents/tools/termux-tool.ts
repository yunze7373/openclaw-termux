import { Type } from "@sinclair/typebox";
import { exec } from "child_process";
import { promisify } from "util";

import type { AnyAgentTool } from "./common.js";
import { jsonResult } from "./common.js";

const execAsync = promisify(exec);

const TermuxLocationSchema = Type.Object({
  provider: Type.Optional(Type.Union([Type.Literal("network"), Type.Literal("gps"), Type.Literal("passive")])),
  request: Type.Optional(Type.Union([Type.Literal("once"), Type.Literal("last"), Type.Literal("updates")])),
});

export function createTermuxLocationTool(): AnyAgentTool {
  return {
    label: "Termux Location",
    name: "termux_location",
    description: "Get device location via Termux API. Default provider is 'network' for best indoor results.",
    parameters: TermuxLocationSchema,
    execute: async (_toolCallId, args) => {
      if (process.platform !== "android") {
        return jsonResult({ ok: false, error: "Only available on Android (Termux)" });
      }

      const params = args as { provider?: string; request?: string };
      // Default to network provider for reliability
      const provider = params.provider ?? "network";
      const request = params.request ?? "once";

      try {
        const command = `termux-location -p ${provider} -r ${request}`;
        const { stdout, stderr } = await execAsync(command);

        if (stderr && stderr.trim()) {
          // Some termux commands output to stderr even on success, but usually it's an error
           // We'll log it but try to parse stdout first
           console.warn(`termux-location stderr: ${stderr}`);
        }

        try {
            const result = JSON.parse(stdout);
            return jsonResult({ ok: true, result });
        } catch (parseError) {
             return jsonResult({ ok: false, error: "Failed to parse JSON output", raw: stdout });
        }

      } catch (error) {
        return jsonResult({
          ok: false,
          error: error instanceof Error ? error.message : String(error),
        });
      }
    },
  };
}
