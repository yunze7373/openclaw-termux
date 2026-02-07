import os

target_file = "/data/data/com.termux/files/home/clawd/skills/multimodal-assistant/scripts/smart_assistant.py"

with open(target_file, "r") as f:
    content = f.read()

if 'model_name = "gemini-1.5-flash"' in content:
    content = content.replace('model_name = "gemini-1.5-flash"', 'model_name = "gemini-2.0-flash"')
    with open(target_file, "w") as f:
        f.write(content)
    print("Updated model to gemini-2.0-flash")
else:
    print("Could not find model_name definition.")
