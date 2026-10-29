"""One optional Imagen 4 hero illustration per published tutorial step.

The illustration is decoration, never content. It is generated after a tutorial
is durably published, attached to that step inside ``plan_items.details_json``,
and may be missing for any reason (feature off, daily cap, provider error). Every
failure path returns ``None``/a skipped status without touching item or job
state, and nothing here retries: one request per step per publication.

Identity: the image file name is ``sha256(title + concept)``, so a step whose
title and core idea are unchanged reuses its existing file with no provider call
and no cap usage, even across regenerations.
"""

import asyncio
import copy
import hashlib
import logging
import os
import re
from collections.abc import Iterable, Mapping
from dataclasses import dataclass
from datetime import datetime, timezone
from pathlib import Path
from typing import Any

from google.genai import types
from pydantic import ValidationError
from sqlalchemy import select
from sqlalchemy.orm import selectinload

from app.core.config import settings
from app.core.db import async_session_maker
from app.models.plan import Plan, PlanItem
from app.schemas.plan import TutorialIllustration
from app.services.genai_client import IMAGEN_MODEL, build_genai_client
from app.services.llm.prompt_loader import load_and_render

logger = logging.getLogger(__name__)

__all__ = [
    "TutorialIllustration",
    "attach_tutorial_illustration",
    "build_illustration_prompt",
    "generate_illustration",
    "generate_tutorial_illustration",
    "illustrate_step",
    "illustration_key",
    "illustration_url",
    "reconcile_step_illustrations",
    "step_inputs",
]

PROVIDER = "gemini_imagen"
ASPECT = "16:9"
TUTORIAL_LESSON_FORMAT = "tutorial_v1"
# Relative to the working directory, exactly like the avatar endpoint and the
# StaticFiles mount in app.main, so /media/tutorials/<hash>.jpg resolves there.
MEDIA_DIR = Path("media")
MEDIA_SUBDIR = "tutorials"
URL_PREFIX = f"/media/{MEDIA_SUBDIR}"
PROMPT_NAME = "tutorial_illustration.txt"
# One request, bounded: a hung provider must not occupy the single default
# worker slot. The Celery task adds its own outer deadline.
PROVIDER_TIMEOUT_SECONDS = 60

_TITLE_LIMIT = 120
_CONCEPT_LIMIT = 240
_DOMAIN_LIMIT = 80
_ALT_LIMIT = 160

# Emphasis and code markers only: "C#" and snake_case words keep their characters.
_MARKDOWN_NOISE = re.compile(r"[*`]+|(?<!\w)_+|_+(?!\w)")
_CORE_FRAMEWORK_HEADING = re.compile(r"^\s{0,3}##\s+core framework\s*$", re.IGNORECASE)
_ANY_HEADING = re.compile(r"^\s{0,3}#{1,6}\s")
_LIST_MARKER = re.compile(r"^(?:[-*+]\s+|\d+[.)]\s+|>\s*)")
_SENTENCE_END = re.compile(r"(?<=[.!?])\s+")


# --- prompt -----------------------------------------------------------------------


def _plain(value: Any, limit: int) -> str:
    """Single-line, markdown-free text capped to ``limit`` characters."""
    text = _MARKDOWN_NOISE.sub("", str(value or ""))
    text = re.sub(r"\s+", " ", text).strip()
    return text[:limit].rstrip()


def build_illustration_prompt(title: str, concept: str, domain: str) -> str:
    """Render the Imagen prompt: editorial style on warm paper, never any text."""
    return load_and_render(
        PROMPT_NAME,
        {
            "title": _plain(title, _TITLE_LIMIT),
            "concept": _plain(concept, _CONCEPT_LIMIT),
            "domain": _plain(domain, _DOMAIN_LIMIT) or "general learning",
        },
    ).strip()


# --- deriving what to illustrate ----------------------------------------------------


def _first_sentence(text: str) -> str:
    return _SENTENCE_END.split(text.strip(), maxsplit=1)[0] if text.strip() else ""


