# Audit fixes — 15 September 2026

In progress; not a production acceptance report.

Implemented locally:
- Resolve and checkpoint reference links at outline preparation, including partial lesson jobs.
- Independent generated-lesson review before publication; safely recompute extracted numeric claims, reject unsupported content and return focused feedback to the writer.
- Preserve reviewed reading/practice durations rather than inflating practice to fill a plan allocation.
- Avoid early item-row flush during catalog composition so reader requests are not blocked by that write lock.
- Compact practice workbook generation to guided and transfer activities; correlate usage with item/step, record safe failure category in item metadata.
- Save registration name into user profile.
- Restore saved guided chat messages via an ownership-checked endpoint; manual retry for unfinished last turn.
- Search Wikidata-backed mentor candidates beyond the initial suggestion list; remove uncalibrated percentage-fit labels.
- Treat explicit new/unestablished habits as insufficient evidence; preserve explanatory no-achievement answers.
- Accept an explicit weekly total followed by a weekday schedule.
- Add saved daily reflection text in the app and backend.
- Add honest reference-unavailable/preparing labels.

Outstanding acceptance work:
- Full backend/Flutter suites, deployment, new simulator build.
- Run bounded synthetic lesson generation and practice, check sources, answers, persistence and latency.
- Inspect resulting plan workload/cadence and verify comparison output on the recorded synthetic baseline.
- Preserve the original failed audit evidence. Do not claim preexisting published lessons have been retrospectively reviewed.
