# CMPYS Prompt Quality & Performance Audit

**Date:** 2026-07-12  
**Scope:** prompt library, LLM orchestration, FastAPI hot paths, Flutter startup/stream rendering, and quality enforcement

## Executive verdict

CMPYS's correct product spine is:

1. **Agentic activation:** evidence-grounded mentor selection, diagnostic interview, age-matched comparison, and a concise strategic verdict.
2. **Twelve-week execution:** a separate, complete plan containing weekly missions, daily rhythms, deep lessons, real materials, and binary completion criteria.
3. **Daily retention:** one current focus, sequential lessons, progress, streaks, and mentor support.

The prior prompts partially blurred the first two stages: the blueprint generated another detailed roadmap and resource list even though the plan generator owned the same work. Persona prompts also prioritized theatrical immersion over a truthful AI-portrayal boundary, and several generated JSON contracts did not match their runtime schemas.

The revised system now matches the product spine. The blueprint is a 350-550-word strategic verdict; the plan is the only execution artifact; plan lessons retain the 1,200-1,800-word teaching requirement plus timed practice; and book modules retain the 3,200-word minimum. Performance work removes redundant search/model calls, prompt duplication, database checkout time, logging work, and per-token UI rebuilds without reducing these content-depth requirements.

## Prompt-quality findings and resolutions

| Area | Previous risk | Resolution and enforcement |
|---|---|---|
| Blueprint vs plan | Two overlapping 12-week roadmaps, duplicated resources and tasks | Blueprint now contains strategic verdict, thesis, phase intent, guardrails, and closing only. Plan owns all tasks, lessons, schedules, resources, and completion criteria. |
| Mentor identity | Some prompts instructed the model to deny being AI or act as the literal person | Persona, interview, tutor, and no-persona fallback now describe a truthful AI portrayal. They remain immersive in ordinary mentoring and answer identity questions plainly. |
| Interview facts | Live search ran again on every interview response and could conflict with the prefetched fact sheet | One grounded fact sheet is reused; interview turns use supplied verified facts only. |
| Persona extraction | Prompt schema did not match `PersonaPackResponse`/`Evidence`; signature phrases could be reconstructed | Exact `persona` wrapper and Evidence fields are required. Signature phrases must be verbatim source substrings with matching evidence. |
| Comparison | `comparison_analyze.txt` was missing while the endpoint expected it | Added an evidence-only, same-age, context-aware, non-shaming JSON contract with strict schema validation. |
| Partial dates | Month/year dates were discarded, causing age evidence loss or model date arithmetic | Partial dates retain sentinel storage plus explicit precision; backend computes ages deterministically and rejects ambiguous value phrases as ages. |
| Plan capacity | Contradictory task-count rules could overfill low-capacity weeks | One authoritative rule: under six hours uses one mission plus one daily rhythm; six or more uses two-to-three missions plus one-to-two daily rhythms. Weekly totals are validated after integer storage rounding. |
| Plan completeness | Nonempty but incomplete plans could be persisted | The API is fixed to a twelve-week cycle. Runtime validation requires ordered weeks 1-12, capacity-specific task counts, success metrics, daily scripts, description depth, and the weekly hour cap. Invalid plans receive one issue-specific retry; the deterministic fallback now preserves the same weekly shape. |
| Deep lesson quality | Structural JSON success did not guarantee lesson depth or correct material composition | Native schema plus deterministic validation requires three 1,200-1,800-word lessons, all seven reader headings, actionable 20-50-word substeps, exact material references, and exactly one book, one relevant video, and one allowed third material. Semantic failures receive quality feedback, not a generic JSON retry. |
| Deferred books | Faster background book generation could leave the plan permanently linked to a search page | Materials retain a canonical key. The client late-binds the generated, published content-resource ID on tap and opens the in-app book reader when the quality-gated module is ready. |
| Prompt injection | Planner context was called “binding” without a system-level data boundary | Planner system prompt now treats every profile, source, transcript, verdict, blueprint, goal, and prior-cycle note as untrusted data. User-authored/free-text fields are delimiter-wrapped where appropriate. |

## Measured baseline

These figures come from local historical logs, not a post-deployment production benchmark.

- **112 structured Gemini calls:** mean 20.0 s, p50 about 18.5 s, p95 about 32.1 s, maximum 54.0 s.
- **Output size was the dominant model-latency signal:** completion tokens correlated with latency at `r=0.844`; prompt tokens did not in this sample (`r=-0.070`).
- **Five calls with at least 5,000 completion tokens** were 4.5% of calls but consumed 11.1% of total model time and averaged 49.7 s.
- **Result generation:** 15 historical `/generate-results` calls had p50 31.7 s and p95 43.7 s.
- **20,079 HTTP traces:** p50 19.3 ms and p95 104.9 ms. Ordinary HTTP was not the primary user-perceived bottleneck.
- **Job polling dominated request volume:** 14,675 GETs. Successful job GET/OPTIONS records represented 72.1% of traces and 75.1% of parsed request-log bytes.
- **Lazy media generation:** historical missing-image requests reached roughly 9.2-10.0 s while using a synchronous SDK call inside an async route.