def _core_framework_sentence(lesson_content: str) -> str:
    """First sentence of the first prose paragraph under "## Core Framework".

    Native blocks (fenced visuals, tables) and list markers are skipped so the
    sentence is the author's own statement of the idea.
    """
    in_section = in_fence = False
    paragraph: list[str] = []
    for line in lesson_content.splitlines():
        stripped = line.strip()
        if not in_section:
            in_section = bool(_CORE_FRAMEWORK_HEADING.match(line))
            continue
        if stripped.startswith("```"):
            if paragraph:
                break
            in_fence = not in_fence
            continue
        if in_fence:
            continue
        if _ANY_HEADING.match(line):
            break
        if not stripped or stripped.startswith("|"):
            if paragraph:
                break
            continue
        paragraph.append(_LIST_MARKER.sub("", stripped))
    return _first_sentence(_plain(" ".join(paragraph), 2000))


def step_inputs(step: Mapping[str, Any]) -> tuple[str, str] | None:
    """``(title, concept)`` for a step, or ``None`` when it has no title.

    The concept is the first sentence of the Core Framework section, falling back
    to the step description and finally the title itself.
    """
    title = _plain(step.get("title"), _TITLE_LIMIT)
    if not title:
        return None
    content = step.get("lesson_content")
    concept = _core_framework_sentence(content) if isinstance(content, str) else ""
    if not concept:
        concept = _first_sentence(_plain(step.get("description"), 1000))
    return title, _plain(concept or title, _CONCEPT_LIMIT)


def illustration_key(title: str, concept: str) -> str:
    return hashlib.sha256((title + concept).encode("utf-8")).hexdigest()


def illustration_url(step: Mapping[str, Any]) -> str | None:
    """The URL this step's illustration has (or would have), if it can have one."""
    inputs = step_inputs(step)
    return f"{URL_PREFIX}/{illustration_key(*inputs)}.jpg" if inputs else None


def _is_illustratable(step: Any) -> bool:
    """A published bespoke tutorial: ``tutorial_v1`` with lesson text, not catalog.

    Catalog-personalized steps are hashed against immutable stored versions and
    are legacy-format lessons; an extra key would fail their integrity check.
    """
    return (
        isinstance(step, Mapping)
        and isinstance(step.get("id"), str)
        and step.get("lesson_format") == TUTORIAL_LESSON_FORMAT
        and isinstance(step.get("lesson_content"), str)
        and bool(step["lesson_content"].strip())
        and not step.get("personalized_lesson_version_id")
    )


def _valid_illustration(value: Any) -> TutorialIllustration | None:
    try:
        return TutorialIllustration.model_validate(value)
    except ValidationError:
        return None


# --- carrying illustrations through republication ------------------------------------


def reconcile_step_illustrations(
    previous_details: Any,
    published_details: dict[str, Any],
    ready_step_ids: Iterable[str],
) -> list[str]:
    """Prepare a replacement ``details_json`` and list the steps to illustrate.

    Publishing rewrites ``details_json`` from the generator's payload, which has
    never seen an illustration added meanwhile. Inside the publication lock,
    copy each stored illustration onto its step when it still matches that
    step's title and idea. Return the ready steps that should be requested now:
    steps new to this publication, or whose stored illustration no longer
    matches. A step that was already published without an image was attempted
    (or the feature was off) and is never requested again.
    """
    steps = published_details.get("steps") if isinstance(published_details, dict) else None
    if not isinstance(steps, list):
        return []
    previous_steps: dict[str, Mapping[str, Any]] = {}
    raw_previous = previous_details.get("steps") if isinstance(previous_details, dict) else None
    for step in raw_previous if isinstance(raw_previous, list) else []:
        if isinstance(step, Mapping) and isinstance(step.get("id"), str):
            previous_steps[step["id"]] = step

    ready = set(ready_step_ids)
    pending: list[str] = []
    for step in steps:
        if not _is_illustratable(step) or step["id"] not in ready:
            continue
        expected_url = illustration_url(step)
        if expected_url is None:
            continue
        prior = previous_steps.get(step["id"])
        kept = _valid_illustration(prior.get("illustration")) if prior else None
        if kept is not None and kept.url == expected_url:
            step["illustration"] = kept.model_dump(mode="json")
            continue
        step.pop("illustration", None)
        if prior is not None and _is_illustratable(prior) and kept is None:
            continue  # Already published once without an image: no retry loop.
        pending.append(step["id"])
    return pending


