"""Direct Z.ai GLM transport with bounded streaming and no implicit fallback."""
import asyncio
import json

from app.services.llm.client import OpenAILLMClient
from app.services.llm.openlux import OpenLuxLLMClient


class ZaiLLMClient(OpenLuxLLMClient):
    """Share strict JSON collection and usage accounting; use GLM wire options."""

    def __init__(self, *, thinking_level=None, **kwargs):
        OpenAILLMClient.__init__(self, provider_name="zai", **kwargs)
        if self.base_url != "https://api.z.ai/api/paas/v4":
            raise ValueError("Z.ai requires its direct HTTPS API endpoint")
        if self.model not in {"glm-5.3", "glm-5.3-flash"}:
            raise ValueError("Unsupported Z.ai model; validate its protocol before enabling")
        self.thinking_level = (
            "low" if thinking_level in {"none", "minimal", "low"}
            else "max" if thinking_level in {"max", "xhigh"}
            else "high"
        )

    async def _events(self, system_prompt, user_prompt, schema=None):
        from app.core.config import settings

        if not self.api_key:
            raise RuntimeError("Z.ai credential is not configured")
        if schema is not None:
            system_prompt += (
                "\nReturn one JSON object matching this schema. Use its properties "
                "as the top-level keys; do not wrap or quote the object in an answer field:\n"
            ) + json.dumps(schema)
        kwargs = {
            "model": self.model,
            "messages": [
                {"role": "system", "content": system_prompt},
                {"role": "user", "content": user_prompt},
            ],
            "stream": True,
            "max_tokens": min((self.max_tokens or 4096) + settings.zai_reasoning_token_reserve, 128000),
            "reasoning_effort": self.thinking_level,
            "extra_body": {"thinking": {"type": "enabled"}},
        }
        if schema is not None:
            kwargs["response_format"] = {"type": "json_object"}
        # Z.ai sends usage on the final streaming chunk without stream_options.
        # Never forward reasoning_content to users or application storage.
        async with asyncio.timeout(self.timeout):
            stream = await self._get_client(self.api_key).chat.completions.create(**kwargs)
            try:
                async for chunk in stream:
                    yield chunk
            finally:
                await stream.close()
