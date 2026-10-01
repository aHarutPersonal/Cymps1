# Gemini book narration — 26 September 2026

The owner selected direct Google Gemini TTS after the former MiniMax gateway
stopped serving this account. Narration is independent of the Zai planning LLM.

## Provider validation

A bounded, synthetic 37-word passage succeeded using the existing Google
credential and `gemini-3.8-flash-tts`, with the prebuilt Sulafat voice. Google
returned HTTP 200 with `finishReason=STOP` in 5.93 seconds, producing 16.32
seconds of mono, 24 kHz, 16-bit WAV audio (789,424 bytes). This is one measured
sample, not a latency guarantee or a subjective voice-quality benchmark.
The response reported 42 input tokens and 523 audio output tokens. Actual
provider usage should drive cost accounting; the pricing page's per-second
conversion is an estimate, not a measured invoice for this sample.

Google's current GenerateContent contract uses a verbatim text part and
`speech_metadata.style` for delivery guidance. Single-speaker selection uses
`speechConfig.voiceConfig.voice`. Unary responses contain a complete WAV
container and must not be wrapped with another WAV header.

Gemini does not provide word timestamps in this integration. The reader must
label text following as estimated and use actual audio duration for progress.

Source: [Google speech generation documentation](https://ai.google.dev/gemini-api/docs/generate-content/speech-generation).

## Release validation

- Backend full suite including PostgreSQL: **1,750 passed**, one existing dependency warning.
- Backend provider-focused checks: **139 passed**; actual Google WAV sample accepted by the new decoder without another generation.
- WAV delivery regression verifies byte-range responses used by native audio players.
- Independent backend review cleared bounded responses, complete WAV validation, credential isolation, truthful timing metadata, and legacy cache compatibility.
- Final Flutter suite: **354 passed**; **57** focused narration checks passed; static analysis clean. The final iOS simulator build is installed.
- Backend release **`cmpys-backend:20260926-153054`** deployed. API, PostgreSQL, Redis, all workers, and scheduler passed deployment health gates. A separate readiness request returned 200, and runtime configuration confirmed narration uses Gemini while planning remains Zai.
- Live deployed service generated a real 277-character book passage in **7.397 seconds**, yielding **21.08 seconds** of audio. A second identical request reused the same cached recording in **0.001 seconds**. Media returned HTTP 206, correct WAV content type, and the requested 1,024-byte range.
- Native iOS playback reached Playing with provider `gemini`, model `gemini-3.8-flash-tts`, advancing text tracking, and working pause/resume. The first full 1,144-character passage produced 78.16 seconds of audio in 24.242 seconds; initial preparation therefore still depends on passage length and provider latency.
- Fixed the live-discovered pause checkpoint defect: duplicate native clip-index events no longer reset the displayed sentence, and pause saves the actual playback offset. Final native recheck preserved the current passage and 1% progress on pause, resumed that same passage on Play, and remained correctly paused afterward.
- Generation is limited to the current clip plus two ahead while playing. Three app clips were generated and no further clips appeared while paused. In-flight work may finish; cached recordings are reusable across playback sessions.
- Final app replay uses the saved recording. No learner answers were submitted and no learning tasks were marked complete.

## Practical limits

Initial narration of an uncached passage still requires Google synthesis and
audio transfer; measured samples ranged from 7.4 to 24.2 seconds depending on
passage length. Cached service lookup is fast but does not eliminate audio
download time. Text tracking is estimated, not provider-aligned word timing.
Native playback and position behavior were verified; subjective voice quality
was not scored in a listening benchmark.
