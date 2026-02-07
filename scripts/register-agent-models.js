import fs from 'node:fs';

const configPath = '/data/data/com.termux/files/home/.moltbot/moltbot.json';

try {
  const raw = fs.readFileSync(configPath, 'utf8');
  const config = JSON.parse(raw);

  // Ensure path exists
  if (!config.agents) config.agents = {};
  if (!config.agents.defaults) config.agents.defaults = {};
  if (!config.agents.defaults.models) config.agents.defaults.models = {};

  const models = config.agents.defaults.models;

  // The list of models we want to expose in the UI (provider/model-id)
  const modelsToRegister = [
    "google/gemini-3-pro-preview",
    "google/gemini-2.5-pro",
    "google/gemini-2.5-flash",
    "google/gemini-2.5-flash-lite"
  ];

  modelsToRegister.forEach(key => {
    // Only add if not already present to preserve any existing custom settings
    if (!models[key]) {
      models[key] = {}; 
    }
  });

  fs.writeFileSync(configPath, JSON.stringify(config, null, 2));
  console.log("Successfully registered Vertex AI models in agent defaults.");

} catch (error) {
  console.error("Failed to update config:", error);
  process.exit(1);
}
