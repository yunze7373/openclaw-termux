import fs from 'node:fs';

const configPath = '/data/data/com.termux/files/home/.moltbot/moltbot.json';

try {
  const raw = fs.readFileSync(configPath, 'utf8');
  const config = JSON.parse(raw);

  // 1. Rename 'google' provider to 'vertex' to bypass hardcoded logic
  if (config.models?.providers?.google) {
    const googleConfig = config.models.providers.google;
    
    // Create new 'vertex' provider
    config.models.providers.vertex = {
        ...googleConfig,
        // Ensure headers are present
        headers: googleConfig.headers || { "X-Goog-Api-Key": config.env?.vars?.VERTEX_API_KEY }
    };
    
    // Remove old 'google' provider to avoid confusion (or keep it if you want)
    // Let's remove it to force usage of the new one
    delete config.models.providers.google;
  }

  // 2. Register new 'vertex/...' models in Agents Defaults
  if (config.models.providers.vertex) {
      const models = config.models.providers.vertex.models || [];
      models.forEach(m => {
          const oldKey = `google/${m.id}`;
          const newKey = `vertex/${m.id}`;
          
          // Remove old entry
          if (config.agents.defaults.models[oldKey]) {
              delete config.agents.defaults.models[oldKey];
          }
          // Add new entry
          if (!config.agents.defaults.models[newKey]) {
              config.agents.defaults.models[newKey] = {};
          }
      });
  }

  // 3. Update Primary Model
  if (config.agents.defaults.model.primary.startsWith("google/")) {
      config.agents.defaults.model.primary = config.agents.defaults.model.primary.replace("google/", "vertex/");
  }

  fs.writeFileSync(configPath, JSON.stringify(config, null, 2));
  console.log("Renamed provider to 'vertex' to bypass default logic.");

} catch (error) {
  console.error("Failed to rename provider:", error);
  process.exit(1);
}
