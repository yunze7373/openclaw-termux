import os

target_file = "/data/data/com.termux/files/home/clawd/skills/multimodal-assistant/scripts/smart_assistant.py"

with open(target_file, "r") as f:
    content = f.read()

old_loop = """# 主循环
async def main_loop():
    if not init_clients():
        return

    recorder = AudioRecorder()
    await speak(f"你好韩哥，{config.get('llm_provider')} 助手已就绪。")
    
    try:
        while True:
            # 监听
            audio_file = recorder.listen()
            
            # 识别
            text = transcribe_audio()
            if not text: continue
                
            if "退出" in text or "再见" in text:
                await speak("再见。" )
                break
                
            # 思考 & 回答
            response = get_ai_response(text)
            await speak(response)
            
    except KeyboardInterrupt:
        print("\n停止")
    finally:
        recorder.close()"""

new_loop = """# 主循环
async def main_loop():
    if not init_clients():
        return

    recorder = AudioRecorder()
    await speak(f"你好韩哥，{config.get('llm_provider')} 助手已就绪。")
    
    try:
        while True:
            # 监听逻辑优化
            stt_provider = config.get("stt_provider", "termux")
            
            if stt_provider == "termux":
                # Termux 自带录音界面，无需 VAD 预录音
                print("\n👂 请准备说话 (等待系统弹窗)...")
            else:
                # 其他 Provider 需要先录音
                audio_file = recorder.listen()
            
            # 识别
            text = transcribe_audio()
            if not text: continue
                
            if "退出" in text or "再见" in text:
                await speak("再见。" )
                break
                
            # 思考 & 回答
            response = get_ai_response(text)
            await speak(response)
            
    except KeyboardInterrupt:
        print("\n停止")
    finally:
        recorder.close()"""

if old_loop in content:
    new_content = content.replace(old_loop, new_loop)
    with open(target_file, "w") as f:
        f.write(new_content)
    print("Successfully patched smart_assistant.py")
else:
    print("Could not find exact match for main_loop.")