## Performance changes and expected impact

### Model and search work

- A fresh five-turn activation flow now uses grounded search on **2 of 8 model responses instead of 8 of 8**: one fact lookup and the comparison remain grounded. This is a 75% reduction in search-enabled calls while preserving the two places where live evidence adds quality.
- Blueprint output is capped at 350-550 words and no longer performs resource search; long-form execution moves to the plan where it belongs.
- Decorative OpenAI “thinking” generations were removed from ingestion and lesson-detail jobs. Polling already supplies deterministic progress narratives, so these calls added cost and database churn without improving the artifact.
- Direct YouTube search/oEmbed runs before a grounded model lookup, but only wins when oEmbed title/creator metadata matches the requested resource. A miss or irrelevant result still uses the grounded fallback.
- Structured outputs now use native schemas for plan details, reducing malformed-JSON repair calls while retaining semantic quality validation.
- Gemini calls are bounded by a 60-second SDK timeout.

### Prompt and serialization work

- Compact UTF-8 JSON reduced six representative fixture serializations from **13,471 to 10,022 bytes (-25.6%)**.
- A synthetic five-turn interview render dropped from **12,752 to 7,786 bytes (-38.9%)** because transcript content is included once instead of three times. This is a prompt-size estimate, not a live provider-latency measurement.
- The interview system template itself is 24.4% smaller.
- Static tracked prompt text grew about 3.2% (about 5.0% including the newly restored comparison prompt). That is intentional: stronger evidence, identity, security, and quality contracts add a small fixed input cost while avoiding expensive bad outputs and retries.

### Backend request paths

- Scalar authentication/session relationships use joined loading, removing extra round trips from every authenticated/session fetch.
- Read/write transactions are committed before interview, result, tutor, material, feed, suggestion, and legacy comparison model calls. Historical eligible calls account for an upper bound of roughly 792.5 connection-seconds that no longer need to monopolize pooled connections. This improves concurrency rather than individual model latency.
- Known plan-job polling uses one typed joined query instead of an import miss followed by a plan query.
- Successful high-frequency job polls are omitted from request logs; failures remain visible. Replay accounting estimates that body suppression plus quiet polling would reduce parsed request-log volume by about 87.5%.
- Request-log file writes run on a background listener thread, response/request bodies are not copied in production by default, and large responses use balanced gzip compression.
- Missing-image generation reuses the Gemini client, releases its database connection, has a timeout, and runs the synchronous image SDK/file write off the asyncio event loop.

### Flutter client

- Returning-launch splash minimum is about 600 ms instead of 3.4 s; first launch preserves the full branded introduction. Session initialization runs in parallel with the splash gate.
- Results, interview, and chat streams use `StringBuffer` and publish at most once per 60 ms after the immediate first chunk. Final text is flushed exactly, so batching changes render frequency, not content.
- Streaming scroll work is limited to one callback per frame.
- High-frequency Riverpod subscriptions select only fields used by Today, Plan, You, and plan state.
- Plan status and current-plan requests begin in parallel, unchanged poll states do not rebuild UI, and polls include `type=plan`.
- Release builds require an explicit `API_BASE_URL`; Android declares Internet permission; router/Dio diagnostics are debug-only; credential/token logs were removed.

## Quality preserved deliberately

The main remaining slow path is intentional: one plan mission contains three complete lessons of 1,200-1,800 words each plus 30-45 minutes of guided practice. Historical 5,000+ token outputs approached 50 seconds. Shortening these artifacts would make the application faster by breaking its primary trust promise, so this audit optimizes orchestration, retries, search, rendering, and caching around them instead.

The following boundaries are now enforced in code rather than left to prompt compliance:

- exactly one ordered twelve-week cycle;
- weekly capacity/count/hour rules;
- three complete lesson-reader modules and exact resource composition;
- published quality-gated book resources before the in-app reader opens;
- deterministic same-age calculation for partial dates;
- structured comparison and persona response schemas.

## Verification

- Backend: **327 tests passed**; the full application and test tree passes Ruff; compile check passed.
- Flutter: **113 tests passed**; `flutter analyze` reports no issues.
- Release-mode web build succeeded with an explicit API base URL.
- Android release compilation could not run because the local environment has no Android SDK; the release URL guard and Android manifest are covered by tests/static analysis.
- `git diff --check` passes.

No live paid-provider benchmark was run during this audit. Post-deployment telemetry should compare p50/p95 time-to-first-token, total result time, repair/quality-retry rate, book-ready latency, and plan-contract failure rate against the historical baseline above.

## Remaining follow-ups

1. Bundle the five official Google Font families locally. Runtime fetching remains a startup/offline risk, but unofficial substitutes were deliberately avoided to preserve the visual system.
2. Consider replacing three-second plan polling with server push if request volume becomes operationally significant. Current work minimizes each poll's database/log cost but does not remove the network requests.
3. If the legacy `/comparison/ai` endpoint remains supported, add user/data-version-aware caching. Historical usage repeated a small number of parameter combinations, but the current Flutter app does not call this endpoint.
4. Re-run an Android release build on a machine with the SDK and benchmark on a mid-range physical device using profile/release mode.
