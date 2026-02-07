import fs from 'node:fs';

const configPath = '/data/data/com.termux/files/home/.moltbot/moltbot.json';

try {
  const raw = fs.readFileSync(configPath, 'utf8');
  const config = JSON.parse(raw);

  // 1. 获取当前的 Key (优先从 google.apiKey 或 headers 中提取)
  let key = config.models?.providers?.google?.apiKey;
  if (!key || key === "YOUR_GOOGLE_API_KEY_HERE") {
    key = config.models?.providers?.google?.headers?.["X-Goog-Api-Key"];
  }

  if (key && key !== "YOUR_GOOGLE_API_KEY_HERE") {
    // 2. 将 Key 存入通用的 env.vars 中，变量名为 GEMINI_API_KEY
    if (!config.env) config.env = { vars: {} };
    if (!config.env.vars) config.env.vars = {};
    config.env.vars["GEMINI_API_KEY"] = key;

    // 3. 清理 google provider 块，使其恢复简洁和通用
    if (config.models?.providers?.google) {
      const google = config.models.providers.google;
      // 移除手动设置的 Key、Header 和特定端点，让系统自动处理
      delete google.apiKey;
      delete google.headers;
      delete google.baseUrl;
      // 确保 api 类型正确
      google.api = "google-generative-ai";
    }

    fs.writeFileSync(configPath, JSON.stringify(config, null, 2));
    console.log("Moltbot 配置已简化：Key 已移至 env.vars，删除了重复的 headers 和 baseUrl。");
  } else {
    console.log("未检测到有效的 Key，未进行修改。");
  }

} catch (error) {
  console.error("修复配置失败:", error);
  process.exit(1);
}
