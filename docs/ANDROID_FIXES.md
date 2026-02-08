# OpenClaw on Android (Termux) - Compatibility Fixes

This document tracks the compatibility layers added to run OpenClaw natively on Android via Termux.

## 1. Process Management (PM2)
- **Issue**: OpenClaw defaults to `systemd` (Linux) or `launchd` (macOS), which are unavailable in Termux.
- **Fix**: 
  - Implemented `src/daemon/pm2.ts` to manage the Gateway process.
  - Updated `src/daemon/service.ts` to detect `android` platform and switch to PM2.
  - Added auto-install for PM2 (`npm install -g pm2`) if missing.

## 2. Dependency: matrix-sdk-crypto
- **Issue**: The `npm install` script for `@matrix-org/matrix-sdk-crypto-nodejs` checks `process.platform` and throws an error for `android`.
- **Fix**: 
  - Added `patches/@matrix-org__matrix-sdk-crypto-nodejs@0.4.0.patch`.
  - Maps `android` platform to `linux` (arm64 gnu) to satisfy the installer.
  - **Note**: Runtime may require `pkg install gcompat` if the binary uses glibc symbols (though often it works for basic crypto).

## 3. Dependency: sqlite-vec (Vector Search)
- **Issue**: The pre-built `sqlite-vec` binary is linked against `glibc`. Termux uses `Bionic libc`. Loading it causes a crash or "vector unavailable" error.
- **Fix**: Compile from source locally.
- **Usage**: Run the helper script:
  ```bash
  bash scripts/fix-sqlite-vec.sh
  ```
  This will:
  1. Install build tools (`rust`, `clang`, `make`, etc.).
  2. Clone `sqlite-vec` and build `vec0.so`.
  3. Replace the binary in `node_modules`.
  4. Patch the JS loader to accept `android-arm64`.

## 4. Setup Wizard (Onboard)
- **Issue**: The wizard assumes standard Linux/macOS paths and tools (Homebrew).
- **Fix**:
  - Hides "Homebrew recommended" prompt on Termux.
  - Defaults to `npm` for skill installation.
  - Maps `brew install` commands to `pkg install -y`.
  - Auto-installs `uv` and `go` via `pkg` if needed.

## 5. UI Build
- **Note**: `pnpm build` does not include the UI.
- **Command**: Run `pnpm ui:build` to compile the Control UI assets.
