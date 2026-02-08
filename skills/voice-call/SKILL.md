---
name: voice-call
description: Start voice calls via the OpenClaw voice-call plugin.
metadata:
  {
    "openclaw":
      {
        "emoji": "📞",
        "skillKey": "voice-call",
        "requires": { "config": ["plugins.entries.voice-call.enabled"] },
      },
  }
---

# Voice Call

Use the voice-call plugin to start or inspect calls (Twilio, Telnyx, Plivo, or mock).

## CLI

```bash
openclaw voicecall call --to "+15555550123" --message "Hello from OpenClaw"
openclaw voicecall status --call-id <id>
```

## Tool

Use `voice_call` for agent-initiated calls.

Actions:

- `initiate_call` (message, to?, mode?)
- `continue_call` (callId, message)
- `speak_to_user` (callId, message)
- `end_call` (callId)
- `get_status` (callId)

Notes:

- Requires the voice-call plugin to be enabled.
- Plugin config lives under `plugins.entries.voice-call.config`.
- Twilio config: `provider: "twilio"` + `twilio.accountSid/authToken` + `fromNumber`.
- Telnyx config: `provider: "telnyx"` + `telnyx.apiKey/connectionId` + `fromNumber`.
- Plivo config: `provider: "plivo"` + `plivo.authId/authToken` + `fromNumber`.
- Dev fallback: `provider: "mock"` (no network).

## Termux Setup (Webhook Exposure)

Voice calls require Twilio/Telnyx to reach your Termux instance via webhook. Since Termux is usually behind NAT/CGNAT, you must use a tunnel.

### Option A: Tailscale (Recommended)

Moltbot has built-in integration with Tailscale Funnel.

1. Install: `pkg install tailscale`
2. Start daemon (user-space): `tailscaled --tun=userspace-networking --socks5-server=localhost:1055 &`
3. Login: `tailscale up`
4. Enable funnel in Moltbot: `openclaw voicecall expose --enable`

### Option B: Cloudflare Tunnel

1. Install: `pkg install cloudflared`
2. Start tunnel: `cloudflared tunnel --url http://localhost:18789`
3. Copy the public URL and configure it in Twilio console (or update `baseUrl` in config).
