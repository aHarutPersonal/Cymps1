# CMPYS backend reliability and narration — 4 October 2026

## Release

Final deployed release: `20261004-143912-reliability`. Earlier validation releases: `20261004-141930-reliability`, `20261004-140859-reliability`, `20261004-133751-reliability` and `20261004-134705-reliability`. All API, database, Redis, interactive workers, catalog workers, curriculum workers and scheduler readiness checks passed. Migration head is `m4n5o6p7q8r9` (additive account-recovery fields).

The complete image upload was cancelled before production activation because transfer throughput was poor. The release was built on the server using its installed image plus a checksummed source snapshot. Dependency and startup manifests were verified byte-for-byte unchanged. The existing deployment activation procedure retained its shared lock, matching Compose backup, quiesced migrations, readiness checks and automatic rollback. Previous image: `20260926-153054`. Final source package SHA-256: `bb7c2b6773a5d5a81ff1f1959ae7ef6aafd4dd70c6386614c3fd4c2e9f7d15aa`. The immediate rollback image is `20261004-141930-reliability`; after real recovery is enabled, only auth-version-aware images are safe rollback targets.

No frontend files were modified by this backend task. iPhone installation remains deferred at the user's request.

## Fixes

- Complete provider JSON enclosed in one Markdown fence or containing literal line breaks in strings can be decoded without rewriting the answer. Truncation, commentary, multiple documents, duplicate keys and non-finite JSON constants remain rejected. Structured output and semantic validation still run. JSON failures now record safe location/type diagnostics, not provider content.
- A malformed lesson-review report gets one bounded review retry against the same lesson. A valid negative review remains a failure; it is never repeatedly requested until approved. The failed review call remains in usage telemetry.
- When otherwise approved lessons fall below the minimum real duration, only practice and its answer checks are expanded before a new independent review. Teaching prose is retained. Published time remains reading time plus independently assessed practice; the minimum is never achieved by padding numbers.
- Closing or failing a results stream cancels its owned scoring request instead of leaving an orphan provider request running.
- Gemini narration now transcribes the actual audio with `gemini-3.5-transcribe` to obtain acoustic word ranges. It uses a single bounded request (10 seconds under the deployed configuration) and `store: false`. Replays use the persisted alignment; older paid recordings are upgraded without resynthesis, with one alignment attempt per cache entry.

## Narration contract

Existing fields remain: `alignment`, `alignmentGranularity`, `alignmentSource`, `offsetEncoding`, `sourceTextHash`, `durationMs`. Source `transcription` identifies acoustic recognition, distinct from native synthesis timing. Granularity is `word`; offsets remain UTF-16 indexes into the exact requested text.

Recognized words must match the source in order, allowing only case, Unicode normalization and punctuation differences. Missing, added or substituted words reject alignment. Malformed, overlapping, negative or out-of-bounds time ranges are omitted; at least 90% of words must retain valid acoustic ranges. No missing endpoints are fabricated. A client must clear its active highlight in a cue gap and must not label text-length interpolation as measured word timing. Audio stays usable when alignment is unavailable.

Measured word ranges are estimates from speech recognition, not a guarantee of sample-exact forced alignment. Numeric verbalization and recognition mismatches may yield audio without cues. Failed alignment is cached to prevent repeated paid requests on every replay.

