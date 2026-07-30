"""Grounded research with provider-owned source provenance.

The discovery call is the only stage allowed to browse.  It returns provider
grounding chunks and support spans, assigns stable source ids server-side, and
then a structured curator may classify and synthesize only those sources (plus
the deterministic approved technique registry).  A normal JSON model can
therefore never pretend that it searched the web.
"""

from __future__ import annotations

import asyncio
import ipaddress
import logging
import socket
import time
from dataclasses import dataclass
from datetime import datetime, timezone
from typing import Any
from urllib.parse import urljoin, urlsplit, urlunsplit

import httpx
from google.genai import types

from app.core.config import settings
from app.services.curriculum.hashing import sha256_json
from app.services.curriculum.budget import estimate_curriculum_grounded_cost_usd
from app.services.curriculum.pilot import TECHNIQUE_REGISTRY
from app.services.curriculum.schemas import (
    ClaimVerificationBundle,
    EvidenceSource,
    EvidenceTier,
    ResearchCuration,
    ResearchManifest,
    RightsStatus,
    SourceType,
)
from app.services.curriculum.security import (
    sanitize_external_text,
    sanitize_research_manifest,
)
from app.services.gemini import (
    GEMINI_REQUEST_TIMEOUT_MS,
    _gemini_client,
    _model_for_tier,
)
from app.services.llm import get_llm_client
from app.services.llm.gemini_compat import (
    generation_config_kwargs,
    resolve_thinking_config,
)
from app.services.llm.prompt_loader import load_and_render, load_prompt
from app.services.llm.telemetry import UsageRecord, record_llm_response, record_usage_records
from app.services.tavily import is_direct_resource_url

logger = logging.getLogger(__name__)


@dataclass(frozen=True, slots=True)
class GroundedSource:
    source_id: str
    title: str
    url: str
    support_text: str
    content_hash: str
    provenance: str = "gemini_google_search_grounding_chunk"
    provider_url: str | None = None
    checked_at: str | None = None
    grounding_confidence: float | None = None


@dataclass(frozen=True, slots=True)
class GroundedDiscovery:
    synthesis: str
    sources: tuple[GroundedSource, ...]
    search_queries: tuple[str, ...]
    model: str


class GroundingUnavailableError(RuntimeError):
    pass


_QUALIFIED_LIVE_DOMAIN_SOURCE_TYPES = frozenset(
    {
        SourceType.PRIMARY_RESEARCH,
        SourceType.PRACTICE_GUIDE,
        SourceType.PROFESSIONAL_STANDARD,
        SourceType.OFFICIAL_DOCUMENTATION,
        SourceType.UNIVERSITY_RESOURCE,
    }
)


def _source_id(url: str) -> str:
    return f"src_{sha256_json({'url': url})[:20]}"


def deterministic_source_classification(
    source: GroundedSource,
) -> tuple[SourceType, EvidenceTier, str]:
    """Apply conservative server-owned quality labels; never trust the curator."""
    if source.provenance == "approved_technique_registry":
        if source.url == "https://ies.ed.gov/ncee/wwc/PracticeGuide/1":
            return SourceType.PRACTICE_GUIDE, EvidenceTier.STRONG, "approved_registry"
        if urlsplit(source.url).hostname == "doi.org":
            return SourceType.PRIMARY_RESEARCH, EvidenceTier.MODERATE, "approved_registry"
        return SourceType.OTHER, EvidenceTier.EMERGING, "approved_registry"
    hosts = {
        (urlsplit(url).hostname or "").casefold()
        for url in (source.url, source.provider_url)
        if url
    }
    if "doi.org" in hosts:
        return (
            SourceType.PRIMARY_RESEARCH,
            EvidenceTier.MODERATE,
            "deterministic_url_rule",
        )
    if "ies.ed.gov" in hosts:
        return (
            SourceType.PRACTICE_GUIDE,
            EvidenceTier.STRONG,
            "deterministic_url_rule",
        )
    if any(host.endswith(".gov") for host in hosts):
        return (
            SourceType.OFFICIAL_DOCUMENTATION,
            EvidenceTier.MODERATE,
            "deterministic_url_rule",
        )
    if any(host.endswith(".edu") for host in hosts):
        return (
            SourceType.UNIVERSITY_RESOURCE,
            EvidenceTier.MODERATE,
            "deterministic_url_rule",
        )
    return SourceType.OTHER, EvidenceTier.EMERGING, "unverified"


