"""Shared helpers for serializing chat threads into prompt-ready transcripts."""
import json

from app.models.chat import ChatMessage
from app.services.llm.prompt_loader import sanitize_untrusted_input


def build_chat_history_json(
    messages: list[ChatMessage],
    max_chars: int | None = None,
    sanitize_user: bool = False,
) -> str:
    """Build a JSON string of chat history for prompt injection.

    When ``max_chars`` is set, drops the oldest messages until the serialized
    transcript fits — recent turns carry the most diagnostic signal.

    When ``sanitize_user`` is True, user-authored turns are wrapped with the
    untrusted-input delimiters so the model treats them as DATA, not
    instructions (prompt-injection defense). Assistant turns are model-generated
    and left as-is. Default False preserves the plain serialization used by
    callers that don't embed the transcript in an instruction-following prompt.
    """
    def _content(msg: ChatMessage) -> str:
        if sanitize_user and msg.role.value == "user":
            return sanitize_untrusted_input(msg.content)
        return msg.content

    history = [
        {"role": msg.role.value, "content": _content(msg)}
        for msg in messages
    ]
    serialized = json.dumps(
        history,
        ensure_ascii=False,
        separators=(",", ":"),
    )
    if max_chars is None:
        return serialized

    while history and len(serialized) > max_chars:
        history.pop(0)
        serialized = json.dumps(
            history,
            ensure_ascii=False,
            separators=(",", ":"),
        )
    return serialized
