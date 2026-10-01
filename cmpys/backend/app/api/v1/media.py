"""Public, read-only delivery of previously generated media."""
from pathlib import Path

from fastapi import APIRouter, HTTPException
from fastapi.responses import FileResponse

router = APIRouter()


@router.get("/{filename}")
async def get_media(filename: str):
    # A public image fetch must never trigger paid generation or database work.
    # Resolve before checking containment so symlinks cannot escape media/.
    media_dir = Path("media").resolve()
    file_path = (media_dir / filename).resolve()
    if file_path.parent != media_dir or not file_path.is_file():
        raise HTTPException(status_code=404, detail="File not found")
    return FileResponse(file_path)