def _domain_claim_eligible(source: GroundedSource) -> bool:
    """Whether a live source can satisfy the manifest's domain evidence gate."""

    source_type, _, provenance = deterministic_source_classification(source)
    return (
        source.provenance != "approved_technique_registry"
        and provenance == "deterministic_url_rule"
        and source_type in _QUALIFIED_LIVE_DOMAIN_SOURCE_TYPES
    )


async def _resolved_public_ips(url: str) -> tuple[str, ...]:
    parsed = urlsplit(url)
    host = parsed.hostname
    if not host:
        return ()
    try:
        addresses = await asyncio.to_thread(
            socket.getaddrinfo,
            host,
            parsed.port or (443 if parsed.scheme == "https" else 80),
            type=socket.SOCK_STREAM,
        )
    except OSError:
        return ()
    ips = {item[4][0].split("%", 1)[0] for item in addresses}
    if not ips or not all(ipaddress.ip_address(ip).is_global for ip in ips):
        return ()
    return tuple(sorted(ips))


def _pinned_url(original_url: str, ip: str) -> tuple[str, str, str]:
    parsed = urlsplit(original_url)
    host = parsed.hostname or ""
    default_port = 443 if parsed.scheme == "https" else 80
    port = parsed.port or default_port
    ip_literal = f"[{ip}]" if ":" in ip else ip
    netloc = ip_literal if port == default_port else f"{ip_literal}:{port}"
    host_header = host if port == default_port else f"{host}:{port}"
    return (
        urlunsplit((parsed.scheme, netloc, parsed.path, parsed.query, "")),
        host_header,
        host,
    )


async def _request_pinned(
    client: httpx.AsyncClient,
    *,
    method: str,
    original_url: str,
    ips: tuple[str, ...],
) -> tuple[int, str | None] | None:
    """Connect only to a prevalidated IP while preserving HTTP Host and TLS SNI."""
    for ip in ips:
        pinned_url, host_header, sni_hostname = _pinned_url(original_url, ip)
        try:
            if method == "GET":
                async with client.stream(
                    method,
                    pinned_url,
                    timeout=8.0,
                    headers={
                        "Host": host_header,
                        "Range": "bytes=0-0",
                        "User-Agent": "CMPYS-CurriculumSourceCheck/1.0",
                    },
                    extensions={"sni_hostname": sni_hostname},
                ) as response:
                    return response.status_code, response.headers.get("location")
            response = await client.request(
                method,
                pinned_url,
                timeout=8.0,
                headers={
                    "Host": host_header,
                    "User-Agent": "CMPYS-CurriculumSourceCheck/1.0",
                },
                extensions={"sni_hostname": sni_hostname},
            )
            return response.status_code, response.headers.get("location")
        except (httpx.HTTPError, OSError):
            continue
    return None


