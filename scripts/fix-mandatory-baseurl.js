import fs from 'node:fs';

const configPath = '/data/data/com.termux/files/home/.moltbot/moltbot.json';

try {
  const raw = fs.readFileSync(configPath, 'utf8');
  const config = JSON.parse(raw);

  if (!config.models) config.models = { providers: {} };
  if (!config.models.providers) config.models.providers = {};
  
  if (!config.models.providers.google) {
      config.models.providers.google = { models: [] };
  }

  const google = config.models.providers.google;
  const key = config.env?.vars?.["GEMINI_API_KEY"];

  // 1. Mandatory baseUrl
  google.baseUrl = "https://aiplatform.googleapis.com/v1/publishers/google";
  google.api = "google-generative-ai";

  // 2. Auth Sync
  if (key) {
      google.apiKey = key;
      google.headers = {
          "X-Goog-Api-Key": key
      };
  }

  fs.writeFileSync(configPath, JSON.stringify(config, null, 2));
  console.log("Moltbot config fixed: restored mandatory baseUrl and synced credentials.");

} catch (error) {
  console.error("Failed to fix config:", error);
  process.exit(1);
}
