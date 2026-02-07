import os

target_file = "/data/data/com.termux/files/home/clawd/skills/multimodal-assistant/scripts/smart_assistant.py"

with open(target_file, "r") as f:
    lines = f.readlines()

new_lines = []
i = 0
while i < len(lines):
    line = lines[i]
    # Check for the broken print statement
    if line.strip() == 'print("':
        # Found the broken start, check next line
        if i + 1 < len(lines) and "👂" in lines[i+1]:
            # Merge them
            combined = line.strip() + "\n" + lines[i+1].strip() + '\n'
            # The indent should match the original line
            indent = line[:line.find('print')]
            new_lines.append(indent + 'print("\n👂 请准备说话 (等待系统弹窗)...")\n')
            i += 2 # Skip next line
            continue
    
    new_lines.append(line)
    i += 1

with open(target_file, "w") as f:
    f.writelines(new_lines)

print("Successfully fixed syntax error in smart_assistant.py")
