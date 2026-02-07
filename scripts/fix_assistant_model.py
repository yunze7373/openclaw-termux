import os

target_file = "/data/data/com.termux/files/home/clawd/skills/multimodal-assistant/scripts/smart_assistant.py"

with open(target_file, "r") as f:
    content = f.read()

# Fix 1: Replace hardcoded model with config variable
old_url = 'url = f"https://generativelanguage.googleapis.com/v1beta/models/gemini-pro:generateContent?key={key}"'
new_url = 'url = f"https://generativelanguage.googleapis.com/v1beta/models/{config[\'gemini\'][\'model\']}:generateContent?key={key}"'

if old_url in content:
    content = content.replace(old_url, new_url)
    print("Fixed hardcoded model ID.")
else:
    print("Could not find hardcoded model ID line (might be already fixed or different format).")

# Fix 2: Ensure correct logic for Vertex Proxy (if we want to use it later)
# The current script overwrites the proxy URL logic. We can clean that up too if needed.
# For now, fixing the AI Studio URL dynamic model is enough to solve 404 if user uses AIza key.

with open(target_file, "w") as f:
    f.write(content)

