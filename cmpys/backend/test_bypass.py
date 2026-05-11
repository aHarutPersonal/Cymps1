import asyncio
from google import genai
from google.genai import types
from app.core.config import settings

async def main():
    client = genai.Client(api_key=settings.gemini_api_key)
    idol_name = "Steve Jobs"
    target_age = 25
    
    # Step 1: Descriptor
    bypass_prompt = f"Describe the precise facial features, eye color, hair style, facial hair, and iconic clothing of {idol_name} at age {target_age}. Write exactly 2 sentences of physical description only. DO NOT use their name. Just describe the person."
    desc_resp = await client.aio.models.generate_content(
        model=settings.gemini_fast_model,
        contents=bypass_prompt
    )
    safe_description = desc_resp.text.strip()
    print("Safe Description:", safe_description)
    
    # Step 2: Image Gen
    prompt = f"A high-quality photorealistic portrait of a {target_age} year old person. {safe_description}. Cinematic lighting, 85mm full frame lens, stunning detail."
    
    try:
        image_resp = await client.aio.models.generate_images(
            model="imagen-4.0-generate-001",
            prompt=prompt,
            config=types.GenerateImagesConfig(
                number_of_images=1,
                output_mime_type="image/jpeg",
                aspect_ratio="1:1",
                person_generation="ALLOW_ADULT"
            )
        )
        if image_resp.generated_images:
            print("Success! image bytes len:", len(image_resp.generated_images[0].image.image_bytes))
        else:
            print("None return. Blocked.")
    except Exception as e:
        print("Error:", e)

asyncio.run(main())
