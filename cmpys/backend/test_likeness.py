import asyncio
from google import genai
from google.genai import types
from app.core.config import settings

async def main():
    if not settings.gemini_api_key:
        print("No API key")
        return
    client = genai.Client(api_key=settings.gemini_api_key)
    
    prompts = [
        "A photorealistic portrait of a 28-year-old actor portraying Steve Jobs in a biopic set in 1983. He has dark hair, a slight stubble, and looks ambitious.",
        "A photorealistic portrait of a 28-year-old man who looks identical to young Steve Jobs. He is wearing a 1980s suit, looking into the camera.",
        "Meticulous incredibly accurate photorealistic CGI recreation of Steve Jobs at exact age 28. Realistic rendering."
    ]
    
    for i, p in enumerate(prompts):
        try:
            print(f"Testing {i}: {p[:50]}...")
            response = await client.aio.models.generate_images(
                model="imagen-4.0-generate-001",
                prompt=p,
                config=types.GenerateImagesConfig(
                    number_of_images=1,
                    output_mime_type="image/jpeg",
                    aspect_ratio="1:1",
                    person_generation="ALLOW_ADULT"
                )
            )
            if response.generated_images:
                filename = f"test_{i}.jpg"
                with open(filename, "wb") as f:
                    f.write(response.generated_images[0].image.image_bytes)
                print(f"SUCCESS -> {filename}")
            else:
                print("No image returned")
        except Exception as e:
            print(f"FAILED: {e}")

asyncio.run(main())
