# Book narration diagnosis — 26 September 2026

Resolved later the same day by the authorized direct Google Gemini migration.
See [Gemini narration release](2026-09-26-gemini-book-narration.md) for deployment
and live playback evidence. The diagnosis below records the original failure.

## Confirmed external failure

Two short synthetic requests to the configured Yunwu MiniMax route returned HTTP 403. The provider explicitly reported that the account had migrated to OpenLux and the old site was read-only. No audio was returned.

The app's existing OpenLux secret authenticated successfully, but its model catalog contains only text/code models. A short MiniMax request returned HTTP 404, `model_not_found`, with no available channel for the current token. The original Yunwu token returned HTTP 401 on OpenLux. Merely replacing the hostname would not restore narration.

Existing audio delivery is healthy: both internal and public routes returned HEAD 200 and Range GET 206 with `audio/mpeg`, byte ranges, and the requested 1,024-byte payload. No learner answers or task-completion state were changed during diagnosis.

## Completed fixes

- Preserve valid generated audio when the provider omits subtitles.
- Reuse cached audio without timing rather than synthesizing and billing for it again.
- Allow valid cache hits while provider credentials are unavailable.
- Record sanitized error categories and HTTP/provider status without passage text, keys, or response bodies.
- Support explicit OpenLux MiniMax configuration independently of the planning LLM, with separate credentials and cache provenance. Defaults and production routing remain unchanged because speech access is unavailable.
- Observe native player error events, end stuck buffering safely, ignore stale callbacks, and allow a manual retry using prepared clips.
- Give narration preparation a bounded 90-second client timeout for synthesis and timing enrichment.
- Clear stale synchronized-highlighting claims when a clip has no provider timing.

## Validation

- Backend full suite including PostgreSQL: **1,700 tests passed**, one existing dependency deprecation warning.
- Flutter full suite: **339 tests passed**; focused narration suite: **42 passed**; static analysis clean.
- Updated iOS simulator build installed successfully and opened the book reader with available playback controls. New upstream audio playback is not claimed as restored.
- Independent review cleared the changes. Repository whitespace checks passed.
- Backend release **`cmpys-backend:20260926-151347`** deployed successfully. API, PostgreSQL, Redis, all worker queues, and scheduler health checks passed; a separate readiness request passed.

New narration remains blocked by voice-provider access. These resilience changes do not restore an unavailable upstream speech channel.

## Provider recommendation

Audition Google's direct Gemini 3.8 Flash TTS for expressive long-form narration. Official standard pricing is $9 per million audio tokens through December 31, 2026, then $18 from January 1, 2027. At the documented 25 audio tokens per second, this is $0.81/hour now and $1.62/hour later, plus text input. Flash-Lite is $0.54/hour now and $1.08/hour later.

MiniMax direct Speech 2.8 Turbo costs $60 per million characters and HD costs $100. At an illustrative 150 words/minute and six characters per word including spaces, that is $3.24/hour and $5.40/hour respectively. Rates exclude retries, separate alignment, storage, delivery, and taxes. Reusing cached shared recordings avoids synthesis charges on each replay.

The existing Google credential can read the Gemini 3.8 Flash TTS model metadata, but no Google audio synthesis, quality audition, adapter implementation, or production provider switch has occurred. Native word alignment is not established by the Google TTS documentation reviewed; accurate highlighting needs a verified alignment step.

Sources: [Google pricing](https://ai.google.dev/gemini-api/docs/pricing), [Google narration model](https://ai.google.dev/gemini-api/docs/models/gemini-3.8-flash-tts), [MiniMax pricing](https://platform.minimax.io/docs/guides/pricing-paygo).
