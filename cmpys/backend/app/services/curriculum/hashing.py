"""Stable content identities for the curriculum factory.

Hashes are derived from canonical JSON, never database ids, paths, or JSON key
order.  A prompt, source pack, or upstream artifact change therefore creates a
new stage input while an equivalent retry remains idempotent.
"""

from __future__ import annotations

import hashlib
import json
from dataclasses import asdict, is_dataclass
from datetime import date, datetime
from decimal import Decimal
from enum import Enum
from typing import Any
from uuid import UUID

from pydantic import BaseModel


HASH_VERSION = "curriculum-sha256-v1"


def _json_value(value: Any) -> Any:
    if isinstance(value, BaseModel):
        return _json_value(value.model_dump(mode="json"))
    if is_dataclass(value) and not isinstance(value, type):
        return _json_value(asdict(value))
    if isinstance(value, dict):
        return {
            str(key): _json_value(item)
            for key, item in sorted(value.items(), key=lambda pair: str(pair[0]))
        }
    if isinstance(value, (list, tuple)):
        return [_json_value(item) for item in value]
    if isinstance(value, (set, frozenset)):
        normalized = [_json_value(item) for item in value]
        return sorted(normalized, key=canonical_json)
    if isinstance(value, Enum):
        return _json_value(value.value)
    if isinstance(value, (datetime, date)):
        return value.isoformat()
    if isinstance(value, UUID):
        return str(value)
    if isinstance(value, Decimal):
        return format(value, "f")
    if isinstance(value, bytes):
        return value.hex()
    if value is None or isinstance(value, (str, int, float, bool)):
        return value
    raise TypeError(f"Unsupported curriculum hash value: {type(value).__name__}")


def canonical_json(value: Any) -> str:
    """Serialize a supported value deterministically as compact UTF-8 JSON."""
    return json.dumps(
        _json_value(value),
        ensure_ascii=False,
        allow_nan=False,
        separators=(",", ":"),
        sort_keys=True,
    )


def sha256_json(value: Any) -> str:
    return hashlib.sha256(canonical_json(value).encode("utf-8")).hexdigest()


def curriculum_identity_hash(
    *,
    skill_key: str,
    level: str,
    locale: str,
    learning_outcome: str,
    taxonomy_version: str,
) -> str:
    """Stable semantic identity for one canonical module target."""
    return sha256_json(
        {
            "hash_version": HASH_VERSION,
            "skill_key": skill_key.strip().casefold(),
            "level": level.strip().casefold(),
            "locale": locale.strip().replace("_", "-").casefold(),
            "learning_outcome": " ".join(learning_outcome.split()),
            "taxonomy_version": taxonomy_version.strip(),
        }
    )


def stage_input_hash(
    *,
    identity_hash: str,
    stage: str,
    pipeline_version: str,
    prompt_version: str,
    inputs: Any,
) -> str:
    """Content-address one stage, including all upstream dependencies."""
    return sha256_json(
        {
            "hash_version": HASH_VERSION,
            "identity_hash": identity_hash,
            "stage": stage,
            "pipeline_version": pipeline_version,
            "prompt_version": prompt_version,
            "inputs": inputs,
        }
    )
