import asyncio
import logging
import json
from datetime import date

from app.core.celery import celery_app
from app.core.db import async_session_maker
from app.models.suggest_job import IdolSuggestJob
from app.models.idol import Idol
from app.models.idol_tag import IdolTag
from app.models.idol_tag_link import IdolTagLink
from app.schemas.idol import (
    LocalIdolSuggestion, 
    WebIdolSuggestion, 
    IdolAliasResponse, 
    IdolTagResponse,
)
from sqlalchemy import func, or_, select
from sqlalchemy.orm import selectinload

logger = logging.getLogger(__name__)

@celery_app.task(bind=True)
def run_idol_suggestions(self, job_id: str) -> dict:
    """
    Run idol suggestions in the background.
    """
    logger.info(f"[SUGGEST] Starting idol suggestions for job_id={job_id}")
    try:
        result = asyncio.get_event_loop().run_until_complete(_run_suggestions_async(job_id))
        logger.info(f"[SUGGEST] Completed job_id={job_id}")
        return result
    except Exception as e:
        logger.exception(f"[SUGGEST] Fatal error in job_id={job_id}: {e}")
        raise

async def _run_suggestions_async(job_id: str) -> dict:
    from app.core.config import settings
    from app.services.llm.client import get_llm_client
    from app.services.llm.prompt_loader import load_prompt, render_prompt
    from app.services.llm.schemas import IdolDiscoverResponse

    async with async_session_maker() as db:
        stmt = select(IdolSuggestJob).where(IdolSuggestJob.id == job_id)
        result = await db.execute(stmt)
        job = result.scalar_one_or_none()

        if not job:
            return {"error": "Job not found"}

        interests = job.interests or ""
        interest_list = [i.strip().lower() for i in interests.split(",") if i.strip()]
        limit = 20 # Default

        try:
            # Step 1: Analyzing interests (Local search)
            await _update_job(db, job, status="running", step="analyzing_interests", progress=10)
            
            local_limit = 12
            local_query = (
                select(
                    Idol,
                    func.sum(IdolTagLink.weight).label("relevance_score"),
                )
                .join(IdolTagLink, Idol.id == IdolTagLink.idol_id)
                .join(IdolTag, IdolTagLink.tag_id == IdolTag.id)
                .options(
                    selectinload(Idol.aliases),
                    selectinload(Idol.tag_links).selectinload(IdolTagLink.tag),
                )
                .where(
                    or_(
                        func.lower(IdolTag.name).in_(interest_list),
                        func.lower(Idol.domain).in_(interest_list),
                    )
                )
                .group_by(Idol.id)
                .order_by(func.sum(IdolTagLink.weight).desc())
                .limit(local_limit)
            )
            local_result = await db.execute(local_query)
            local_rows = local_result.unique().all()
            
            suggestions = []
            local_names = set()
            for idol, relevance_score in local_rows:
                suggestions.append({
                    "source": "local",
                    "id": str(idol.id),
                    "name": idol.name,
                    "birthDate": idol.birth_date.isoformat() if idol.birth_date else None,
                    "domain": idol.domain,
                    "aliases": [
                        {"id": str(a.id), "alias_text": a.alias_text}
                        for a in idol.aliases
                    ],
                    "tags": [
                        {"id": str(link.tag.id), "name": link.tag.name, "type": link.tag.type}
                        for link in idol.tag_links
                    ],
                    "relevanceScore": float(relevance_score) if relevance_score else 0.0,
                })
                local_names.add(idol.name.lower())
            
            await _update_job(db, job, progress=30)

            # Step 2: Querying knowledge base (LLM)
            await _update_job(db, job, step="querying_knowledge_base", progress=40)
            
            remaining = limit - len(suggestions)
            if remaining > 0 and settings.llm_configured:
                client = get_llm_client(timeout=60.0, fast=True)
                
                # First, generate human-readable thinking (streamed)
                thinking_template = load_prompt("thinking_narrate")
                thinking_prompt = render_prompt(thinking_template, {
                    "interests": ", ".join(interest_list) if interest_list else "general interests",
                }, prompt_name="thinking_narrate.txt")
                
                # Callback to stream thinking to database
                async def on_chunk(text: str):
                    job.thinking_text = text
                    await db.commit()
                
                # Generate human-readable thinking with streaming
                if hasattr(client, 'generate_json_streaming'):
                    # For thinking, we use a simple text generation (not JSON)
                    # Just stream the response directly
                    thinking_system = "You are a friendly AI assistant who thinks out loud while helping users find inspiring role models. Be warm and engaging."
                    
                    import openai
                    from app.core.config import settings as app_settings
                    
                    try:
                        openai_client = openai.AsyncOpenAI(api_key=app_settings.openai_api_key)
                        thinking_text = ""
                        
                        stream = await openai_client.chat.completions.create(
                            model="gpt-4o-mini",
                            messages=[
                                {"role": "system", "content": thinking_system},
                                {"role": "user", "content": thinking_prompt},
                            ],
                            stream=True,
                            max_tokens=200,
                            temperature=0.7,
                        )
                        
                        async for chunk in stream:
                            delta = chunk.choices[0].delta
                            if delta.content:
                                thinking_text += delta.content
                                job.thinking_text = thinking_text
                                await db.commit()
                        
                        logger.info(f"[SUGGEST] Thinking generated: {len(thinking_text)} chars")
                    except Exception as e:
                        logger.warning(f"[SUGGEST] Thinking generation failed: {e}")
                        job.thinking_text = "Let me think about role models that match your interests..."
                        await db.commit()
                
                await _update_job(db, job, progress=50)
                
                # Now generate the actual idol candidates (JSON)
                system_prompt = "You are a knowledge assistant that helps discover notable people as role models. Be concise."
                user_template = load_prompt("idol_discover")
                user_prompt = render_prompt(user_template, {
                    "interests_json_array": json.dumps(interest_list),
                    "user_age": "null",
                    "limit": str(remaining + 5),
                }, prompt_name="idol_discover.txt")
                
                validated, response = await client.generate_and_validate(
                    system_prompt=system_prompt,
                    user_prompt=user_prompt,
                    output_model=IdolDiscoverResponse,
                    repair_on_failure=False,
                )
                
                await _update_job(db, job, progress=70)

                # Step 3: Filtering matches
                await _update_job(db, job, step="filtering_matches", progress=80)
                
                if validated and validated.candidates:
                    web_count = 0
                    for c in validated.candidates:
                        if web_count >= remaining:
                            break
                        if c.name.lower() not in local_names:
                            birth_date_val = None
                            if c.birth_year:
                                try:
                                    birth_date_val = date(c.birth_year, 1, 1).isoformat()
                                except ValueError:
                                    pass
                            
                            wikipedia_url = None
                            if c.wikipedia_slug:
                                wikipedia_url = f"https://en.wikipedia.org/wiki/{c.wikipedia_slug.replace(' ', '_')}"
                            
                            suggestions.append({
                                "source": "web",
                                "provider": "llm",
                                "externalId": f"llm:{c.name.lower().replace(' ', '_')}",
                                "name": c.name,
                                "description": c.description,
                                "birthDate": birth_date_val,
                                "wikipediaUrl": wikipedia_url,
                                "occupations": c.domains,
                                "confidence": c.confidence,
                            })
                            web_count += 1
            
            # Finalize
            job.result_json = {"suggestions": suggestions}
            await _update_job(db, job, status="completed", step="done", progress=100)
            return {"status": "completed", "count": len(suggestions)}

        except Exception as e:
            logger.exception(f"Suggestions failed for job {job_id}")
            await _update_job(db, job, status="failed", step="error", error_message=str(e))
            return {"error": str(e)}

async def _update_job(db, job, **kwargs):
    for k, v in kwargs.items():
        setattr(job, k, v)
    await db.commit()
