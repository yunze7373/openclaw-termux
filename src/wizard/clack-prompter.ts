import {
  autocompleteMultiselect,
  cancel,
  confirm,
  intro,
  isCancel,
  multiselect,
  type Option,
  outro,
  select,
  spinner,
  text,
} from "@clack/prompts";
import { createCliProgress } from "../cli/progress.js";
import { stripAnsi } from "../terminal/ansi.js";
import { note as emitNote } from "../terminal/note.js";
import { stylePromptHint, stylePromptMessage, stylePromptTitle } from "../terminal/prompt-style.js";
import { theme } from "../terminal/theme.js";
import type { WizardProgress, WizardPrompter } from "./prompts.js";
import { WizardCancelledError } from "./prompts.js";

/**
 * Ensure process.stdin is flowing and in raw mode before each interactive prompt.
 *
 * Two known issues on Node.js ≥ 22 / Termux (process.platform === "android"):
 *
 * 1. PAUSE: @clack/core's Prompt.close() calls rl.close() → stdin.pause().
 *    The next prompt's readline.createInterface() should resume it, but on
 *    Android the resume does not reliably take effect, leaving stdin paused
 *    and the prompt hung indefinitely.
 *
 * 2. RAW MODE: @clack/core calls setRawMode(true) on prompt start and
 *    setRawMode(false) on close().  On Android the close-time setRawMode(false)
 *    leaves stdin in cooked/echoed mode; the next prompt's setRawMode(true)
 *    call succeeds but the terminal's echo inhibition is not applied in time,
 *    causing arrow-key escape sequences (e.g. ^[a) to be printed raw instead
 *    of being intercepted by readline.
 *
 * Calling resume() and setRawMode(true) here is harmless on other platforms.
 */
function ensureStdinFlowing(): void {
  try {
    const stdin = process.stdin;
    if (typeof stdin.isPaused === "function" && stdin.isPaused()) {
      stdin.resume();
    }
    // Re-enable raw mode so the prompt can intercept arrow keys / escape
    // sequences.  Without this, on Termux/Android the arrow keys are echoed
    // as raw bytes (^[A etc.) instead of being captured by @clack/core.
    if (stdin.isTTY && typeof stdin.setRawMode === "function") {
      stdin.setRawMode(true);
    }
  } catch {
    // best-effort — ignore errors (e.g. stdin not a TTY, already destroyed)
  }
}

function guardCancel<T>(value: T | symbol): T {
  if (isCancel(value)) {
    cancel(stylePromptTitle("Setup cancelled.") ?? "Setup cancelled.");
    throw new WizardCancelledError();
  }
  return value;
}

function normalizeSearchTokens(search: string): string[] {
  return search
    .toLowerCase()
    .split(/\s+/)
    .map((token) => token.trim())
    .filter((token) => token.length > 0);
}

function buildOptionSearchText<T>(option: Option<T>): string {
  const label = stripAnsi(option.label ?? "");
  const hint = stripAnsi(option.hint ?? "");
  const value = String(option.value ?? "");
  return `${label} ${hint} ${value}`.toLowerCase();
}

export function tokenizedOptionFilter<T>(search: string, option: Option<T>): boolean {
  const tokens = normalizeSearchTokens(search);
  if (tokens.length === 0) {
    return true;
  }
  const haystack = buildOptionSearchText(option);
  return tokens.every((token) => haystack.includes(token));
}

export function createClackPrompter(): WizardPrompter {
  return {
    intro: async (title) => {
      intro(stylePromptTitle(title) ?? title);
    },
    outro: async (message) => {
      outro(stylePromptTitle(message) ?? message);
    },
    note: async (message, title) => {
      emitNote(message, title);
    },
    select: async (params) => {
      ensureStdinFlowing();
      return guardCancel(
        await select({
          message: stylePromptMessage(params.message),
          options: params.options.map((opt) => {
            const base = { value: opt.value, label: opt.label };
            return opt.hint === undefined ? base : { ...base, hint: stylePromptHint(opt.hint) };
          }) as Option<(typeof params.options)[number]["value"]>[],
          initialValue: params.initialValue,
        }),
      );
    },
    multiselect: async (params) => {
      ensureStdinFlowing();
      const options = params.options.map((opt) => {
        const base = { value: opt.value, label: opt.label };
        return opt.hint === undefined ? base : { ...base, hint: stylePromptHint(opt.hint) };
      }) as Option<(typeof params.options)[number]["value"]>[];

      if (params.searchable) {
        return guardCancel(
          await autocompleteMultiselect({
            message: stylePromptMessage(params.message),
            options,
            initialValues: params.initialValues,
            filter: tokenizedOptionFilter,
          }),
        );
      }

      return guardCancel(
        await multiselect({
          message: stylePromptMessage(params.message),
          options,
          initialValues: params.initialValues,
        }),
      );
    },
    text: async (params) => {
      ensureStdinFlowing();
      const validate = params.validate;
      return guardCancel(
        await text({
          message: stylePromptMessage(params.message),
          initialValue: params.initialValue,
          placeholder: params.placeholder,
          validate: validate ? (value) => validate(value ?? "") : undefined,
        }),
      );
    },
    confirm: async (params) => {
      ensureStdinFlowing();
      return guardCancel(
        await confirm({
          message: stylePromptMessage(params.message),
          initialValue: params.initialValue,
        }),
      );
    },
    progress: (label: string): WizardProgress => {
      const spin = spinner();
      spin.start(theme.accent(label));
      const osc = createCliProgress({
        label,
        indeterminate: true,
        enabled: true,
        fallback: "none",
      });
      return {
        update: (message) => {
          spin.message(theme.accent(message));
          osc.setLabel(message);
        },
        stop: (message) => {
          osc.done();
          spin.stop(message);
        },
      };
    },
  };
}