async def resolve_public_source_url(
    provider_url: str,
    *,
    max_redirects: int = 5,
) -> str | None:
    """Resolve a grounding redirect without ever following it into private IPs."""
    current = provider_url.strip()
    for _ in range(max_redirects + 1):
        # A fresh, proxy-disabled pool per hop prevents same-IP cross-host
        # connection reuse from bypassing the newly validated Host/TLS SNI.
        async with httpx.AsyncClient(
            follow_redirects=False,
            trust_env=False,
        ) as client:
            try:
                parsed = urlsplit(current)
                port = parsed.port
            except ValueError:
                return None
            allowed_port = (
                parsed.scheme == "https" and port in {None, 443}
            ) or (parsed.scheme == "http" and port in {None, 80})
            if not allowed_port or not is_direct_resource_url(current):
                return None
            # The HTTP connection uses this exact validated address rather than
            # resolving the hostname a second time (DNS-rebinding/TOCTOU guard).
            ips = await _resolved_public_ips(current)
            if not ips:
                return None
            result = await _request_pinned(
                client,
                method="HEAD",
                original_url=current,
                ips=ips,
            )
            if result is None:
                return None
            status_code, location = result
            if status_code in {405, 501}:
                result = await _request_pinned(
                    client,
                    method="GET",
                    original_url=current,
                    ips=ips,
                )
                if result is None:
                    return None
                status_code, location = result
            if status_code in {301, 302, 303, 307, 308} and location:
                current = urljoin(current, location)
                continue
            if 200 <= status_code < 400:
                return current
            return None
    return None


def _segment_text(support: Any, synthesis: str) -> str:
    segment = getattr(support, "segment", None)
    text = str(getattr(segment, "text", None) or "").strip()
    if text:
        return text
    start = getattr(segment, "start_index", None)
    end = getattr(segment, "end_index", None)
    if isinstance(start, int) and isinstance(end, int) and 0 <= start < end:
        return synthesis[start:end]
    return ""


def _grounding_sources(response: Any, synthesis: str) -> tuple[tuple[GroundedSource, ...], tuple[str, ...]]:
    by_url: dict[str, dict[str, Any]] = {}
    queries: set[str] = set()
    for candidate in getattr(response, "candidates", None) or []:
        metadata = getattr(candidate, "grounding_metadata", None)
        if metadata is None:
            continue
        chunks = list(getattr(metadata, "grounding_chunks", None) or [])
        for query in getattr(metadata, "web_search_queries", None) or []:
            if str(query).strip():
                queries.add(str(query).strip())
        for index, chunk in enumerate(chunks):
            web = getattr(chunk, "web", None)
            url = str(getattr(web, "uri", None) or "").strip()
            if not is_direct_resource_url(url):
                continue
            entry = by_url.setdefault(
                url,
                {
                    "title": sanitize_external_text(
                        getattr(web, "title", None) or url, max_chars=500
                    ),
                    "supports": [],
                    "indices": set(),
                    "confidences": [],
                },
            )
            entry["indices"].add(index)
        for support in getattr(metadata, "grounding_supports", None) or []:
            text = sanitize_external_text(_segment_text(support, synthesis))
            if not text:
                continue
            indices = list(getattr(support, "grounding_chunk_indices", None) or [])
            scores = list(getattr(support, "confidence_scores", None) or [])
            for position, index in enumerate(indices):
                if not isinstance(index, int) or index < 0 or index >= len(chunks):
                    continue
                web = getattr(chunks[index], "web", None)
                url = str(getattr(web, "uri", None) or "").strip()
                if url in by_url:
                    by_url[url]["supports"].append(text)
                    if position < len(scores):
                        try:
                            by_url[url]["confidences"].append(float(scores[position]))
                        except (TypeError, ValueError):
                            pass

    sources: list[GroundedSource] = []
    for url, item in by_url.items():
        support_text = sanitize_external_text(
            " ".join(dict.fromkeys(item["supports"])), max_chars=2500
        )
        # A URL in metadata without a provider-attributed support span cannot
        # ground a claim and is deliberately excluded from the manifest.
        if len(support_text) < 20:
            continue
        source_id = _source_id(url)
        sources.append(
            GroundedSource(
                source_id=source_id,
                title=item["title"] or url,
                url=url,
                support_text=support_text,
                content_hash=sha256_json(
                    {"title": item["title"], "url": url, "support_text": support_text}
                ),
                grounding_confidence=(
                    max(item["confidences"]) if item["confidences"] else None
                ),
            )
        )
    return tuple(sources), tuple(sorted(queries))


