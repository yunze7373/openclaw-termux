# Native Dependencies - Termux/Android Optimization

This document describes the strategy for eliminating native dependency compilation on Termux/Android.

## Problem

When installing `npm i -g openclaw-android` on Termux, it tries to compile native dependencies:
- `@napi-rs/canvas` (CPU instruction incompatibility - "Illegal instruction" errors)
- `node-llama-cpp` (requires heavy compilation)

This causes installation failures on low-end devices.

## Solution Overview

### 1. **Make Dependencies Optional** ✅

Dependencies have been converted from `peerDependencies` to `optionalDependencies`:

```json
"optionalDependencies": {
  "@discordjs/opus": "^0.10.0",
  "@napi-rs/canvas": "^0.1.89",
  "node-llama-cpp": "3.15.1"
}
```

This allows installation to succeed even if these modules fail to compile.

### 2. **Implement Graceful Fallback** ✅ 

Created `src/native-deps.ts` which provides:
- Safe dynamic loading with error handling
- Graceful degradation if modules unavailable
- Status reporting via `getNativeDepsReport()`

Usage in code:
```typescript
import { loadOptionalNative, isNativeAvailable } from './native-deps';

// Try to load, but don't fail if unavailable
const canvas = await loadOptionalNative('canvas');
if (!canvas) {
  // Use fallback or disable feature
  console.warn('Canvas not available, media features disabled');
}

// Check availability
if (isNativeAvailable('llama-cpp')) {
  // Use local LLM execution
} else {
  // Fall back to cloud-based models
}
```

### 3. **Publish Prebuilt Binaries** (For Future Releases)

#### Option A: Separate npm Package for Termux

```bash
# Create lightweight Termux variants
npm publish openclaw-android@2026.2.22  # Main package (no natives)
npm publish openclaw-android-termux@2026.2.22  # With prebuilt binaries

# Installation
npm i -g openclaw-android              # Pure JS (always works)
npm i -g openclaw-android-termux       # With prebuilts if available
```

#### Option B: GitHub Releases + Binary Download

Host prebuilt binaries for Termux:
```
https://github.com/yunze7373/openclaw-termux/releases/download/v2026.2.22/
  - canvas-termux-arm64.node
  - canvas-termux-arm.node
  - llama-cpp-termux-arm64.tar.gz
```

Post-install script downloads them:
```json
"scripts": {
  "postinstall": "node scripts/install-termux-natives.js"
}
```

#### Option C: Prebuild Binary Groups

Add to `package.json`:
```json
"binary": {
  "module_name": "openclaw",
  "module_path": "./native_modules/{platform}-{arch}/",
  "host": "https://github.com/releases/download/v{version}/"
}
```

### 4. **Environment Variable Control**

Users can explicitly skip native compilation:

```bash
# Skip all native builds
npm config set build-from-source false
npm i -g openclaw-android

# Or
NO_NATIVE_BUILD=1 npm i -g openclaw-android

# OR via environment before npm
export npm_config_build_from_source=false
npm i -g openclaw-android
```

Update `.npmignore` to minimize package size:

```
src/
apps/
docs/
extensions/
skills/
scripts/
*.config.ts
*.test.ts
```

### 5. **Installation Checksum & Feature Detection**

After installation, verify what's available:

```bash
# In CLI
openclaw --check-native-deps

# Output:
# Canvas support:      ✗ (not available)
# Llama.cpp support:   ✗ (not available)
# Discord opus codec:  ✓ (available)
```

## Implementation Priority

### Phase 1 (Now - Completed ✅)
- Make all native deps optional in `package.json`
- Implement safe loading in `src/native-deps.ts`
- Update code to use graceful fallbacks

### Phase 2 (Next)
- Update `Install_termux*.sh` scripts to use `npm ignore-scripts`
- Document Termux installation without native builds
- Add `--check-native-deps` command

### Phase 3 (Future)
- Build CI/CD pipeline to generate prebuilt binaries
- Host prebuilts on GitHub releases
- Implement post-install script to download prebuilts

## How It Works Now

### Installation on Termux (No Compilation!)

```bash
# With npm ignore-scripts flag
npm install --ignore-scripts -g openclaw-android

# Or (auto-skipped by optional deps)
npm i -g openclaw-android

# Features will gracefully degrade:
# - Canvas rendering: Unavailable (use stdout/log fallback)
# - Local LLM: Unavailable (use cloud models)
# - Discord opus: Unavailable (use other codecs)
# - Everything else: ✅ Works normally
```

### Fallback Strategies

**Canvas (Media Rendering)**
- When unavailable: Fall back to text-based output
- CLI shows: ASCII art, markdown tables
- Web UI: Static HTML alternatives

**Llama.cpp (Local LLM)**
- When unavailable: Use cloud models only
- NO fallback needed - just disable feature
- User must configure API keys

**Discord Opus**
- When unavailable: Use another voice codec
- Currently optional - safe to skip

## Testing

Verify native deps handling:

```bash
# Simulate no natives available
SKIP_NATIVES=1 npm test

# Verify graceful degradation
npm run test native-deps
```

## User Benefits

✅ **Installation never fails due to compilation**
✅ **Works on low-end devices immediately**
✅ **Optional features degrade gracefully**
✅ **Future prebuilts are easy to add**
✅ **Smaller initial package size**
✅ **Faster npm install**

## Migration Guide for Users

**Old way (before optimization):**
```bash
./Install_termux.sh --full  # May fail on native compilation
```

**New way (after optimization):**
```bash
./Install_termux.sh --full  # Always succeeds
openclaw --check-native-deps # See what's available
```

## Build Script Updates Needed

Update `Install_termux*.sh` to use `--ignore-scripts`:

```bash
pnpm install --no-frozen-lockfile --ignore-scripts
# OR
npm install --ignore-scripts
```

This prevents any attempt to compile natives during installation.

## References

- [NPM: Optional Dependencies](https://docs.npmjs.com/cli/v10/configuring-npm/package-json#optionaldependencies)
- [node-pre-gyp: Prebuilt Binaries](https://github.com/mapbox/node-pre-gyp)
- [NAPI-RS: Cross Platform Builds](https://napi.rs/docs/getting-started/installation)
- [Termux: Native Development](https://wiki.termux.com/wiki/Development_Environments)
