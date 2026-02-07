import fs from 'node:fs';

const configPath = '/data/data/com.termux/files/home/.moltbot/moltbot.json';

try {
  const raw = fs.readFileSync(configPath, 'utf8');
  const config = JSON.parse(raw);

  if (config.models?.providers?.google) {
    const google = config.models.providers.google;
    
    // Force auth mode to 'api-key' to guide the library
    google.auth = "api-key";
    
    // Ensure apiKey field is populated directly (not just headers)
    const key = config.env?.vars?.["VERTEX_API_KEY"];
    if (key) {
        google.apiKey = key;
    }
  }

  fs.writeFileSync(configPath, JSON.stringify(config, null, 2));
  console.log("Config updated: Added auth='api-key' flag.");

} catch (error) {
  console.error("Failed to update config:", error);
  process.exit(1);
}
