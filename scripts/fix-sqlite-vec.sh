#!/bin/bash
# scripts/fix-sqlite-vec.sh
# Compiles sqlite-vec from source to fix "vector unavailable" on Termux.

set -e

echo "🦞 OpenClaw: sqlite-vec Termux Patcher"
echo "========================================"

if [ -z "$TERMUX_VERSION" ]; then
  echo "⚠️  This script is intended for Termux environment."
  read -p "Continue anyway? [y/N] " -n 1 -r
  echo
  if [[ ! $REPLY =~ ^[Yy]$ ]]; then exit 1; fi
fi

# 1. Install Build Dependencies
echo "📦 [1/4] Installing build dependencies..."
# sqlite-vec is C, so we need clang/gcc and make
pkg install -y clang git make sqlite pkg-config gettext binutils

# 2. Locate node_modules package
echo "🔍 [2/4] Locating sqlite-vec package..."
PKG_PATH=$(find node_modules -type d -name "sqlite-vec" | grep -v ".pnpm" | head -n 1)

if [ -z "$PKG_PATH" ]; then
  PKG_PATH=$(find node_modules -type d -name "sqlite-vec" | head -n 1)
fi

if [ -z "$PKG_PATH" ]; then
  echo "   ❌ sqlite-vec package not found, please run 'pnpm install' first"
  exit 1
fi
echo "   ✓ Found: $PKG_PATH"

# 3. Clone and Compile
TEMP_DIR=$(mktemp -d)
echo "🏗️  [3/4] Building sqlite-vec from source (C)..."
echo "   Work dir: $TEMP_DIR"

git clone --depth 1 https://github.com/asg017/sqlite-vec "$TEMP_DIR"
cd "$TEMP_DIR"

# Build shared library using Makefile (quiet mode)
echo "   Compiling..."
# Termux uses clang as cc, use CFLAGS=-w to suppress warnings
export CC=clang
export CFLAGS="-w"
make loadable > /dev/null 2>&1 || {
    echo "   ❌ Compilation failed, showing detailed errors..."
    make loadable
    exit 1
}

# Locate output
SO_FILE=$(find dist -name "vec0.so" | head -n 1)
if [ -z "$SO_FILE" ]; then
  # Fallback search
  SO_FILE=$(find . -name "*.so" | head -n 1)
fi

if [ ! -f "$SO_FILE" ]; then
  echo "   ❌ Build failed, shared library file not found"
  exit 1
fi
echo "   ✓ Compilation complete: $SO_FILE"

# 4. Install and Patch
echo "🩹 [4/4] Installing and patching..."

# Copy binary
cp "$SO_FILE" "$OLDPWD/$PKG_PATH/vec0.so"
echo "   Copied vec0.so to package."

# Patch index files to accept android-arm64
cd "$OLDPWD/$PKG_PATH"

for EXT in js cjs mjs; do
  if [ -f "index.$EXT" ]; then
    echo "   Patching index.$EXT..."
    
    # Force patch for 0.1.7+: directly make getLoadablePath return vec0.so in current directory
    # Ignore platform checks, ignore package name concatenation
    
    if [[ "$EXT" == "mjs" ]]; then
      # ESM: Use fileURLToPath + import.meta.url
      # We replace the beginning of the function body
      sed -i '/function getLoadablePath() {/a \  return join(fileURLToPath(new URL(".", import.meta.url)), "vec0.so");' "index.$EXT"
    else
      # CJS: Use __dirname
      sed -i '/function getLoadablePath() {/a \  return join(__dirname, "vec0.so");' "index.$EXT"
    fi
    
    # Legacy version compatibility (switch case pattern)
    sed -i "s/case 'linux':/case 'linux': case 'android':/g" "index.$EXT"
    sed -i "s/case 'darwin':/case 'darwin': case 'android':/g" "index.$EXT"
  fi
done

# Cleanup
cd /
rm -rf "$TEMP_DIR"

echo "✅ Success! sqlite-vec has been compiled and patched for Termux."
echo "   Please restart OpenClaw: openclaw gateway restart"
