import fs from 'node:fs';

const configPath = '/data/data/com.termux/files/home/.moltbot/moltbot.json';
const raw = fs.readFileSync(configPath, 'utf8');
const config = JSON.parse(raw);
const providerConfig = config.models.providers.vertex || config.models.providers.google;

const apiKey = providerConfig.apiKey;
// Try v1beta
const baseUrl = "https://aiplatform.googleapis.com/v1/publishers/google"; 

console.log(`Debug: apiKey length = ${apiKey ? apiKey.length : 'undefined'}`);

const modelId = "gemini-2.5-flash-lite";
// Test streaming endpoint with HEADER auth
const url = `${baseUrl}/models/${modelId}:streamGenerateContent`; // No key in URL

console.log(`ℹ️  Testing Streaming Endpoint with Header Auth`);
console.log(`📍 URL: ${url}`);

const payload = {
  contents: [{
    role: "user",
    parts: [{ text: "Hello, answer in one word." }]
  }]
};

async function testStream() {
  try {
    const response = await fetch(url, {
      method: "POST",
      headers: { 
          "Content-Type": "application/json",
          "X-Goog-Api-Key": apiKey // Auth via header
      },
      body: JSON.stringify(payload)
    });

    if (!response.ok) {
      const text = await response.text();
      console.error(`❌ Stream Failed: ${response.status}`);
      console.error(text);
    } else {
      console.log(`✅ Stream Connected! Status: ${response.status}`);
      const text = await response.text(); // Just read body to confirm
      console.log(`Response length: ${text.length} chars`);
      // console.log(text.substring(0, 200));
    }
  } catch (e) {
    console.error("Network error:", e);
  }
}

testStream();
