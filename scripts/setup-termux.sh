#!/bin/bash
# scripts/setup-termux.sh
# One-click setup for OpenClaw on Termux (Android).
# Handles dependencies, building, patching, and onboarding.

set -e

echo "🦞 OpenClaw: Termux All-in-One Setup"
echo "===================================="

# 1. System Dependencies
echo "📦 [1/5] Checking system dependencies..."
pkg update -y
# Core deps for building and running
PACKAGES="git nodejs-lts rust clang make python pkg-config gettext binutils tur-repo"
# Ensure tur-repo is installed for some extras if needed, though standard repo usually suffices
pkg install -y $PACKAGES

# Check for pm2
if ! command -v pm2 &> /dev/null; then
    echo "   Installing pm2..."
    npm install -g pm2
fi

# Check for pnpm
if ! command -v pnpm &> /dev/null; then
    echo "   Installing pnpm..."
    npm install -g pnpm
fi

# 2. Project Dependencies
echo "📥 [2/5] Installing project dependencies..."
# Use --ignore-scripts to avoid matrix-crypto failure (patched later or ignored)
# But we added a patch in package.json, so standard install might work?
# Just in case, we stick to --ignore-scripts for safety on clean install, 
# but pnpm patch requires scripts? No, patch is applied by pnpm.
# Let's try standard install first.
echo "   Running pnpm install..."
pnpm install || {
    echo "⚠️  Standard install failed. Retrying with --ignore-scripts..."
    pnpm install --ignore-scripts
}

# 3. Build Project
echo "🏗️  [3/5] Building OpenClaw..."
echo "   Building core..."
pnpm build
echo "   Building UI..."
pnpm ui:build

# 4. Patch sqlite-vec (Vector Database)
echo "🔧 [4/5] Patching sqlite-vec for Termux..."
if [ -f "scripts/fix-sqlite-vec.sh" ]; then
    bash scripts/fix-sqlite-vec.sh
else
    echo "⚠️  scripts/fix-sqlite-vec.sh not found. Skipping vector patch."
fi

# 5. Launch Onboard
echo "🚀 [5/5] Setup complete! Launching onboard wizard..."
echo "   (Press Ctrl+C to skip)"
sleep 2

# We use the local bin to ensure we use the built version
./openclaw.mjs onboard --install-daemon

echo
echo "🎉 All done! You can manage OpenClaw with:"
echo "   openclaw gateway status"
