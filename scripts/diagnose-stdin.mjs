#!/usr/bin/env node
/**
 * Diagnostic script to verify the stdin pause/resume hypothesis on Termux.
 *
 * Run on Termux:  TERM=dumb node scripts/diagnose-stdin.mjs
 *
 * Expected output on a healthy platform:
 *   [1] stdin.isTTY: true
 *   [2] setRawMode available: true
 *   [3] paused before rl: false
 *   [4] paused after rl.prompt(): false
 *   [5] paused after rl.close(): true   ← rl.close() pauses stdin
 *   [6] paused after rl2 created: false  ← new rl should resume
 *   ... rl2 question answered ...
 *
 * If step [6] shows "true" → confirms the bug: readline.createInterface
 * does NOT resume stdin on this Node.js build.
 */

import * as readline from "node:readline";

const stdin = process.stdin;

console.log(`[1] stdin.isTTY: ${stdin.isTTY}`);
console.log(`[2] setRawMode available: ${typeof stdin.setRawMode === "function"}`);
console.log(`[3] paused before rl: ${stdin.isPaused()}`);

// --- simulate what @clack/core does for ConfirmPrompt ---
const rl1 = readline.createInterface({ input: stdin, output: process.stdout, terminal: true });
rl1.prompt();
console.log(`[4] paused after rl1.prompt(): ${stdin.isPaused()}`);

// simulate submitting confirm
rl1.close();
console.log(`[5] paused after rl1.close(): ${stdin.isPaused()}`);

// --- simulate what @clack/core does for the NEXT prompt (SelectPrompt) ---
const rl2 = readline.createInterface({ input: stdin, output: process.stdout, terminal: true });
rl2.prompt();
console.log(`[6] paused after rl2.prompt(): ${stdin.isPaused()}`);

if (stdin.isPaused()) {
  console.log("\n>>> BUG CONFIRMED: stdin is still paused after new readline interface.");
  console.log(">>> Trying manual stdin.resume()...");
  stdin.resume();
  console.log(`[7] paused after manual resume: ${stdin.isPaused()}`);
}

console.log("\n[*] Now type something and press Enter to verify input works:");
rl2.question("  > ", (answer) => {
  console.log(`[OK] Received: "${answer}"`);
  rl2.close();
  process.exit(0);
});

// Timeout in case stdin is stuck
setTimeout(() => {
  console.log("\n[TIMEOUT] stdin appears to be stuck — no input received after 15s.");
  process.exit(1);
}, 15000);
