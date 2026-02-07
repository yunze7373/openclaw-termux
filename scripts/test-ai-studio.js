import fs from 'node:fs';

const configPath = '/data/data/com.termux/files/home/.moltbot/moltbot.json';
const raw = fs.readFileSync(configPath, 'utf8');
const config = JSON.parse(raw);
const key = config.env?.vars?.VERTEX_API_KEY || config.env?.vars?.GEMINI_API_KEY;

if (!key || key.includes("YOUR_")) {
    console.error("No valid key found in env.vars to test.");
    process.exit(1);
}

// Test AI Studio Endpoint
const url = `https://generativelanguage.googleapis.com/v1beta/models/gemini-2.0-flash:generateContent?key=${key}`;

console.log(`Testing AI Studio Endpoint with Key...`);

async function test() {
    try {
        const res = await fetch(url, {
            method: "POST",
            headers: { "Content-Type": "application/json" },
            body: JSON.stringify({ contents: [{ parts: [{ text: "Hi" }] }] })
        });
        
        if (res.ok) {
            console.log("✅ AI Studio Endpoint WORKS with this key!");
        } else {
            console.log(`❌ AI Studio Endpoint FAILED: ${res.status}`);
            console.log(await res.text());
        }
    } catch (e) {
        console.error(e);
    }
}
test();
