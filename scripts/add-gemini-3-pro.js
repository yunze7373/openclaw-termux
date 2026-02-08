import fs from 'node:fs';

const configPath = '/data/data/com.termux/files/home/.moltbot/moltbot.json';

try {
  const raw = fs.readFileSync(configPath, 'utf8');
  const config = JSON.parse(raw);

  if (config.models && config.models.providers && config.models.providers.google) {
    const google = config.models.providers.google;

    // Add gemini-3-pro-preview to the beginning of the list
    const flagshipModel = {
      "id": "gemini-3-pro-preview",
      "name": "Gemini 3 Pro (Preview)",
      "contextWindow": 1000000,
      "maxTokens": 8192,
      "input": ["text", "image"]
    };

    // Prevent duplicates
    const exists = google.models.some(m => m.id === flagshipModel.id);
    if (!exists) {
      google.models.unshift(flagshipModel);
    }
  }

  fs.writeFileSync(configPath, JSON.stringify(config, null, 2));
  console.log("Moltbot configuration updated: Added Gemini 3 Pro Preview.");

} catch (error) {
  console.error("Failed to update config:", error);
  process.exit(1);
}