async def discover_grounded_sources(
    *,
    module_target: dict[str, Any],
    tier: str,
    telemetry_metadata: dict[str, Any] | None = None,
    usage_sink: list[dict[str, Any]] | None = None,
) -> GroundedDiscovery:
    if not settings.gemini_api_key:
        raise GroundingUnavailableError(
            "GEMINI_API_KEY is required for autonomous curriculum source discovery"
        )
    system_prompt = load_prompt("curriculum_research_system")
    user_prompt = load_and_render(
        "curriculum_research_discovery",
        {
            "module_target_json": module_target,
            "approved_technique_registry_json": [
                item.model_dump(mode="json") for item in TECHNIQUE_REGISTRY
            ],
        },
    )
    client = _gemini_client()
    model = _model_for_tier(tier)
    thinking_level, thinking_budget = resolve_thinking_config(
        model=model,
        tier=tier,
        thinking_level="low",
        thinking_budget=None,
    )
    started = time.perf_counter()
    response = await client.aio.models.generate_content(
        model=model,
        contents=user_prompt,
        config=types.GenerateContentConfig(
            system_instruction=system_prompt,
            tools=[types.Tool(google_search=types.GoogleSearch())],
            max_output_tokens=4000,
            http_options=types.HttpOptions(timeout=GEMINI_REQUEST_TIMEOUT_MS),
            **generation_config_kwargs(
                model=model,
                temperature=0.2,
                thinking_level=thinking_level,
                thinking_budget=thinking_budget,
            ),
        ),
    )
    synthesis = str(response.text or "").strip()
    provider_sources, queries = _grounding_sources(response, synthesis)
    resolution_results = await asyncio.gather(
        *(resolve_public_source_url(source.url) for source in provider_sources)
    )
    checked_at = datetime.now(timezone.utc).isoformat()
    sources: tuple[GroundedSource, ...] = tuple(
        GroundedSource(
            source_id=_source_id(canonical_url),
            title=source.title,
            url=canonical_url,
            support_text=source.support_text,
            content_hash=sha256_json(
                {
                    "title": source.title,
                    "url": canonical_url,
                    "support_text": source.support_text,
                }
            ),
            provenance=source.provenance,
            provider_url=source.url,
            checked_at=checked_at,
            grounding_confidence=source.grounding_confidence,
        )
        for source, canonical_url in zip(provider_sources, resolution_results, strict=True)
        if canonical_url is not None
    )
    usage = getattr(response, "usage_metadata", None)
    prompt_tokens = getattr(usage, "prompt_token_count", None)
    completion_tokens = getattr(usage, "candidates_token_count", None)
    total_tokens = getattr(usage, "total_token_count", None)
    estimated_cost = estimate_curriculum_grounded_cost_usd(
        model=model,
        prompt_tokens=prompt_tokens,
        completion_tokens=completion_tokens,
        total_tokens=total_tokens,
        search_queries=len(queries),
    )
    if usage_sink is not None:
        usage_sink.append(
            {
                "operation": "curriculum_grounded_research",
                "model": model,
                "provider": "gemini",
                "input_tokens": int(prompt_tokens or 0),
                "output_tokens": int(completion_tokens or 0),
                "total_tokens": int(total_tokens or 0),
                "estimated_cost_usd": estimated_cost,
                "search_queries": len(queries),
            }
        )
    await record_usage_records(
        [
            UsageRecord(
                operation="curriculum_grounded_research",
                model=model,
                provider="gemini",
                prompt_tokens=prompt_tokens,
                completion_tokens=completion_tokens,
                total_tokens=total_tokens,
                estimated_cost_usd=estimated_cost,
                duration_ms=(time.perf_counter() - started) * 1000,
                grounded=True,
                search_queries=len(queries),
                success=bool(synthesis and sources),
                result_status="grounded" if synthesis and sources else "insufficient_grounding",
                metadata={
                    "stage": "research_manifest",
                    "grounded_source_count": len(sources),
                    "provider_grounding_chunk_count": len(provider_sources),
                    **(telemetry_metadata or {}),
                },
            )
        ]
    )
    if not synthesis or len(sources) < 2:
        raise GroundingUnavailableError(
            "grounded discovery returned fewer than two source-backed support spans"
        )
    return GroundedDiscovery(synthesis, sources, queries, model)


