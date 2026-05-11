import asyncio
from google import genai
from app.core.config import settings

async def main():
    client = genai.Client(api_key=settings.gemini_api_key)
    try:
        models = await client.aio.models.list()
        for m in models:
            if getattr(m, 'name', None) and ('image' in m.name or 'imagen' in m.name):
                print(m.name, getattr(m, 'supported_generation_methods', []))
    except Exception as e:
        print("Error:", e)

asyncio.run(main())
