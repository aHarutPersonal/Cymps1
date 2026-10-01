# Plan generation and waiting-screen follow-up — 26 September 2026

## Waiting screen

- Replaced the dark, dense layout with a paper background, compact mentor header, clear progress message, and restrained green/gold accents.
- Retained the sourced Seneca, Isaac Newton, and Warren Buffett quotations and portraits, with accessible previous/next controls.
- Added distinct running, paused, and ready presentations. Quote rotation respects reduced motion and stops after manual interaction.
- Fixed retry progress retaining a failed attempt's later stage. A retry starts from confirmed saved results and restores later progress from the server.
- Verified all three states on a phone and at 200% text, including scroll access to sources and recovery controls.
- Full Flutter suite: **333 tests passed**. Static analysis: **no issues**. Simulator build, installation, and normal app launch succeeded.

Preview: [Updated waiting screen](../../fe/cmpys/docs/releases/assets/plan-waiting-screen.png).

## Performance investigation

Historical telemetry identified two serial plan-generation calls as the largest remaining wait: the cycle backbone and the first week's expansion. Comparison and blueprint are earlier dependencies; comparison scoring already overlaps later work. Historical durations from different jobs are not an end-to-end benchmark.

Controlled tests used fictional learner data, a 90-second deadline per call, no automatic repair or fallback, and no application-row writes:

| Experiment | Time | Outcome |
| --- | ---: | --- |
| Fresh cycle backbone | 61.3 s | Rejected: a one-off diagnostic was mislabeled as recurring practice, leaving too few mission tasks. |
| Existing full-week response, medium reasoning | 44.3 s | Structural gates passed; manual review found unsupported app workflows. |
| Existing full-week response, low reasoning | 18.3 s | Rejected: changed five daily drills into three longer sessions and described unsupported app workflows. |
| Compact mutable-copy response, medium reasoning | 48.9 s | Structural gates passed, but no latency improvement: approximately 10% slower than the single medium baseline. Not shipped. |

All three week tests used the same synthetic scaffold after explicitly correcting the diagnostic's task type and validating the scaffold. They do not establish successful fresh end-to-end generation. Lower reasoning was not adopted. Compact output saved only about 4% of completion tokens, and was withdrawn rather than adding an unproven generation path.

The small sample does not prove either latency equivalence or a general speedup. Model/provider response time remains the dominant source of waiting. Structural gates cannot establish that every free-text instruction is pedagogically sound or supported by the app; manual content review was part of acceptance.

## Retained backend changes

- The worker publishes roadmap and first-week milestones only after validation, including when resuming saved work. Invalid saved drafts cannot advance the displayed stage.
- The status API shows the actual worker stage instead of simulated progress copy. Removed premature stage commits.
- One ordered achievement query now supplies both the full gap context and the five most recent achievements, eliminating a duplicate read without discarding evidence.
- Generation schema guidance distinguishes one-off diagnostics from daily rhythms and specifies supported app actions, supplied exercise inputs, optional resource access, and consistent recurrence.
- Medium reasoning, existing validation bounds, checkpoint identity, and reuse of valid saved work remain unchanged. Guidance improvements are instructions to the model, not new semantic validation gates.

Full backend suite, including PostgreSQL integration: **1,683 tests passed** in 13.27 seconds. One existing dependency deprecation warning remains. The independent review cleared the retained change; repository whitespace checks passed.

No demonstrated fresh-pipeline latency reduction is claimed. Avoiding duplicate data loading is a small efficiency improvement; clearer schema guidance aims to prevent invalid outputs and retries but its production effect has not yet been measured.

Deployed **`cmpys-backend:20260926-144815`** successfully. API readiness, PostgreSQL, Redis, all configured workers/queue bindings, and the scheduler passed the deployment health checks. A separate readiness request also passed. The updated iOS simulator build is installed and opens normally; the waiting-state previews used offline fixtures and did not create another learner plan.