def approved_technique_sources() -> tuple[GroundedSource, ...]:
    """Server-owned seed sources; valid without claiming a live web retrieval."""
    sources: dict[str, GroundedSource] = {}
    for entry in TECHNIQUE_REGISTRY:
        excerpt = sanitize_external_text(
            "Implementation: "
            + " ".join(entry.implementation_contract)
            + " Limitations: "
            + " ".join(entry.limitations)
        )
        for url in entry.source_urls:
            source_id = _source_id(url)
            sources.setdefault(
                url,
                GroundedSource(
                    source_id=source_id,
                    title=f"Approved evidence source for {entry.technique_id.value}",
                    url=url,
                    support_text=excerpt,
                    content_hash=sha256_json(
                        {"title": entry.technique_id.value, "url": url, "support_text": excerpt}
                    ),
                    provenance="approved_technique_registry",
                    provider_url=None,
                    checked_at=None,
                    grounding_confidence=None,
                ),
            )
    return tuple(sources.values())


def required_planner_technique_sources() -> tuple[GroundedSource, ...]:
    """Keep one exact registry URL available for every selectable technique."""
    by_url = {source.url: source for source in approved_technique_sources()}
    selected: dict[str, GroundedSource] = {}
    for entry in TECHNIQUE_REGISTRY:
        source = by_url[entry.source_urls[0]]
        selected.setdefault(source.url, source)
    return tuple(selected.values())


