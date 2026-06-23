"""Shared helpers for serializing chat threads into prompt-ready transcripts."""
import json

from app.models.chat import ChatMessage


def build_chat_history_json(
    messages: list[ChatMessage],
    max_chars: int | None = None,
) -> str:
    """Build a JSON string of chat history for prompt injection.

    When ``max_chars`` is set, drops the oldest messages until the serialized
    transcript fits — recent turns carry the most diagnostic signal.
    """
    history = [
        {"role": msg.role.value, "content": msg.content}
        for msg in messages
    ]
    serialized = json.dumps(history, indent=2)
    if max_chars is None:
        return serialized

    while history and len(serialized) > max_chars:
        history.pop(0)
        serialized = json.dumps(history, indent=2)
    return serialized
