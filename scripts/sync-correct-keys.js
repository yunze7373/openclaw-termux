import fs from 'node:fs';

const configPath = '/data/data/com.termux/files/home/.moltbot/moltbot.json';

try {
  const raw = fs.readFileSync(configPath, 'utf8');
  const config = JSON.parse(raw);

  const vertexKey = config.env?.vars?.VERTEX_API_KEY;
  const geminiKey = config.env?.vars?.GEMINI_API_KEY;

  console.log("Current Keys in env.vars:");
  console.log(`- VERTEX_API_KEY: ${vertexKey ? vertexKey.substring(0, 8) + '...' : '(empty)'}`);
  console.log(`- GEMINI_API_KEY: ${geminiKey ? geminiKey.substring(0, 8) + '...' : '(empty)'}`);

  // 1. Sync Vertex Key to 'vertex' provider
  if (config.models.providers.vertex) {
      if (vertexKey && vertexKey !== "YOUR_VERTEX_KEY_HERE") {
          config.models.providers.vertex.apiKey = vertexKey;
          // Ensure Header uses the Vertex Key
          config.models.providers.vertex.headers = {
              "X-Goog-Api-Key": vertexKey
          };
          console.log("✅ Updated 'vertex' provider with VERTEX_API_KEY.");
      } else {
          console.warn("⚠️  VERTEX_API_KEY is empty or default. 'vertex' provider not updated.");
      }
  }

  // 2. Sync Gemini Key to 'gemini' provider
  if (config.models.providers.gemini) {
      if (geminiKey && geminiKey !== "YOUR_GEMINI_KEY_HERE") {
          config.models.providers.gemini.apiKey = geminiKey;
          // Gemini usually doesn't need header, but clean up just in case
          delete config.models.providers.gemini.headers; 
          console.log("✅ Updated 'gemini' provider with GEMINI_API_KEY.");
      } else {
          console.warn("⚠️  GEMINI_API_KEY is empty. 'gemini' provider not updated.");
      }
  }

  fs.writeFileSync(configPath, JSON.stringify(config, null, 2));
  console.log("Config sync complete. Please restart moltbot.");

} catch (error) {
  console.error("Failed to sync keys:", error);
}
