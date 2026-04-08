#!/usr/bin/env node
/**
 * termux-type-alias-injector.mjs
 * Replaces Playwright type imports with `type X = any` aliases for Termux compatibility.
 *
 * Usage:
 *   node scripts/termux-type-alias-injector.mjs <file> <type1,type2,...> <from-module> [--dry-run]
 *
 * Example:
 *   node scripts/termux-type-alias-injector.mjs src/browser/pw-tools-core.downloads.ts Dialog,FileChooser playwright
 */
import { readFileSync, writeFileSync } from "node:fs";

const [,, filePath, typeList, fromModule, ...flags] = process.argv;
const dryRun = flags.includes("--dry-run");

if (!filePath || !typeList || !fromModule) {
  console.error("Usage: termux-type-alias-injector.mjs <file> <type1,type2,...> <from-module> [--dry-run]");
  process.exit(1);
}

const types = typeList.split(",").map(t => t.trim());
let src = readFileSync(filePath, "utf8");
let changed = false;

// Check if aliases already exist
const allPresent = types.every(t => src.includes(`type ${t} = any`));
if (allPresent) {
  console.log(`[SKIP] ${filePath}: all type aliases already present`);
  process.exit(0);
}

const escModule = fromModule.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");

// Remove import lines that import these types from the module
for (const typeName of types) {
  // Remove from: import { ..., TypeName, ... } from "module"
  // or: import type { ..., TypeName, ... } from "module"
  const importRe = new RegExp(
    `import\\s+(type\\s+)?\\{([^}]*)\\b${typeName}\\b([^}]*)\\}\\s+from\\s+["']${escModule}["'];?`,
    "g"
  );
  src = src.replace(importRe, (full, typeKw, before, after) => {
    changed = true;
    // Remove the specific type from the import list
    const remaining = (before + after)
      .split(",")
      .map(s => s.trim())
      .filter(s => s && s !== typeName);
    if (remaining.length === 0) return ""; // entire import removed
    return `import ${typeKw || ""}{ ${remaining.join(", ")} } from "${fromModule}";`;
  });
}

// Insert type aliases after the last import statement
const lines = src.split("\n");
let lastImportIdx = -1;
for (let i = 0; i < lines.length; i++) {
  if (/^import\s/.test(lines[i]) || /^import\s/.test(lines[i].trim())) {
    lastImportIdx = i;
  }
}

const aliasLines = types
  .filter(t => !src.includes(`type ${t} = any`))
  .map(t => `type ${t} = any;`);

if (aliasLines.length > 0) {
  changed = true;
  const insertAt = lastImportIdx >= 0 ? lastImportIdx + 1 : 0;
  lines.splice(insertAt, 0, "", ...aliasLines);
  src = lines.join("\n");
}

if (!changed) {
  console.log(`[SKIP] ${filePath}: no changes needed`);
  process.exit(0);
}

if (dryRun) {
  console.log(`[DRY] Would rewrite ${filePath} with aliases: ${types.join(", ")}`);
} else {
  writeFileSync(filePath, src, "utf8");
  console.log(`[OK] ${filePath}: injected type aliases: ${types.join(", ")}`);
}
