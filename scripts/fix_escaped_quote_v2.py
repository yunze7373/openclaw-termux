import os

target_file = "/data/data/com.termux/files/home/clawd/skills/multimodal-assistant/scripts/smart_assistant.py"

with open(target_file, "r") as f:
    content = f.read()

# Fix the specific corrupted part
old_part = """content\\": text"""
new_part = """content": text"""

if old_part in content:
    new_content = content.replace(old_part, new_part)
    with open(target_file, "w") as f:
        f.write(new_content)
    print("Fixed corrupted line via direct string replacement.")
else:
    print("Pattern not found. Trying regex or partial match.")

