# CMPYS MVP validation — 26 September 2026

Later plan-speed and waiting-screen follow-up: [validation and benchmark results](2026-09-26-plan-speed-and-waiting-screen.md). That follow-up deployed `cmpys-backend:20260926-144815`, with 1,683 backend tests and 333 Flutter tests passing. The public-release requirements below remain unchanged.

## Changes under validation

- Plan generation resumes valid saved work, repairs small scheduling arithmetic errors, and replaces unusable exhausted checkpoints on an explicit retry.
- Plans use the reserved interactive queue, have a real coroutine deadline, and record dispatch/worker failures as retryable states.
- Onboarding uses immediate questions for fixed inputs and short, bounded adaptive questions. Each question is saved before display and can be replayed after interruption.
- Mobile onboarding preserves entered information and discovery results, handles large text and the keyboard, and offers explicit recovery after connection failures.
- Authentication distinguishes access from refresh tokens, validates bcrypt input limits, and moves password hashing off the request event loop.
- Account changes clear prior local state safely, including a reset racing initial storage hydration.
- Public missing-media requests no longer generate paid images. Background import dispatch requires ownership and an atomic claim.
- News fetching is asynchronous, time bounded, and size bounded.
- Deployment uses a shared host lock, staged configuration, health gates, and rollback that does not rerun old migrations.
- Session reads handle refreshed database timestamps without triggering asynchronous lazy-loading errors.
- Lesson retries preserve valid outline checkpoints and keep enriched material caches out of the strict generation schema.
- Lesson review distinguishes blocking defects from optional advisories while retaining correctness, arithmetic, complete-exercise, and realistic-workload gates.
- Final lesson duration uses independently reviewed practice time without padding. Writing instructions require complete exercise inputs and tools the app supports.
- Lesson preparation has a 480-second coroutine deadline that cancels parallel provider calls while retaining saved checkpoints.
- Complete provider JSON accidentally wrapped in an `answer` field is recovered only when it validates against the expected schema. Truncated, ambiguous, and schema-invalid responses remain rejected; content gates still run.
- Review failures record bounded field/type diagnostics without lesson content. Review telemetry evaluates the review contract rather than lesson word count.
- Authentication routes have per-IP request limits, bounded bursts, JSON 429 responses, and a 16 KiB body cap. Preflight requests, onboarding, and streamed responses retain their original behavior.
- Practice generation uses the verified balanced route with a bounded 100-second operation, a 120-second preparation lease, and a 130-second client timeout. Three failed attempts trigger a 30-minute cooldown instead of permanent lockout; timeout classification and expired timestamp loading are corrected.
- Practice preparation allows navigation back to the lesson. Reopening polls without another generation request, and polling stops when the screen closes.
- Today keeps personalized plan actions and the Ideas entry point; the unrelated shuffled quote card is removed.

## Completed validation

- Backend full suite with PostgreSQL integration enabled: 1,676 tests passed in 15.14 seconds (`RUN_POSTGRES_INTEGRATION=1 LLM_PROVIDER=dummy GOOGLE_BOOKS_SECRET_ID=''`).
- Flutter final full suite: 326 tests passed; static analysis is clean. Obsolete Today quote-card tests were replaced with coverage that personalized actions and Ideas navigation remain available.
- Final generation-screen polish: 10 targeted tests passed; static analysis clean.
- iOS simulator builds succeeded.
- Latest verified immutable backend deployment, `cmpys-backend:20260926-140113`, succeeded with API, database, Redis, and worker services ready.
- Nine isolated nginx behavior checks passed, including rate limits, payload limits, trusted client addresses, preflight, and immediate streaming. Production nginx validation, public readiness, and certificate challenge probe passed.
- Production smoke ran over SSH/loopback, with synthetic credentials kept in memory: registration, login, profile, refresh-token separation, readiness, and missing media passed.
- Immediate opening question returned in 0.66 seconds in the deployed smoke test.
- A real saved failed plan recovered in 56.390 seconds, producing 12 weeks, exactly 6 hours per week, and 36 tasks.
- Live lesson retry succeeded in approximately 100 seconds after job creation (97.447 seconds to first lesson readiness after worker start). The unfinished lesson used one 81.03-second writing call and a 5.13-second independent review, both passing quality checks, with no retries. The approved second lesson was reused without another generation call.
- The generated first lesson opened successfully in the iOS reader, with all seven sections available and in-app practice navigation working.
- Live practice generation succeeded in 38.082 seconds, persisted two activities, and cleared its lease. Leaving the preparation screen and reopening resumed the same request without fanout. The actual case and answer controls opened in the simulator. No learner answers were submitted or tasks marked complete.

## Live validation findings

A simulator retry exposed a session-read `MissingGreenlet` error that mocked tests did not cover. The fix and a PostgreSQL regression test are complete and deployed. Live saved-plan recovery has passed.

Lesson generation exposed outline and enriched-cache checkpoint bugs, followed by a review contract that treated minor editorial advice as blocking defects. These fixes are deployed. The next retry saved an approved second lesson but exposed an extra provider JSON wrapper that caused a valid-looking first draft to be discarded and rewritten. The fifth deployment includes the strict envelope recovery and improved review diagnostics above. The exact earlier malformed review response cannot be reconstructed because its body and validation details were not retained.

The first-lesson retry, actual simulator reader, and practice preparation now pass. Practice initially exposed repeated 45-second timeouts on the fast provider route; the balanced route completed in 38.082 seconds. A real PostgreSQL regression also covers cooldown serialization on the third failed attempt. Answer grading remains covered by automated tests; validation did not submit answers or manufacture learner progress in the live account.

## Public release requirements

- HTTPS deployment tooling is prepared and tested, but approval of the certificate provider's legal agreement is pending. HTTPS activation and verification remain required before public release.
- Password-reset email delivery is not configured because an email provider and sender are absent. The app no longer pretends an email was sent; it explicitly marks recovery unavailable. Working email login and registration remain available, but account recovery remains a public-release requirement.

Public production release remains blocked by HTTPS activation and email recovery setup; successful deployment and test results do not remove these requirements.

Test success establishes the exercised contracts, not a guarantee that every application defect has been eliminated. Long lesson generation and provider availability still require operational monitoring.