# --- generation ---------------------------------------------------------------------


def count_generated_today(directory: Path, *, now: datetime | None = None) -> int:
    """Images written to ``directory`` today (UTC), by file modification date."""
    today = (now or datetime.now(timezone.utc)).date()
    count = 0
    try:
        with os.scandir(directory) as entries:
            for entry in entries:
                if not (entry.name.endswith(".jpg") and entry.is_file()):
                    continue
                modified = datetime.fromtimestamp(entry.stat().st_mtime, tz=timezone.utc)
                count += modified.date() == today
    except FileNotFoundError:
        return 0
    return count


def _write_atomic(path: Path, data: bytes) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    temporary = path.parent / f".{path.name}.{os.getpid()}.tmp"
    try:
        temporary.write_bytes(data)
        os.replace(temporary, path)
    finally:
        temporary.unlink(missing_ok=True)


def _alt_text(title: str, concept: str) -> str:
    text = f"Illustration for “{title}”: {concept}"
    return text if len(text) <= _ALT_LIMIT else text[: _ALT_LIMIT - 1].rstrip() + "…"


async def _request_image(prompt: str) -> bytes | None:
    """One Imagen request. Raises on provider errors; ``None`` for an empty result."""
    client = build_genai_client()
    try:
        response = await asyncio.wait_for(
            client.aio.models.generate_images(
                model=IMAGEN_MODEL,
                prompt=prompt,
                config=types.GenerateImagesConfig(
                    number_of_images=1,
                    output_mime_type="image/jpeg",
                    aspect_ratio=ASPECT,
                ),
            ),
            timeout=PROVIDER_TIMEOUT_SECONDS,
        )
    finally:
        close = getattr(getattr(client, "aio", None), "aclose", None)
        if callable(close):
            try:
                await close()
            except Exception:  # Closing is courtesy; never mask the real outcome.
                logger.debug("[ILLUSTRATION] Imagen client close failed", exc_info=True)
    images = getattr(response, "generated_images", None) or []
    image = getattr(images[0], "image", None) if images else None
    data = getattr(image, "image_bytes", None)
    return bytes(data) if data else None


async def generate_illustration(title: str, concept: str, domain: str) -> TutorialIllustration | None:
    """Generate (or reuse) the image for one title and idea.

    Returns ``None`` when disabled, over today's cap, or on any provider error.
    Makes at most one provider request and never retries.
    """
    if not settings.tutorial_illustrations_enabled:
        return None
    try:
        key = illustration_key(title, concept)
        directory = MEDIA_DIR / MEDIA_SUBDIR
        path = directory / f"{key}.jpg"
        illustration = TutorialIllustration(
            url=f"{URL_PREFIX}/{key}.jpg",
            alt=_alt_text(title, concept),
            provider=PROVIDER,
            aspect=ASPECT,
        )
        if await asyncio.to_thread(path.is_file):
            return illustration  # Idempotent: no provider call, not counted.
        cap = settings.tutorial_illustration_daily_cap
        if await asyncio.to_thread(count_generated_today, directory) >= cap:
            logger.info("[ILLUSTRATION] Daily cap of %s reached; skipping", cap)
            return None
        data = await _request_image(build_illustration_prompt(title, concept, domain))
        if not data:
            logger.warning("[ILLUSTRATION] Imagen returned no image for %s", key[:12])
            return None
        await asyncio.to_thread(_write_atomic, path, data)
        return illustration
    except Exception as error:
        logger.warning("[ILLUSTRATION] Generation failed (%s): %s", type(error).__name__, error)
        return None


