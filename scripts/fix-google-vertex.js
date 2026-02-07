import fs from 'node:fs';

const configPath = '/data/data/com.termux/files/home/.moltbot/moltbot.json';

try {
  const raw = fs.readFileSync(configPath, 'utf8');
  const config = JSON.parse(raw);

  if (config.models && config.models.providers && config.models.providers.google) {
    const google = config.models.providers.google;

    // Use Vertex AI specific endpoint with publishers/google prefix
    // to match the Vertex AI path structure: v1/publishers/google/models/...
    google.baseUrl = "https://aiplatform.googleapis.com/v1/publishers/google";
    google.api = "google-generative-ai";

    if (google.models && Array.isArray(google.models)) {
      google.models.forEach(model => {
        // Enforce schema-valid input types (only "text" and "image" are currently allowed)
        if (Array.isArray(model.input)) {
          model.input = model.input.filter(type => type === "text" || type === "image");
        }
      });
    }
  }

  fs.writeFileSync(configPath, JSON.stringify(config, null, 2));
  console.log("Moltbot configuration updated for Vertex AI endpoint.");

} catch (error) {
  console.error("Failed to update config:", error);
  process.exit(1);
}
