import fs from 'node:fs';

const configPath = '/data/data/com.termux/files/home/.moltbot/moltbot.json';

try {
  const raw = fs.readFileSync(configPath, 'utf8');
  const config = JSON.parse(raw);

  const key = config.env?.vars?.["VERTEX_API_KEY"];
  
  if (!key || key === "YOUR_VERTEX_KEY_HERE") {
      console.warn("⚠️  Warning: VERTEX_API_KEY seems unset or default. Please ensure it is filled in env.vars.");
  }

  if (config.models?.providers?.google) {
    const google = config.models.providers.google;
    
    // Ensure Key is correct
    // (If user updated env.vars, we want to make sure it propagates)
    if (key) {
        google.headers = { "X-Goog-Api-Key": key }; // Keep provider level
        
        // Push to model level
        if (google.models) {
            google.models.forEach(model => {
                if (!model.headers) model.headers = {};
                model.headers["X-Goog-Api-Key"] = key;
            });
        }
        console.log("Propagated VERTEX_API_KEY to model-level headers.");
    }
  }

  fs.writeFileSync(configPath, JSON.stringify(config, null, 2));
  console.log("Config updated.");

} catch (error) {
  console.error("Failed to update config:", error);
  process.exit(1);
}
