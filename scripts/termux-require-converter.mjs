#!/usr/bin/env node
/**
 * termux-require-converter.mjs
 * Converts ESM imports to require() for specified modules in TypeScript files.
 * Used by termux-auto-patch.sh for the optional-imports patch category.
 *
 * Usage:
 *   node scripts/termux-require-converter.mjs <file> <module> [--dry-run]
 *
 * Examples:
 *   node scripts/termux-require-converter.mjs src/shared/net/ip.ts ipaddr.js
 *   node scripts/termux-require-converter.mjs src/discord/voice/manager.ts @discordjs/voice --dry-run
 */
import { readFileSync, writeFileSync } from "node:fs";

const [,, filePath, moduleName, ...flags] = process.argv;
const dryRun = flags.includes("--dry-run");

if (!filePath || !moduleName) {
  console.error("Usage: termux-require-converter.mjs <file> <module> [--dry-run]");
  process.exit(1);
}

const escModule = moduleName.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
let src = readFileSync(filePath, "utf8");
let changed = false;

// Pattern 1: import * as X from "module"
const starRe = new RegExp(`import\\s+\\*\\s+as\\s+(\\w+)\\s+from\\s+["']${escModule}["'];?`, "g");
src = src.replace(starRe, (_, name) => {
  changed = true;
  return `const ${name} = require("${moduleName}") as typeof import("${moduleName}");`;
});

// Pattern 2: import X from "module" (default import)
const defaultRe = new RegExp(`import\\s+(\\w+)\\s+from\\s+["']${escModule}["'];?`, "g");
src = src.replace(defaultRe, (_, name) => {
  changed = true;
  return `const ${name} = require("${moduleName}") as typeof import("${moduleName}");`;
});

// Pattern 3: import { A, B, C } from "module" (named imports)
const namedRe = new RegExp(`import\\s+\\{([^}]+)\\}\\s+from\\s+["']${escModule}["'];?`, "g");
src = src.replace(namedRe, (full, names) => {
  // Check if it's already a type-only import
  if (/import\s+type\s/.test(full)) return full;

  const imported = names.split(",").map(n => n.trim()).filter(Boolean);
  // Separate type imports from value imports
  const typeImports = imported.filter(n => n.startsWith("type "));
  const valueImports = imported.filter(n => !n.startsWith("type "));

  if (valueImports.length === 0) return full; // all type-only, leave as is

  changed = true;
  const lines = [];
  // require() for value imports
  lines.push(`const { ${valueImports.join(", ")} } = require("${moduleName}") as any;`);
  // Add type import for all names (so TS can still see types)
  const allNames = imported.map(n => n.replace(/^type\s+/, ""));
  lines.push(`import type { ${allNames.join(", ")} } from "${moduleName}";`);
  return lines.join("\n");
});

if (!changed) {
  // Check if require() already exists
  if (src.includes(`require("${moduleName}")`) || src.includes(`require('${moduleName}')`)) {
    console.log(`[SKIP] ${filePath}: require("${moduleName}") already present`);
    process.exit(0);
  }
  console.log(`[SKIP] ${filePath}: no matching import pattern for "${moduleName}"`);
  process.exit(0);
}

if (dryRun) {
  console.log(`[DRY] Would rewrite ${filePath}`);
  console.log("--- Preview (first 20 lines with changes) ---");
  const lines = src.split("\n").slice(0, 40);
  for (const line of lines) {
    if (line.includes("require(") || line.includes("import type")) {
      console.log(`  > ${line}`);
    }
  }
} else {
  writeFileSync(filePath, src, "utf8");
  console.log(`[OK] ${filePath}: converted "${moduleName}" import to require()`);
}
