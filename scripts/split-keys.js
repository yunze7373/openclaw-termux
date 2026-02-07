import fs from 'node:fs';

const configPath = '/data/data/com.termux/files/home/.moltbot/moltbot.json';

try {
  const raw = fs.readFileSync(configPath, 'utf8');
  const config = JSON.parse(raw);

  // 1. Setup Env Vars
  if (!config.env) config.env = { vars: {} };
  
  // Use existing key as default for Gemini (AI Studio)
  const currentKey = config.env.vars.GEMINI_API_KEY || "";
  
  // Initialize VERTEX_API_KEY if not exists
  if (!config.env.vars.VERTEX_API_KEY) {
      config.env.vars.VERTEX_API_KEY = "YOUR_VERTEX_KEY_HERE";
  }
  
  // 2. Configure 'gemini' (AI Studio) to use GEMINI_API_KEY
  if (config.models.providers.gemini) {
      // We set the value directly from env var reference (if supported) or just copy the value.
      // Since Moltbot loads env vars into process.env, and we want to allow user to edit env.vars to change it,
      // we will set the apiKey field to the specific value currently in that var.
      // NOTE: User must update env.vars, run reload, and this script updates the provider config? 
      // Actually, simplest is to let user edit env.vars, and we bind provider to it.
      // But Moltbot json doesn't support "${VAR}" syntax natively in json.
      // So we have to instruct user to fill correct key in env.vars, AND we sync it here.
      
      config.models.providers.gemini.apiKey = config.env.vars.GEMINI_API_KEY;
  }

  // 3. Configure 'google' (Vertex AI) to use VERTEX_API_KEY
  if (config.models.providers.google) {
      const vKey = config.env.vars.VERTEX_API_KEY;
      config.models.providers.google.apiKey = vKey;
      // Sync header for Vertex
      config.models.providers.google.headers = {
          "X-Goog-Api-Key": vKey
      };
  }

  fs.writeFileSync(configPath, JSON.stringify(config, null, 2));
  console.log("Config split: 'GEMINI_API_KEY' for AI Studio, 'VERTEX_API_KEY' for Vertex AI.");
  console.log("Please edit ~/.moltbot/moltbot.json to fill in 'VERTEX_API_KEY'.");

} catch (error) {
  console.error("Failed to split keys:", error);
  process.exit(1);
}
