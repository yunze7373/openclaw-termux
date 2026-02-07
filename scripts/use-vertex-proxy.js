import fs from 'node:fs';

const configPath = '/data/data/com.termux/files/home/.moltbot/moltbot.json';

try {
  const raw = fs.readFileSync(configPath, 'utf8');
  const config = JSON.parse(raw);

  if (config.models?.providers?.vertex) {
    const vertex = config.models.providers.vertex;
    
    // Point to local proxy
    vertex.baseUrl = "http://127.0.0.1:19000";
    
    // Remove auth overrides (Proxy handles key injection)
    delete vertex.headers;
    delete vertex.auth;
    // We can keep apiKey field just for reference or UI, but proxy reads env.vars directly.
    
    // Clean up model-level headers if any
    if (vertex.models) {
        vertex.models.forEach(m => {
            if (m.headers) delete m.headers;
        });
    }
  }

  fs.writeFileSync(configPath, JSON.stringify(config, null, 2));
  console.log("Config updated to use Local Vertex Proxy.");

} catch (error) {
  console.error("Failed to update config:", error);
  process.exit(1);
}
