# OpenClaw on Termux (Android)

Run OpenClaw on Android devices using Termux.

## Prerequisites

- Android device (ARM64 recommended)
- [Termux](https://f-droid.org/packages/com.termux/) installed from F-Droid (not Play Store)
- At least 2GB free storage

## Quick Install

```bash
# Clone the repository
git clone https://github.com/yunze7373/openclaw-termux.git ~/openclaw-termux
cd ~/openclaw-termux

# Run the deployment script
./Install_termux.sh --full
```

## Manual Installation

### 1. Install Dependencies

```bash
pkg update && pkg upgrade -y
pkg install -y nodejs-lts git openssh curl wget jq

# Install pnpm
npm install -g pnpm

# Optional: pm2 for process management
npm install -g pm2
```

### 2. Set Environment Variables

Add to `~/.bashrc` or `~/.zshrc`:

```bash
# OpenClaw environment
export OPENCLAW_PATH_BOOTSTRAPPED=1
export NODE_OPTIONS="--max-old-space-size=4096"

# Termux paths
export PATH="$PREFIX/bin:$HOME/.local/bin:$PATH"
export TMPDIR="$PREFIX/tmp"
export SSL_CERT_FILE="$PREFIX/etc/tls/cert.pem"
export NODE_EXTRA_CA_CERTS="$PREFIX/etc/tls/cert.pem"

# pnpm
export PNPM_HOME="$HOME/.local/share/pnpm"
export PATH="$PNPM_HOME:$PATH"
```

Reload: `source ~/.bashrc`

### 3. Build the Project

```bash
cd ~/openclaw-termux

# Install dependencies (skip problematic native modules)
pnpm install

# Build
pnpm build

# Optional: Build web UI
pnpm ui:build
```

### 4. Create CLI Entry Points

```bash
ln -sf ~/openclaw-termux/openclaw.mjs $PREFIX/bin/moltbot
ln -sf ~/openclaw-termux/openclaw.mjs $PREFIX/bin/openclaw
```

### 5. Start the Gateway

```bash
# Interactive start
moltbot gateway start

# Or with pm2 (background)
pm2 start ~/openclaw-termux/openclaw.mjs --name moltbot -- gateway start
pm2 save
```

## Known Issues & Workarounds

### Native Module Compilation

Some npm packages with native bindings don't have Android ARM64 prebuilts:

- **sharp**: Use npm mirror for prebuilt binaries
- **oxfmt**: Disable git hooks (no Android support)
- **node-pty**: May require manual compilation

Add to `.npmrc`:

```ini
sharp_binary_host=https://npmmirror.com/mirrors/sharp-libvips
sharp_libvips_binary_host=https://npmmirror.com/mirrors/sharp-libvips
```

### Log Directory

OpenClaw automatically detects Termux and uses `$PREFIX/tmp/openclaw` instead of `/tmp/openclaw`.

### SSL Certificates

If you see SSL errors, ensure the certificate path is set:

```bash
export SSL_CERT_FILE="$PREFIX/etc/tls/cert.pem"
export NODE_EXTRA_CA_CERTS="$PREFIX/etc/tls/cert.pem"
```

### Process Management

Termux doesn't support systemd. Use pm2 instead:

```bash
# Start
pm2 start moltbot

# Stop
pm2 stop moltbot

# Logs
pm2 logs moltbot

# Auto-start on boot (requires Termux:Boot)
pm2 startup
```

## Updating

```bash
cd ~/openclaw-termux
./Install_termux.sh --update
```

## Troubleshooting

### Command not found: moltbot

Ensure the symlink exists and PATH is correct:

```bash
ls -la $PREFIX/bin/moltbot
echo $PATH
```

### Build failures

Try clearing node_modules and rebuilding:

```bash
rm -rf node_modules pnpm-lock.yaml
pnpm install
pnpm build
```

### Gateway won't start

Check logs:

```bash
moltbot gateway status
cat $PREFIX/tmp/openclaw/openclaw-$(date +%Y-%m-%d).log
```

## Performance Tips

1. **Disable unnecessary plugins** in config to reduce memory usage
2. **Use a swap file** if you have limited RAM:
   ```bash
   # Requires root
   dd if=/dev/zero of=/data/swapfile bs=1M count=1024
   mkswap /data/swapfile
   swapon /data/swapfile
   ```
3. **Run in background** with pm2 and `--max-memory-restart 500M`

## See Also

- [Raspberry Pi Installation](./raspberry-pi.md)
- [Linux Installation](./linux.md)
- [Configuration Guide](../configuration/index.md)
