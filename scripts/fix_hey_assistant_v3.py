import os

target_file = "/data/data/com.termux/files/home/clawd/skills/multimodal-assistant/scripts/smart_assistant.py"

with open(target_file, "r") as f:
    lines = f.readlines()

new_lines = []
for line in lines:
    # Fix 1: Optimize main loop for Termux STT
    # We look for the call inside the loop, not the class definition
    if "recorder.listen()" in line and "def" not in line:
        indent = line[:line.find("recorder.listen()")]
        new_lines.append(f'{indent}# 监听逻辑优化\n')
        new_lines.append(f'{indent}stt_provider = config.get("stt_provider", "termux")\n')
        new_lines.append(f'{indent}if stt_provider == "termux":\n')
        new_lines.append(f'{indent}    print("\n👂 请准备说话 (等待系统弹窗)...")\n')
        new_lines.append(f'{indent}else:\n')
        new_lines.append(f'{indent}    recorder.listen()\n')
    
    # Fix 2: Allow "openai" as alias for "whisper"
    elif 'elif provider == "whisper":' in line:
        new_lines.append(line.replace('"whisper"', '"whisper" or provider == "openai"'))
        
    else:
        new_lines.append(line)

with open(target_file, "w") as f:
    f.writelines(new_lines)

print("Successfully patched smart_assistant.py with v3 script")