@dataclass(frozen=True)
class _StepInputs:
    title: str
    concept: str
    domain: str


def _domain_for(plan: Any) -> str:
    """The mentor's field, else the plan's goal, else a neutral default."""
    idol = getattr(plan, "idol", None)
    domain = _plain(getattr(idol, "domain", None), _DOMAIN_LIMIT)
    if domain:
        return domain
    roadmap = getattr(plan, "roadmap_json", None)
    goal = _plain(roadmap.get("effective_goal"), _DOMAIN_LIMIT) if isinstance(roadmap, dict) else ""
    return goal or "general learning"


def _find_step(details: Any, step_id: str) -> tuple[int, Mapping[str, Any]] | None:
    steps = details.get("steps") if isinstance(details, dict) else None
    for index, step in enumerate(steps if isinstance(steps, list) else []):
        if isinstance(step, Mapping) and step.get("id") == step_id:
            return index, step
    return None


async def _load_step_inputs(plan_item_id: str, step_id: str) -> _StepInputs | None:
    async with async_session_maker() as db:
        item = (
            await db.execute(
                select(PlanItem)
                .options(selectinload(PlanItem.plan).selectinload(Plan.idol))
                .where(PlanItem.id == plan_item_id)
            )
        ).scalar_one_or_none()
        if item is None:
            return None
        found = _find_step(item.details_json, step_id)
        if found is None or not _is_illustratable(found[1]):
            return None
        inputs = step_inputs(found[1])
        if inputs is None:
            return None
        return _StepInputs(inputs[0], inputs[1], _domain_for(item.plan))


async def generate_tutorial_illustration(plan_item_id: str, step_id: str) -> TutorialIllustration | None:
    """Generate (or reuse) the illustration for one published tutorial step.

    Read-only with respect to the database. ``None`` for every non-success.
    """
    if not settings.tutorial_illustrations_enabled:
        return None
    try:
        inputs = await _load_step_inputs(plan_item_id, step_id)
    except Exception as error:
        logger.warning("[ILLUSTRATION] Could not load step %s/%s: %s", plan_item_id, step_id, error)
        return None
    if inputs is None:
        return None
    return await generate_illustration(inputs.title, inputs.concept, inputs.domain)


# --- attaching to the published step -------------------------------------------------


async def attach_tutorial_illustration(
    plan_item_id: str, step_id: str, illustration: TutorialIllustration
) -> str:
    """Write ``illustration`` into the step inside ``details_json``.

    The item row is locked and re-read, so the change merges onto whatever a
    concurrent checkpoint just published instead of overwriting it. Returns
    ``attached``, ``unchanged``, ``stale`` (the lesson changed while the image
    was generating) or ``missing``. Item and job status are never touched.
    """
    async with async_session_maker() as db:
        item = (
            await db.execute(
                select(PlanItem)
                .where(PlanItem.id == plan_item_id)
                .execution_options(populate_existing=True)
                .with_for_update(of=PlanItem)
            )
        ).scalar_one_or_none()
        found = _find_step(item.details_json, step_id) if item is not None else None
        if found is None or not _is_illustratable(found[1]):
            await db.rollback()
            return "missing"
        index, step = found
        if illustration_url(step) != illustration.url:
            await db.rollback()
            return "stale"
        value = illustration.model_dump(mode="json")
        if step.get("illustration") == value:
            await db.rollback()
            return "unchanged"
        updated = copy.deepcopy(item.details_json)
        updated["steps"][index]["illustration"] = value
        item.details_json = updated
        await db.commit()
        return "attached"


async def illustrate_step(plan_item_id: str, step_id: str) -> dict[str, str]:
    """Generate and attach one step's illustration. Used by the Celery task."""
    illustration = await generate_tutorial_illustration(plan_item_id, step_id)
    if illustration is None:
        return {"status": "skipped"}
    return {"status": await attach_tutorial_illustration(plan_item_id, step_id, illustration),
            "url": illustration.url}
