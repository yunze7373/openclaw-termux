import fs from 'node:fs';

const configPath = '/data/data/com.termux/files/home/.moltbot/moltbot.json';
const raw = fs.readFileSync(configPath, 'utf8');
const config = JSON.parse(raw);

const apiKey = config.env?.vars?.VERTEX_API_KEY;
const baseUrl = "https://aiplatform.googleapis.com/v1/publishers/google";
const modelId = "gemini-3-pro-preview";

// Test Query Param Auth (User's CURL style)
const url = `${baseUrl}/models/${modelId}:streamGenerateContent?key=${apiKey}`;

console.log(`ℹ️  Testing Vertex AI with Query Param Auth`);
console.log(`📍 URL: ${url.replace(apiKey, "HIDDEN_KEY")}`);

const payload = {
  contents: [{
    role: "user",
    parts: [{ text: "Hello" }]
  }]
};

async function testStream() {
  try {
    const response = await fetch(url, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify(payload)
    });

    if (!response.ok) {
      console.error(`❌ Failed: ${response.status}`);
      console.error(await response.text());
    } else {
      console.log(`✅ Success! Status: ${response.status}`);
    }
  } catch (e) {
    console.error("Error:", e);
  }
}

testStream();