Primary references: [Google transcription and word annotations](https://ai.google.dev/gemini-api/docs/transcribe), [Interactions audio input](https://ai.google.dev/api/interactions-api), [Gemini TTS](https://ai.google.dev/gemini-api/docs/speech-generation).

## Validation

- Full backend suite, with isolated PostgreSQL integration enabled: **1,782 passed**, 14.62 seconds. One existing Google SDK deprecation warning.
- Narration/transcription targeted suite: **105 passed**. Includes exact source matching, Unicode/UTF-16 offsets, pause preservation, malformed final timestamps, low-coverage rejection, HTTP/timeout/body-limit failures and cache upgrades without resynthesis.
- Baseline frontend checks before the separate frontend changes: 368 tests passed, static analysis clean. These results do not validate the separate executor's later patch.
- Live synthetic narration: 10.760-second recording prepared with acoustic alignment in **6.338 seconds**. **18 of 19** words retained valid ranges; malformed last-word timing was omitted. Cached replay: **0.001 seconds**, same audio and alignment.
- Separate capability probe: synthesis **4.193 seconds**, acoustic transcription **1.089 seconds**. These are one short sample, not a percentile latency claim.
- Live registration/login/profile/refresh succeeded. A refresh token was rejected as an access token, and another synthetic account's session was not exposed.

## Baseline findings and plan measurements

On the old release, the same synthetic onboarding scenario produced results in **43.207 seconds**, but the queued plan failed after **129.079 seconds** with two malformed provider JSON responses. The original response bodies were not retained, so their exact syntax cannot be attributed to fences or literal newlines. An explicit recovery using the saved backbone completed in **40.572 seconds** of execution.

The first lesson mission then saved two approved lessons but failed its third because independently supported duration was 38 minutes against a 40-minute minimum. First-lesson checkpoint arrived after **175.191 seconds**; the final job failed at **186.754 seconds**. Repeated detail opens returned the same partial artifact and job; saved lessons remained available.

On the new release, a fresh isolated account completed all eight intake answers and results in **38.987 seconds** (results stream only). Fixed questions returned in roughly 0.04 seconds; adaptive questions took roughly 3 seconds. This single before/after sample is not a stable performance distribution. Full plan and lesson readiness are measured separately below.

## Outstanding release requirements

Public production release still requires HTTPS activation and working password-reset email delivery. Previous validation recorded pending certificate agreement authorization and no configured email provider/sender. This release does not claim those requirements are satisfied or that all possible application defects have been eliminated.

## Follow-up found by the live release test

The first fresh plan on the initial release still failed at **172.314 seconds**. The initial Z.ai roadmap call timed out at 90 seconds. Its recovery produced a week with three missions allocated 2, 2 and 1.5 hours plus a 0.5-hour daily rhythm. Integer storage resolves this to 7 hours, exceeding the requested 6. A targeted repair repeated that infeasible structure.

The follow-up makes the scheduling constraint explicit: whole integer hours, at least two hours per mission and one per daily rhythm; a six-hour week can therefore contain exactly two missions. Validation reports the minimum hours required by the selected task count, giving targeted repair an actionable correction. Z.ai compact roadmap and week expansion now request low reasoning on the same balanced model, retaining all content and workload validation; the previous medium setting mapped to high reasoning. Other providers' routing is unchanged.

Final backend regression suite after this follow-up: **1,784 passed**, 15.06 seconds. The live retry below must succeed before this issue can be considered resolved for the tested scenario.

## Final planning and queue corrections

The next live attempt exposed overly broad duplicate-title validation: a daily reflection habit repeated across different weeks caused a full-cycle rejection. Daily rhythms can now continue across weeks; duplicate missions across the cycle and duplicate tasks within a week still fail validation. The prompt also distinguishes a weekly project/application from short repeated daily practice.

An isolated server process running this final planner code and prompt regenerated the synthetic account's full roadmap plus first week in **64.040 seconds**, preserving its cached comparison. This is an execution-time measurement, not end-to-end onboarding latency or a production queue-wait benchmark. All twelve weeks have exactly **6 stored hours**. The first approved lesson became available after **150.027 seconds** on the earlier lesson pipeline; a second lesson then exhausted Z.ai timeouts, leaving the first lesson safely accessible.

Further changes address that observed wait and failure:

- Only planning uses the reserved high-priority worker. Foreground lesson opens/retries and the first prefetched lesson use the default worker; remaining current-week missions and look-ahead work use low priority. Long lessons can no longer occupy the planning worker. Existing worker topology and resources are unchanged.
- Lesson writing overlaps the independent outline/reference-link lookup. The outline is still published first; failed or cancelled publication cancels and drains the owned writers.
- A genuine sanitized Z.ai transport failure or timeout now permits one independent Gemini quality-model recovery. Lesson writing uses that recovery on its existing second attempt. Content/schema failures do not authorize a provider switch, complete output and content checks still apply, and no third writing attempt is added.

Final backend suite after these changes: **1,796 passed**, 15.04 seconds. Tests cover repeated daily habits, preserved mission uniqueness, six-hour feasibility, independent queues, concurrent reference lookup, cancellation, and outage-only recovery.

## Additional live functional checks

For the synthetic account, completed comparison status is `ready`; comparison GET returned in **0.057 seconds**, cached results replay in **0.053 seconds**, week summary in **0.049 seconds**. Profile and resource endpoints succeeded. A first cold resource-list read took 4.055 seconds; subsequent reads took **0.052–0.061 seconds** (320,566 bytes).

Practice generation for the published first lesson succeeded in **35.124 seconds**, returned two activities, and repeated preparation reused the ready workbook in **0.013 seconds**. No answers or completion records were submitted. Registration on the external route succeeded after the deployment startup window; an empty registration payload correctly returned 422, and public readiness returned 200.

## Final retry evidence

The deployed `140859` retry remained partial after **337.314 seconds**. Its first draft was correctly rejected for contradictory rubric totals; the second Z.ai writing attempt then timed out at 180 seconds. This is an unresolved live failure, not a successful recovery. The single previously published lesson retained exactly the same content hash, and repeated retry requests returned the same job rather than starting duplicate work. It became available again 15.242 seconds into the retry.

While that lesson occupied the default worker, a completed-plan redelivery was safely skipped by the separate planning worker in **9.537 seconds**. This verifies worker independence and idempotence, not fresh plan-generation latency.

The follow-up keeps Z.ai lesson corrections at low reasoning on the same quality model, instead of the high reasoning that exhausted the 180-second budget. Complete-output validation and independent content review remain required. Full suite after this change: **1,799 passed**, 14.21 seconds, one existing SDK deprecation warning.

On final release `20261004-141930-reliability`, the same synthetic mission retry **completed successfully** with two lessons and three materials. Worker execution took **104.601 seconds**; API polling observed both lessons available at **109.414 seconds**. This is a retry reusing one approved lesson, not generation of two new lessons or a fresh-user plan benchmark. Duplicate retry requests again shared one job. The previously ready lesson reappeared 18.810 seconds into retry loading.

Final-release readiness returned 200 with database and Redis healthy. Existing narration replay retained the same 18 acoustic cues and audio, taking **0.009 seconds** on its first post-release cache read and **0.001 seconds** on its next read.

Release transport was rechecked: the app's default production endpoint still uses HTTP, and the external HTTPS handshake failed. The prepared IP-certificate workflow does not require buying a domain but requires the owner's acceptance of the certificate subscriber agreement; no acceptance or security configuration change was made during this task. The repository's infrastructure has no configured API domain or email delivery resource. Password recovery is not merely a missing setting: the client explicitly reports it unavailable, and backend auth has no reset-token/email delivery flow. It requires an authorized sender/provider plus implementation and end-to-end validation. These remain concrete public-release blockers.

## Fresh-account measurement on the corrected queues

A new isolated account completed registration and the eight-answer intake through the normal deployed API. No prior plan, backbone or lesson checkpoint was copied. Measured from the start of `generate-results`, comparison/results finished in **26.567 seconds**, the new roadmap was available in **89.828 seconds**, and the first approved lesson was available in **157.910 seconds**. The plan-job event arrived at 0.084 seconds; the same roadmap/lesson intervals from that event were **89.744 / 157.825 seconds**. Polling interval was three seconds. Calls originated inside the server, so these are API-flow timings excluding mobile/WAN rendering overhead. Shared mentor/catalog data may be cached normally; this is not a cold infrastructure benchmark.

This is one fresh-run sample, distinct from the earlier recovery measurements. The frontend executor's previous five-minute first-plan observation happened before queue isolation, on a different account and scenario; these samples are not a controlled performance distribution. The restored lesson's final content-hash check also passed: its original approved prose remained unchanged.

## Account recovery follow-up

The missing recovery function identified above has now been implemented and tested, rather than left as a configuration-only claim. See [password recovery integration](2026-10-04-password-recovery.md) for the exact client contract, safeguards, limitations and required SMTP connection. The full suite after this follow-up passed **1,817 tests** in **51.04 seconds**, with one existing SDK deprecation warning. A real loopback SMTP receiver confirmed adapter delivery; PostgreSQL tests confirmed code expiry/replacement/single use and password changes, while auth tests confirmed access and refresh revocation.

Real production email remains disabled until an existing verified sender is connected and tested. No email provider was purchased, no external email was sent, and test delivery is not claimed as production delivery.

Post-deployment synthetic smoke passed registration, login, profile and token refresh. Recovery availability returned false, requests returned explicit 503, and an invalid well-formed code returned 400 through the live Redis limiter. Database migration head matched `m4n5o6p7q8r9`; all configured services passed deployment readiness.
