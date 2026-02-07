import fs from 'node:fs';

const configPath = '/data/data/com.termux/files/home/.moltbot/moltbot.json';

try {
  const raw = fs.readFileSync(configPath, 'utf8');
  const config = JSON.parse(raw);

  if (config.agents?.defaults?.model) {
    const modelConfig = config.agents.defaults.model;
    
    // Fix primary model string (trim space)
    if (modelConfig.primary) {
        modelConfig.primary = modelConfig.primary.trim();
        // Also ensure lowercase provider prefix if it matches our provider
        if (modelConfig.primary.toLowerCase().startsWith("vertex/")) {
             const parts = modelConfig.primary.split('/');
             modelConfig.primary = "vertex/" + parts[1];
        }
    }

    // Fix fallbacks
    if (modelConfig.fallbacks && Array.isArray(modelConfig.fallbacks)) {
        modelConfig.fallbacks = modelConfig.fallbacks.map(f => {
            let fixed = f.trim();
            if (fixed.toLowerCase().startsWith("vertex/")) {
                const parts = fixed.split('/');
                fixed = "vertex/" + parts[1];
            }
            return fixed;
        });
    }
  }

  fs.writeFileSync(configPath, JSON.stringify(config, null, 2));
  console.log("Config fixed: Trimmed model IDs and normalized provider case.");

} catch (error) {
  console.error("Failed to fix config:", error);
  process.exit(1);
}
