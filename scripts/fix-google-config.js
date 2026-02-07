import fs from 'node:fs';

const configPath = '/data/data/com.termux/files/home/.moltbot/moltbot.json';

try {
  const raw = fs.readFileSync(configPath, 'utf8');
  const config = JSON.parse(raw);

  if (config.models && config.models.providers && config.models.providers.google) {
    const google = config.models.providers.google;

    // 1. Fix missing baseUrl
    // For AI Studio (API Key), this is the standard endpoint.
    if (!google.baseUrl) {
      google.baseUrl = "https://generativelanguage.googleapis.com/v1beta";
    }

    // 2. Fix invalid input types
    // The schema likely only accepts "text" and "image" currently.
    if (google.models && Array.isArray(google.models)) {
      google.models.forEach(model => {
        if (Array.isArray(model.input)) {
          model.input = model.input.filter(type => type === "text" || type === "image");
        }
      });
    }
  }

  fs.writeFileSync(configPath, JSON.stringify(config, null, 2));
  console.log("Moltbot configuration fixed: added baseUrl and cleaned input types.");

} catch (error) {
  console.error("Failed to fix config:", error);
  process.exit(1);
}
