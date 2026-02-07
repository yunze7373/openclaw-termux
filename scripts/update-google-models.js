import fs from 'node:fs';

const configPath = '/data/data/com.termux/files/home/.moltbot/moltbot.json';

try {
  const raw = fs.readFileSync(configPath, 'utf8');
  const config = JSON.parse(raw);

  // Preserve existing key if user already filled it
  const existingGoogle = config.models.providers.google || {};
  const currentKey = existingGoogle.apiKey;
  const newKey = (currentKey && currentKey.length > 10 && currentKey !== "YOUR_GOOGLE_API_KEY_HERE") 
                 ? currentKey 
                 : "YOUR_GOOGLE_API_KEY_HERE";

  // Update Google Provider with latest 2026 models
  config.models.providers.google = {
    "apiKey": newKey,
    "api": "google-generative-ai",
    "models": [
      {
        "id": "gemini-3-flash-preview",
        "name": "Gemini 3 Flash (Preview)",
        "contextWindow": 2000000,
        "maxTokens": 8192,
        "input": ["text", "image", "audio", "video"]
      },
      {
        "id": "gemini-2.5-pro",
        "name": "Gemini 2.5 Pro",
        "contextWindow": 2000000,
        "maxTokens": 8192,
        "input": ["text", "image", "audio", "video"]
      },
      {
        "id": "gemini-2.5-flash",
        "name": "Gemini 2.5 Flash",
        "contextWindow": 1000000,
        "maxTokens": 8192,
        "input": ["text", "image", "audio", "video"]
      },
      {
        "id": "gemini-2.5-flash-lite",
        "name": "Gemini 2.5 Flash-Lite",
        "contextWindow": 1000000,
        "maxTokens": 8192,
        "input": ["text", "image", "audio", "video"]
      }
    ]
  };

  fs.writeFileSync(configPath, JSON.stringify(config, null, 2));
  console.log("Moltbot configuration updated with Gemini 3 and 2.5 models.");

} catch (error) {
  console.error("Failed to update config:", error);
  process.exit(1);
}
