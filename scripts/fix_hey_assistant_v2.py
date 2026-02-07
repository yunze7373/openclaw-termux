import os

target_file = "/data/data/com.termux/files/home/clawd/skills/multimodal-assistant/scripts/smart_assistant.py"

with open(target_file, "r") as f:
    lines = f.readlines()

new_lines = []
for line in lines:
    if "audio_file = recorder.listen()" in line:
        indent = line[:line.find("audio_file")]
        new_lines.append(f'{indent}# 监听逻辑优化\n')
        new_lines.append(f'{indent}stt_provider = config.get("stt_provider", "termux")\n')
        new_lines.append(f'{indent}if stt_provider == "termux":\n')
        new_lines.append(f'{indent}    print("\n👂 请准备说话 (等待系统弹窗)...")\n')
        new_lines.append(f'{indent}else:\n')
        new_lines.append(f'{indent}    audio_file = recorder.listen()\n')
    else:
        new_lines.append(line)

with open(target_file, "w") as f:
    f.writelines(new_lines)

print("Successfully patched smart_assistant.py with v2 script")