async def curate_research_manifest(
    *,
    module_target: dict[str, Any],
    discovery: GroundedDiscovery,
    tier: str,
    telemetry_metadata: dict[str, Any] | None = None,
    usage_sink: list[dict[str, Any]] | None = None,
) -> ResearchManifest:
    qualified_live_ids = {
        source.source_id
        for source in discovery.sources
        if _domain_claim_eligible(source)
    }
    if not qualified_live_ids:
        # The control loop treats this source-research failure as retryable and
        # performs a fresh grounded discovery. Never ask the curator to invent
        # a source or silently weaken the publication invariant.
        raise GroundingUnavailableError(
            "grounded discovery returned no deterministically qualified live source"
        )
    allowed_sources = {source.source_id: source for source in discovery.sources}
    for source in approved_technique_sources():
        allowed_sources.setdefault(source.source_id, source)
    source_catalog = [
        {
            "source_id": source.source_id,
            "title": source.title,
            "url": source.url,
            "support_text": source.support_text,
            "provenance": source.provenance,
            "provider_provenance_url": source.provider_url,
            "access_checked_at": source.checked_at,
            "grounding_confidence": source.grounding_confidence,
            "domain_claim_eligible": source.source_id in qualified_live_ids,
        }
        for source in allowed_sources.values()
    ]
    client = get_llm_client(
        tier=tier,
        timeout=90,
        max_tokens=7000,
        temperature=0.1,
    )
    validated, response = await client.generate_and_validate(
        system_prompt=load_prompt("curriculum_writer_system"),
        user_prompt=load_and_render(
            "curriculum_research_curate",
            {
                "module_target_json": module_target,
                "grounded_synthesis": sanitize_external_text(
                    discovery.synthesis, max_chars=12000
                ),
                "server_owned_source_catalog_json": source_catalog,
            },
        ),
        output_model=ResearchCuration,
        repair_on_failure=True,
    )
    await record_llm_response(
        operation="curriculum_research_curation",
        response=response,
        model=getattr(client, "model", None),
        result_status="schema_valid" if validated else "failed",
        metadata={
            "stage": "research_manifest",
            "source_count": len(source_catalog),
            **(telemetry_metadata or {}),
        },
    )
    if validated is None or response.error:
        raise RuntimeError(response.error or "research curation failed")
    if usage_sink is not None:
        usage_sink.append(
            {
                "operation": "curriculum_research_curation",
                "model": str(response.model or getattr(client, "model", None) or "unknown"),
                "provider": response.provider,
                "input_tokens": int(response.prompt_tokens or 0),
                "output_tokens": int(response.completion_tokens or 0),
                "total_tokens": int(response.total_tokens or 0),
            }
        )
    curation = ResearchCuration.model_validate(validated)
    annotation_ids = {item.source_id for item in curation.source_annotations}
    referenced_ids = {
        source_id for claim in curation.claims for source_id in claim.source_ids
    }
    required_registry_ids = {
        source.source_id for source in required_planner_technique_sources()
    }
    selected_ids = referenced_ids | required_registry_ids
    if len(selected_ids) > 30:
        raise ValueError(
            "claim sources plus required technique evidence exceed manifest capacity"
        )
    selected_ids |= set(sorted(annotation_ids - selected_ids)[: 30 - len(selected_ids)])
    missing = sorted(selected_ids - set(allowed_sources))
    if missing:
        raise ValueError(f"curator referenced non-grounded source ids: {missing}")
    annotations = {item.source_id: item for item in curation.source_annotations}
    if referenced_ids - set(annotations):
        raise ValueError("every claim source requires a source annotation")

    source_rows = []
    for source_id in sorted(selected_ids):
        source = allowed_sources[source_id]
        annotation = annotations.get(source_id)
        source_rows.append(
            EvidenceSource(
                source_id=source.source_id,
                title=source.title,
                url=source.url,
                source_type=deterministic_source_classification(source)[0],
                evidence_tier=deterministic_source_classification(source)[1],
                # Search grounding proves relevance, not a reuse license. Keep
                # all live and deterministic bibliography entries citation-only
                # until a server-side license verifier says otherwise.
                rights_status=RightsStatus.CITATION_ONLY,
                publisher=annotation.publisher if annotation else None,
                author=annotation.author if annotation else None,
                published_at=annotation.published_at if annotation else None,
                checked_at=source.checked_at,
                provider_provenance_url=source.provider_url,
                sanitized_support_text=source.support_text,
                source_text_kind=(
                    "approved_registry_summary"
                    if source.provenance == "approved_technique_registry"
                    else "provider_grounded_support"
                ),
                classification_provenance=deterministic_source_classification(source)[2],
                grounding_confidence=source.grounding_confidence,
                content_hash=source.content_hash,
            ).model_dump(mode="json")
        )
    manifest = sanitize_research_manifest(
        {
            "research_question": curation.research_question,
            "sources": source_rows,
            "claims": [claim.model_dump(mode="json") for claim in curation.claims],
            "limitations": curation.limitations,
        }
    )
    # Final provenance invariant: each saved URL came from provider metadata or
    # the versioned approved seed. A model-emitted URL can never enter this set.
    provenance_urls = {source.url for source in allowed_sources.values()}
    if any(source.url not in provenance_urls for source in manifest.sources):
        raise AssertionError("manifest contains a URL outside trusted provenance")
    return manifest


_CLAIM_STOPWORDS = {
    "about", "after", "also", "and", "are", "because", "before", "being",
    "between", "from", "have", "into", "that", "the", "their", "there",
    "these", "this", "through", "using", "when", "where", "which", "with",
}


def _claim_support_overlap(claim: str, support_text: str) -> float:
    import re

    def tokens(value: str) -> set[str]:
        return {
            token
            for token in re.findall(r"[a-z0-9]+", value.casefold())
            if len(token) >= 4 and token not in _CLAIM_STOPWORDS
        }

    claim_tokens = tokens(claim)
    if not claim_tokens:
        return 0.0
    return len(claim_tokens & tokens(support_text)) / len(claim_tokens)


