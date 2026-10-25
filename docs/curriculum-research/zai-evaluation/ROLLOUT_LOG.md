# Z.ai production rollout — 15 September 2026

Requested scope: deploy the tested direct Z.ai models, without Qwen, and verify the production application paths.

## Configuration and implementation

- `LLM_PROVIDER=zai`: GLM-5.3 for balanced/quality generation; GLM-5.3-Flash for the fast tier, onboarding conversation and tutoring chat.
- Credential resolved from the existing encrypted AWS Secrets Manager application secret. No key in source, Docker image, dotenv, or this report.
- Existing search/grounding integration retained. Z.ai failures do not implicitly trigger a paid Gemini retry.
- Strict complete-response handling, streaming usage accounting, no hidden SDK retries, and rejection of truncated JSON.
- GLM hidden reasoning included in output reservation and cost accounting. Uncached rates are conservative when cache discounts apply.
- Practice generation allows 45 seconds for GLM within the existing 60-second operation lease. Comparison gives the single GLM call up to 40 seconds within its 45-second overall deadline.
- Existing quality gates, catalog publication rules, and unknown-charge budget holds retained.

## Verification

Full backend suite: 1,544 passed. After deadline changes: 82 targeted tests passed. After preserving the existing OpenLux error-category compatibility: 50 transport/recovery tests passed.

Initial image was built for AMD64; server pull rejected it before application changes. Rebuilt for the verified ARM64 server architecture.

Final ARM64 image digest: `sha256:a3eb0080bf34aa13d8815140b75b94cf3e6a078558ad8b9f4c8e35d240172e3a`.

Live deployment and synthetic application validation results will be appended after verification. Synthetic validation reserves at most $1 and records usage, including unknown charges on interrupted streams; it does not reset older budgets.

Deployment completed: all 9 application services are running, 7 Celery workers respond, and readiness reports healthy. Effective provider is Z.ai with Flash / GLM-5.3 / GLM-5.3 tiers. The deployment compared existing environment values and confirmed unrelated settings were preserved.

## First live application pass and corrective release

Comparison passed in 7.63 seconds and did not score absent evidence. Tutoring chat passed in 2.76 seconds (first text 2.52 seconds).

The live pass exposed issues beyond transport connectivity:
- A requested four-week plan still received a prompt insisting on twelve weeks. Made the requested duration explicit throughout the backbone prompt.
- The outline's JSON schema allowed `in_app_lesson`, while its validator rejected it. Added an outline-specific material schema and explicit resource guidance, preserving existing validation requirements.
- GLM's plan drafting exceeded the inherited 45-second primary deadline. Its initial backbone/week call now gets 90 seconds, matching the already-allowed recovery deadline, avoiding premature repeated generation.
- GLM practice generation exceeded 45 seconds at high reasoning effort. Retained GLM-5.3 and the 45-second operation bound, selecting low reasoning effort for this constrained exercise schema.

Corrective image: `zai-20260915-r2`, digest `sha256:6deb48bcf02a67f214f3c74d28e837084fae26e655b3b57322437cfc7456c12e`.
Full corrected schema/prompt regression suite: 1,545 passed. Final practice/transport subset: 62 passed.

First-pass known usage estimate: $0.02083905. Two calls ended without usage and remain unknown; conservative first-pass reservations total $0.37809525. Subsequent validation retains those reservations rather than resetting the cap.

The first corrective deployment automatically rolled back because the short worker probe did not collect all seven responses. Worker startup logs showed successful broker connections and startup; the restored deployment had all seven idle workers. Retried with an eight-second response window while retaining the seven-worker requirement. Corrective release passed on probe 2: 9 services running, 7 workers responding, readiness healthy, unrelated configuration preserved.

Correction to test interpretation: `PlanGenerateRequest.durationWeeks` allows only 12, so the four-week synthetic call in the first two passes was not a valid production request. Its phase failures are not evidence that the public twelve-week flow failed. Final verification uses twelve weeks. The duration-explicit prompt preserves the normal twelve-week behavior.

The second lesson attempt was rejected for a heading longer than the display limit. Added word-boundary shortening for generated outline headings only; the full description and lesson content remain intact. Full GLM practice still exceeded 45 seconds, so constrained workbook assembly now uses Flash; substantive text review and full lessons retain GLM-5.3. Targeted regression suite: 111 passed.

Before final verification, completed requests are settled at 125% of their returned-usage estimate. All three interrupted calls retain their full pre-request reservations. The total $1 cap is unchanged; historical call reservations remain in the report.

Final deployed image: `zai-20260915-r3`, digest `sha256:029fb14a5c8ea89276752c676bdb487cadc79322ee8e816245f894d93861d983`. Deployment passed with 9 running services, 7 responding workers, and preserved unrelated settings. Structured practice assembly uses GLM-5.3-Flash; text rubric review uses GLM-5.3.

## Full-content verification

GLM-5.3 generated one complete 2,743-word lesson in 134.34 seconds (including outline). Reader/schema gates passed. Flash generated a four-activity workbook in 39.98 seconds. All 17 fixed-answer fields correctly accepted their computed/correct answers and rejected deliberately incorrect answers.

**Manual content review did not pass.** The correct Lena reconciliation is +$500 unearned deposit − $250 additional prepaid-insurance outflow + $100 collection of an opening receivable = +$350 cash–profit difference. The generated lesson and inherited workbook explanation omit the $100 term. The workbook also asks for per-transaction column entry while that activity exposes only totals. See `production/content-review.json`. These synthetic artifacts were not published to learner accounts. Passing JSON, word-count and numeric-field validation does not establish semantic or pedagogical quality.

The public twelve-week plan timed out twice on GLM-5.3 at 90 seconds per call. The compact roadmap draft now uses Flash; detailed week expansion and long lessons retain GLM-5.3. The roadmap prompt requests concise fields, and the plan checkpoint identity includes the Flash model. A full 1,546-test backend run passed; the final cache-identity adjustment passed 11 checkpoint tests.

Final route release: `zai-20260915-r4`, digest `sha256:a5962a9aa67fe9c1b2567d7db6f4f86aa43e1d78764cb80287a9f5ee8eb01ad4`. Nine services and seven workers passed readiness.

The revised compact roadmap completed, but the expanded week was rejected for a missing success criterion and a mission summary below the existing 35-word requirement. Added generation-only `ExecutionPlanResponse` / week / task schemas: success metrics are required non-null strings, exactly one expanded week is requested, and mission text carries the existing minimum-word pattern. Historical plan readers retain their existing permissive schema. Planning regression subset: 267 passed; provider/schema subset: 11 passed.

The strict week schema then exposed a valid-length prose limit conflict: an 80–140-word description exceeded the inherited 1,000-character ceiling. Increased that ceiling to 2,000 characters; all minimum-depth and workload checks remain. Planning/schema regression subset: 325 passed. Synthetic structured responses are now retained by the validation driver so a later contract failure can be inspected without losing the draft.
