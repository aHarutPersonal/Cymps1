# Lesson rounding and short-draft recovery — 4 October 2026

## Incident

The first-week mission “Read The Intelligent Investor, chapters 1, 8, and 20, and write a 300-word summary” was created at 15:59 UTC and failed at 16:03 UTC. Its first generation encountered writer timeouts, a fallback lesson with 1,764 words (below the 1,900-word floor), and arithmetic review failures.

The arithmetic failures were not all equivalent. `33.333… → 33.3` was valid rounding but exceeded the review's fixed absolute tolerance of 0.01. `26.9479 → 26.97` was genuinely incorrect at the displayed two-decimal precision. The correction must distinguish these cases.

The user's existing retry completed at 16:07:04 UTC, before this fix was deployed. All three lessons were ready (2,279, 2,229 and 2,519 words). We did not enqueue another job or overwrite this recovered content. The authenticated HTTPS detailed-item endpoint returned `details_status=available` and no error.

## Changes

- Arithmetic review derives displayed precision from numeric literals in the actual lesson prose/actions, preserving trailing zeros and using the most precise spelling when the same numeric value occurs more than once. It independently recomputes and rounds the expression to that precision. A model-provided coarse spelling or permissive tolerance cannot override source precision. Correct rounding passes; incorrect signs, values and rounding remain blocked. Semantic review remains required.
- Legacy review responses without the new optional literal still work. Review telemetry uses the same normalized literal and deterministic verdict as publication.
- Structured drafts whose individual sections clear their minimums but whose total is below 1,900 words now enter targeted expansion. Previously, assembly discarded the section structure before the global word-count failure, bypassing the repair path.
- Expansion requests the fewest sections needed to clear the total floor with a small margin, then reruns the original quality gates and independent review. It retains the existing two-repair bound per writing attempt, preserves other prose/actions, and recalculates deficient fields after each attempt. It never lowers the minimum or pads content locally.
- Existing transport recovery, checkpoint reuse, and publication concurrency protections remain in place.

## Validation

- Full backend suite, including isolated PostgreSQL integration: **1,832 passed** (one existing dependency deprecation warning).
- Expanded focused review/generation suite after adding bounded-failure coverage: **87 passed**.
- Cases cover correct/incorrect rounding, trailing zeros, repeated values with different precision, negative values, grouping separators, missing source literals, and agreement between publication and telemetry.
- Generation tests cover individual and total shortfalls, successful limited expansion, unchanged actions/references, and exhausted repairs retaining the two independently completed lessons. Existing provider-timeout recovery and approved-checkpoint reuse tests also pass.
- Before deployment, no foreground plan/detail generation was active. Content and progress hashes were captured for the actual affected mission.

## Deployment and preservation

Released as `20261004-161915-reliability` using the health-checked source-overlay release procedure. API, PostgreSQL, Redis, all seven queue consumers and beat passed readiness checks. Deployed source hashes match the tested local source.

Read-only probes inside the deployed image confirmed correct rounding is accepted, genuinely wrong rounding is rejected even with a reviewer tolerance of 0.1, trailing zeros retain their precision, and a complete short draft reaches targeted section expansion.

After deployment, the actual mission's authenticated HTTPS response remained `available`, with three lessons, no details error, and its latest generation job `completed`. Before/after lesson hashes and saved practice/completion snapshots matched exactly. At this check there were no practice answers or completion records for this mission; no content, plan or progress was reset.

## Limits

This fixes two concrete failure mechanisms; it does not guarantee every provider request will succeed. No new physical iPhone UI/audio test was performed for this server-only correction. The successful real retry predates the code deployment and must not be presented as proof of a live generation using the new code.