async def verify_research_manifest(
    *,
    manifest: ResearchManifest,
    tier: str,
    telemetry_metadata: dict[str, Any] | None = None,
    usage_sink: list[dict[str, Any]] | None = None,
) -> ResearchManifest:
    source_by_id = {source.source_id: source for source in manifest.sources}
    verification_pack = [
        {
            "claim": claim.model_dump(mode="json"),
            "bound_sources": [
                {
                    "source_id": source_id,
                    "title": source_by_id[source_id].title,
                    "support_text": source_by_id[source_id].sanitized_support_text,
                    "source_text_kind": source_by_id[source_id].source_text_kind,
                    "grounding_confidence": source_by_id[source_id].grounding_confidence,
                }
                for source_id in claim.source_ids
            ],
        }
        for claim in manifest.claims
    ]
    client = get_llm_client(
        tier=tier,
        timeout=90,
        max_tokens=7000,
        temperature=0.0,
    )
    validated, response = await client.generate_and_validate(
        system_prompt=load_prompt("curriculum_writer_system"),
        user_prompt=load_and_render(
            "curriculum_research_verify",
            {"claim_support_pack_json": verification_pack},
        ),
        output_model=ClaimVerificationBundle,
        repair_on_failure=True,
    )
    await record_llm_response(
        operation="curriculum_research_claim_verification",
        response=response,
        model=getattr(client, "model", None),
        result_status="schema_valid" if validated else "failed",
        metadata={
            "stage": "source_research",
            "claim_count": len(manifest.claims),
            **(telemetry_metadata or {}),
        },
    )
    if validated is None or response.error:
        raise RuntimeError(response.error or "claim verification failed")
    if usage_sink is not None:
        usage_sink.append(
            {
                "operation": "curriculum_research_claim_verification",
                "model": str(response.model or getattr(client, "model", None) or "unknown"),
                "provider": response.provider,
                "input_tokens": int(response.prompt_tokens or 0),
                "output_tokens": int(response.completion_tokens or 0),
                "total_tokens": int(response.total_tokens or 0),
            }
        )
    bundle = ClaimVerificationBundle.model_validate(validated)
    by_claim = {item.claim_id: item for item in bundle.verifications}
    if set(by_claim) != {claim.claim_id for claim in manifest.claims}:
        raise ValueError("claim verifier must return every and only manifest claim ID")
    verified_claims = []
    for claim in manifest.claims:
        verification = by_claim[claim.claim_id]
        if not set(verification.supported_source_ids).issubset(claim.source_ids):
            raise ValueError("claim verifier invented or rebound a source ID")
        support = " ".join(
            source_by_id[source_id].sanitized_support_text
            for source_id in verification.supported_source_ids
        )
        lexical_overlap = _claim_support_overlap(claim.statement, support)
        if (
            not verification.passed
            or verification.confidence < 0.80
            or not verification.supported_source_ids
            or lexical_overlap < 0.35
        ):
            raise ValueError(
                f"claim {claim.claim_id} failed independent source verification"
            )
        verified_claims.append(
            claim.model_copy(
                update={
                    "verification_score": verification.confidence,
                    "verification_note": sanitize_external_text(
                        (
                            f"{verification.reasoning} "
                            f"Deterministic lexical overlap={lexical_overlap:.2f}."
                        ),
                        max_chars=800,
                    ),
                }
            )
        )
    return manifest.model_copy(update={"claims": verified_claims})


async def build_research_manifest(
    *,
    module_target: dict[str, Any],
    research_tier: str,
    curation_tier: str = "fast",
    verification_tier: str = "quality",
    telemetry_metadata: dict[str, Any] | None = None,
    usage_sink: list[dict[str, Any]] | None = None,
) -> ResearchManifest:
    discovery = await discover_grounded_sources(
        module_target=module_target,
        tier=research_tier,
        telemetry_metadata=telemetry_metadata,
        usage_sink=usage_sink,
    )
    manifest = await curate_research_manifest(
        module_target=module_target,
        discovery=discovery,
        tier=curation_tier,
        telemetry_metadata=telemetry_metadata,
        usage_sink=usage_sink,
    )
    return await verify_research_manifest(
        manifest=manifest,
        tier=verification_tier,
        telemetry_metadata=telemetry_metadata,
        usage_sink=usage_sink,
    )
