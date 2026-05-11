import asyncio
from google import genai
from google.genai import types
from app.core.config import settings

async def main():
    client = genai.Client(api_key=settings.gemini_api_key)
    try:
        response = await client.aio.models.generate_images(
            model="imagen-4.0-generate-001",
            prompt="A sleek futuristic robot in a modern laboratory, digital art style.",
            config=types.GenerateImagesConfig(
                number_of_images=1,
                output_mime_type="image/jpeg",
                aspect_ratio="1:1",
                person_generation="ALLOW_ADULT"
            )
        )
        if hasattr(response, 'generated_images') and response.generated_images:
            print("Success:", len(response.generated_images[0].image.image_bytes))
        else:
            print("response object contains:", dir(response))
    except Exception as e:
        print("Error:", e)

asyncio.run(main())
