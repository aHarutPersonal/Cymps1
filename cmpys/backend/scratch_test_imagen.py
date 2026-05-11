import os
import sys

from google import genai
from google.genai import types

from dotenv import load_dotenv
load_dotenv(".env")

api_key = os.environ.get("GEMINI_API_KEY")
client = genai.Client(api_key=api_key)

try:
    print("Generating image...")
    result = client.models.generate_images(
        model='imagen-3.0-generate-002',
        prompt='A cute baby dinosaur drinking coffee.',
        config=types.GenerateImagesConfig(
            number_of_images=1,
            output_mime_type="image/jpeg",
            aspect_ratio="1:1"
        )
    )
    for index, generated_image in enumerate(result.generated_images):
        image = generated_image.image
        with open(f"media/test_dino_{index}.jpg", "wb") as f:
            f.write(image.image_bytes)
        print(f"Saved media/test_dino_{index}.jpg")
except Exception as e:
    print(f"Error: {e}")
