"""Durable, input-bound planning artifacts; saving never marks a plan ready."""
from copy import deepcopy
from collections.abc import Awaitable, Callable
from typing import Any
from app.services.curriculum.hashing import sha256_json


class PlanCheckpointStore:
    def __init__(self, raw: dict | None, identity: str, save: Callable[[dict], Awaitable[None]] | None):
        raw = deepcopy(raw or {})
        self.state = raw if raw.get('identity') == identity else {
            'identity': identity, 'stages': {},
            **({'operator_recovery': raw['operator_recovery']} if raw.get('operator_recovery') else {}),
        }
        self.save = save

    def load(self, stage: str) -> dict | None:
        entry = self.state.get('stages', {}).get(stage)
        if entry is None:
            return None
        if not isinstance(entry, dict) or entry.get('hash') != sha256_json(entry.get('record')):
            raise ValueError('Plan checkpoint integrity mismatch')
        return deepcopy(entry['record'])

    async def put(self, stage: str, payload: dict, **metadata: Any) -> None:
        record = {'payload': payload, **metadata}
        self.state.setdefault('stages', {})[stage] = {'record': record, 'hash': sha256_json(record)}
        if self.save:
            await self.save(deepcopy(self.state))

    async def discard(self, *stages: str) -> None:
        """Drop unusable stages while retaining input identity and valid work."""
        for stage in stages:
            self.state.setdefault('stages', {}).pop(stage, None)
        if self.save:
            await self.save(deepcopy(self.state))
