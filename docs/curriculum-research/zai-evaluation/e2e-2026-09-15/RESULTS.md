# Fresh registration-to-lesson audit — 15 September 2026

**Overall result: FAIL.** A new learner can register, finish onboarding and receive a personalized plan, but cannot complete the first learning mission reliably. The delivered first lesson contains incorrect exercise answers, the second lesson failed, and practice failed twice.

The test used a new synthetic account and an isolated iPhone 16 Plus / iOS 18.6 simulator. It used the current installed frontend build against production; no fresh frontend build or production fixes were made in this test. The owner's saved account and completed work were not replaced.

## Results by stage

| Stage | Result | Evidence |
|---|---|---|
| Email registration | Pass with UX issue | Empty input rejected; valid synthetic account created; name requested again during onboarding. |
| Mentora discovery/search | Fail | Buffett search returns no results because search only filters suggestions; Jobs shown as top investing match. Continued with Rockefeller to reach later stages. |
| Intake | Partial | Eight answer categories retained, including four-hour limit, beginner gaps and in-app constraints. Generic work-sample checks remain needs_review; explanatory “none yet” is not normalized as none_yet. |
| Comparison | Fail | Zero discipline score presented as comparable despite explicitly unestablished habits. Capital is correctly withheld on incompatible bases. |
| Plan generation | Partial | One 12-week plan, 24 tasks, four stored hours each week. Required two corrective retries. Cold-start resume kept the same job. |
| Plan substance | Partial | Correctly targets the diagnostic cash-flow mistake. One-hour habit describes 30 minutes and promises an absent reflection form. |
| Lesson availability | Fail | First usable lesson after 505.953 seconds; second lesson timed out after bounded attempts. First survives as partial content. |
| Lesson teaching quality | Fail | Substantial 2,682-word lesson, but independent-case totals and rubric are wrong. |
| Practice preparation | Fail twice | Same practice record, two generation attempts, state failed, no workbook or answer fields. |
| Answers, hints, grading, transfer and completion | Blocked | Cannot reach these stages normally without a prepared workbook. No pass was fabricated or inferred from old tests. |
| Tutor chat | Partial | Corrects the diagnostic mistake and persists both messages on server; transcript disappears from UI after full restart. |
| Account/plan restoration | Pass | Full restart returns to the new account and plan without restarting onboarding. |

## Critical content error

The lesson's Lakeside Coffee Cart case claims cash increases by **$555** and profit is **$610**. Its supplied transactions yield **$290** cash increase and **$570** profit. The profit/cash gap is **$280**, not $55. Its checking rubric gives the equipment adjustment the wrong sign, admits the numbers do not bridge, and directs the learner to recheck their work. Correct learner reasoning could be marked wrong.

The preceding Riverside worked example is correct. This makes the later wrong answer key especially easy for a beginner to trust. Backend telemetry labels the saved lesson `quality_passed`; the current checks therefore do not establish factual or arithmetic quality.

[Original first lesson](first-lesson.md) · [Independent arithmetic calculation](arithmetic-audit.json) · [Detailed observations](OBSERVATIONS.md) · [Synthetic account evidence](account-evidence.json)

## Timing and cost limits

The plan spent 57.561 seconds queued and 219.792 seconds across four sequential model calls, before other processing overhead. The first lesson became ready 505.953 seconds into its separate lesson pipeline. Reuse did not deliver an instant first lesson in this run.

Account-linked plan calls total **$0.0568317** estimated token cost. Known account-linked plan plus detail calls total **$0.1204957**, with two detail timeouts having unknown billed usage. Discovery, interview, comparison, catalog personalization, chat and practice are not all reliably attributable to the account in current telemetry. Consequently this is not the full test cost or a reconciled invoice. A broad usage export was blocked by automatic approval review and not executed; the saved evidence uses only verified synthetic account/job/item IDs.

## Fix priority

1. Validate every generated numeric case and answer key independently before publication; validate that instructions match actual workbook fields. Repair this erroneous lesson rather than using its key for grading.
2. Make lesson preparation resumable and fast enough for onboarding, and expose real progress without blocking the detail GET or reporting preparation delay as a network failure.
3. Make practice generation observable and reliable; preserve account/item correlation and failure reasons so rejected content can be diagnosed safely.
4. Withhold unsupported comparison scores; separate untested habits from measured performance.
5. Implement actual mentor search and constrain recommendations to relevant teaching goals; prevent prompts from promising unavailable input forms and inflated time estimates.
6. Restore saved server chat history on frontend startup.

This single novice-finance scenario does not establish advanced-learner quality or coverage across every skill. Those need additional profiles after the reproducible blockers above are fixed.
