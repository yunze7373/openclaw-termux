import os

target_file = "/data/data/com.termux/files/home/clawd/skills/multimodal-assistant/scripts/smart_assistant.py"

with open(target_file, "r") as f:
    lines = f.readlines()

new_lines = []
for line in lines:
    if 'content\": text' in line:
        # Fix the escaped quote
        fixed = line.replace('content\": text', 'content": text')
        new_lines.append(fixed)
        print("Fixed corrupted content key.")
    else:
        new_lines.append(line)

with open(target_file, "w") as f:
    f.writelines(new_lines)

