"""One place that turns the configured Gemini key into a google-genai client.

Imagen shares the Gemini API key. Keeping the construction here means callers
(the mentor avatar endpoint, tutorial illustrations) never handle the secret
themselves.
"""

from google import genai

from app.core.config import settings

# Imagen 4 model used for every generated image in the product.
IMAGEN_MODEL = "imagen-4.0-generate-001"


def build_genai_client() -> genai.Client:
    """Return a fresh client; raises ``ValueError`` when no API key is configured.

    A client owns an aiohttp session bound to the event loop that first uses
    it, so image callers build one per request instead of sharing it.
    """
    return genai.Client(api_key=settings.gemini_api_key)
