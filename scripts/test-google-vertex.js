import fs from 'node:fs';

// 1. Read configuration
const configPath = '/data/data/com.termux/files/home/.moltbot/moltbot.json';
const raw = fs.readFileSync(configPath, 'utf8');
const config = JSON.parse(raw);

const googleConfig = config.models?.providers?.google;

if (!googleConfig) {
  console.error("❌ No 'google' provider found in moltbot.json");
  process.exit(1);
}

const apiKey = googleConfig.apiKey;
const baseUrl = googleConfig.baseUrl; 

if (!apiKey || apiKey === "YOUR_GOOGLE_API_KEY_HERE") {
  console.error("❌ API Key is missing or default placeholder.");
  process.exit(1);
}

// 2. Prepare Request (Generate Content)
const modelId = "gemini-3-pro-preview";
const url = `${baseUrl}/models/${modelId}:generateContent?key=${apiKey}`;

console.log(`ℹ️  Testing Gemini 3 Pro Preview Availability`);
console.log(`📍 Endpoint: ${url.replace(apiKey, "HIDDEN_KEY")}`);
console.log(`🤖 Model:    ${modelId}`);

const payload = {
  contents: [{
    role: "user",
    parts: [{ text: "Hello! If you are Gemini 3 Pro, please confirm your identity briefly." }]
  }]
};

// 3. Send Request
async function testApi() {
  try {
    const response = await fetch(url, {
      method: "POST",
      headers: {
        "Content-Type": "application/json"
      },
      body: JSON.stringify(payload)
    });

    if (!response.ok) {
      const errorText = await response.text();
      console.error(`
❌ Model Access Failed!`);
      console.error(`Status: ${response.status} ${response.statusText}`);
      console.error(`Response: ${errorText}`);
      process.exit(1);
    }

    const data = await response.json();
    
    if (data.candidates && data.candidates[0]?.content?.parts?.[0]?.text) {
      console.log(`
✅ Success! ${modelId} is ACTIVE:`);
      console.log("---------------------------------------------------");
      console.log(data.candidates[0].content.parts[0].text.trim());
      console.log("---------------------------------------------------");
    } else {
      console.log(`
⚠️  Request succeeded but response format was unexpected:`);
      console.log(JSON.stringify(data, null, 2));
    }

  } catch (error) {
    console.error(`
❌ Network/Script Error:`, error);
  }
}

testApi();