import fs from 'node:fs';

const configPath = '/data/data/com.termux/files/home/.moltbot/moltbot.json';

try {
  const raw = fs.readFileSync(configPath, 'utf8');
  const config = JSON.parse(raw);

  if (config.models && config.models.providers && config.models.providers.google) {
    const google = config.models.providers.google;
    const key = google.apiKey;

    if (key) {
        // Vertex AI Express Mode accepts Key via Header, which is more reliable 
        // than relying on library-specific query param injection when using a custom baseUrl.
        google.headers = {
            "X-Goog-Api-Key": key
        };
        console.log("Added X-Goog-Api-Key header to Google provider config.");
    }
  }

  fs.writeFileSync(configPath, JSON.stringify(config, null, 2));
  console.log("Config updated.");

} catch (error) {
  console.error("Failed to update config:", error);
  process.exit(1);
}
