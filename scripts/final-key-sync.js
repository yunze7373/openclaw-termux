import fs from 'node:fs';

const configPath = '/data/data/com.termux/files/home/.moltbot/moltbot.json';

try {
  const raw = fs.readFileSync(configPath, 'utf8');
  const config = JSON.parse(raw);

  const vertexKey = config.env?.vars?.VERTEX_API_KEY;
  const geminiKey = config.env?.vars?.GEMINI_API_KEY;

  console.log("Syncing correctly aligned keys:");
  console.log(`- Vertex (AQ...): Using VERTEX_API_KEY`);
  console.log(`- Gemini (AIza...): Using GEMINI_API_KEY`);

  // 1. Sync Vertex (AQ.Ab8RN...)
  if (config.models.providers.vertex) {
      config.models.providers.vertex.apiKey = vertexKey;
      config.models.providers.vertex.headers = {
          "X-Goog-Api-Key": vertexKey
      };
  }

  // 2. Sync Gemini (AIzaSyB9...)
  if (config.models.providers.gemini) {
      config.models.providers.gemini.apiKey = geminiKey;
      delete config.models.providers.gemini.headers;
  }

  fs.writeFileSync(configPath, JSON.stringify(config, null, 2));
  console.log("Mapping complete.");

} catch (error) {
  console.error("Sync failed:", error);
}
