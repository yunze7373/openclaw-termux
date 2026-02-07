
import asyncio
import sys
import os

# Set the path to include the directory of the smart_assistant script
assistant_dir = "/data/data/com.termux/files/home/clawd/skills/multimodal-assistant/scripts"
sys.path.append(assistant_dir)

# Import the speak function
try:
    from smart_assistant import speak
except ImportError:
    # If import fails directly, try to mock the environment needed
    print("Direct import failed, attempting to use termux-tts-speak as fallback with Xiao-Ji style")
    import subprocess
    def speak_fallback(text):
        # Xiao-Ji style: max volume + tts
        subprocess.run(["termux-volume", "music", "15"], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        subprocess.run(["termux-tts-speak", text])
    
    async def speak(text):
        speak_fallback(text)

async def main():
    if len(sys.argv) < 2:
        message = "您好，我是小鸡。请告诉我您想播报的内容。"
    else:
        message = " ".join(sys.argv[1:])
    
    print(f"正在通过小鸡播报: {message}")
    await speak(message)
    print("播报请求已发送。")

if __name__ == "__main__":
    asyncio.run(main())
