import fs from 'node:fs';

const configPath = '/data/data/com.termux/files/home/.moltbot/moltbot.json';

try {
  const raw = fs.readFileSync(configPath, 'utf8');
  const config = JSON.parse(raw);

  const key = config.env?.vars?.["GEMINI_API_KEY"] || "YOUR_API_KEY";

  // 1. Ensure 'google' is Vertex AI (Express Mode)
  // This provider is already set up, we just ensure settings are correct
  config.models.providers.google = {
    ...config.models.providers.google,
    baseUrl: "https://aiplatform.googleapis.com/v1/publishers/google",
    api: "google-generative-ai",
    apiKey: key,
    headers: {
        "X-Goog-Api-Key": key
    },
    // Keep existing models list
    models: config.models.providers.google.models || []
  };

  // 2. Create 'gemini' as Standard AI Studio
  // Copy models from google provider but use standard endpoint
  const standardModels = JSON.parse(JSON.stringify(config.models.providers.google.models));
  
  config.models.providers.gemini = {
    baseUrl: "https://generativelanguage.googleapis.com/v1beta",
    api: "google-generative-ai",
    apiKey: key,
    // Standard API doesn't usually need the header, but it doesn't hurt.
    // However, clean config is better. It uses query param by default.
    models: standardModels
  };

  // 3. Register 'gemini' models in Agent Defaults so they appear in UI
  if (!config.agents.defaults.models) config.agents.defaults.models = {};
  
  // Register corresponding entries like 'gemini/gemini-2.0-flash'
  standardModels.forEach(m => {
      const entryKey = `gemini/${m.id}`;
      if (!config.agents.defaults.models[entryKey]) {
          config.agents.defaults.models[entryKey] = {};
      }
  });

  fs.writeFileSync(configPath, JSON.stringify(config, null, 2));
  console.log("Config updated: Separate 'google' (Vertex) and 'gemini' (AI Studio) providers created.");

} catch (error) {
  console.error("Failed to split providers:", error);
  process.exit(1);
}
