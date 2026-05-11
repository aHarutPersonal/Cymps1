import os
import io
from fastapi import APIRouter, HTTPException, Depends
from fastapi.responses import FileResponse, Response
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy.orm import selectinload
from sqlalchemy.future import select
from typing import Annotated
from datetime import date

from app.api.dependencies import get_db
from app.models.idol import Idol
from app.core.config import settings

from pathlib import Path

router = APIRouter()

@router.get("/{filename}")
async def get_media(filename: str, db: Annotated[AsyncSession, Depends(get_db)]):
    """
    Serve media files directly. 
    If an idol image is requested but not found locally, lazily generate it using Gemini.
    """
    media_dir = Path("media")
    media_dir.mkdir(exist_ok=True)
    file_path = media_dir / filename
    
    if file_path.exists():
        return FileResponse(file_path)
    
    # Lazy generation for missing avatar images.
    # Expected format: {uuid}_{timestamp}.jpg
    if "_" in filename and filename.endswith(".jpg"):
        idol_id_str = filename.split("_")[0]
        try:
            stmt = select(Idol).options(selectinload(Idol.profile)).where(Idol.id == idol_id_str)
            result = await db.execute(stmt)
            idol = result.scalar_one_or_none()
            if not idol:
                raise HTTPException(status_code=404, detail="Idol not found for this media")
            
            # Extract prompt template
            prompt_path = Path("..") / "prompts" / "image_generate.txt"
            with open(prompt_path, "r") as f:
                prompt_template = f.read()
                
            # Render prompt
            age = 40
            if idol.birth_date:
                today = date.today()
                death_date = idol.profile.death_date if (idol.profile and idol.profile.death_date) else today
                age = death_date.year - idol.birth_date.year - ((death_date.month, death_date.day) < (idol.birth_date.month, idol.birth_date.day))
                age = max(20, min(age, 80)) # Clamp reasonable age

            occupation = ""
            desc = ""
            if idol.profile:
                occupation = ", ".join(idol.profile.primary_roles)
                if idol.profile.short_description:
                    desc = idol.profile.short_description[:200]

            prompt = prompt_template.format(
                idol_name=idol.name,
                age=age,
                idol_description=f"{occupation}. {desc}"
            )
            
            # Generate image via GenAI
            try:
                from google import genai
                from google.genai import types
                
                client = genai.Client(api_key=settings.gemini_api_key)
                result = client.models.generate_images(
                    model='imagen-4.0-generate-001',
                    prompt=prompt,
                    config=types.GenerateImagesConfig(
                        number_of_images=1,
                        output_mime_type="image/jpeg",
                        aspect_ratio="1:1"
                    )
                )
                
                if result.generated_images:
                    image_bytes = result.generated_images[0].image.image_bytes
                    
                    # Save it locally so next time it serves fast
                    with open(file_path, "wb") as out_file:
                        out_file.write(image_bytes)
                        
                    return Response(content=image_bytes, media_type="image/jpeg")
                else:
                    raise HTTPException(status_code=500, detail="Gemini returned no images")
            except Exception as e:
                import logging
                logging.error(f"Image generation failed: {e}")
                raise HTTPException(status_code=500, detail=f"Image generation failed: {str(e)}")
        except ValueError:
            pass # Not a valid UUID
            
    raise HTTPException(status_code=404, detail="File not found")
