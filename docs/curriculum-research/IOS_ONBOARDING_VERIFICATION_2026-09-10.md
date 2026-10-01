# iOS onboarding verification — 2026-09-10

Tested the current Flutter app in the running iPhone 16 Plus simulator (iOS 18.6), connected to the deployed backend. The user selected John D. Rockefeller with the initial goal “Find direction.” With permission to go through onboarding, a consistent synthetic beginner profile was entered; these answers are saved in that session.

## Observed question flow

| Input | Live verification |
| --- | --- |
| Completed achievements | “None yet” accepted and saved as `achievement_baseline_status=none_yet`. |
| Current capabilities | Captured basic spreadsheet arithmetic, introductory reading, and explicit gaps in financial statements and profit versus cash. |
| Foundation check | Accepted a fictional shop example; saved as `needs_review`, not demonstrated mastery. |
| Application check | “I don’t know yet” accepted and saved as `unknown`, including the iOS smart apostrophe. |
| Weekly capacity | Custom “2 hours per week” rejected without advancing; draft retained. Returning to the picker and submitting eight hours worked. |
| Twelve-week outcome | Captured a detailed report-and-spreadsheet outcome with an unfamiliar-case check and no requirement to buy investments. |
| Constraints and resources | Captured free materials, fictional cases, basic tools, and four two-hour sessions; did not equate money or portfolio ownership with knowledge. |
| Learning habits and support | Captured worked examples, in-app exercises, feedback, correction, transfer cases, and weekly accountability. |

The server recorded all eight required keys, no missing keys, nine assistant turns including the closing turn, and transition to comparison. No private control trailers were displayed. Empty text could not be submitted, and invalid time did not skip the question.

## Failures found and addressed

1. **Initial interview timeout.** Two actual attempts failed at approximately 60 seconds on OpenLux Terra. A separate short Sol onboarding probe also timed out; trivial Terra probes still worked. The deployed `onboarding-20260910-072859` release adds onboarding-only recovery for temporary failures before any answer text, trying OpenLux first and permitting one direct Gemini recovery. Partial responses and permanent failures do not switch providers. All 1,462 backend tests passed. The same simulator session then progressed successfully; the initial successful turns used OpenLux in about 10–11 seconds, so live fallback itself was not proven by those turns.

2. **Detailed goal rejected by plan-job storage.** The interview accepted a multi-sentence outcome, but results generation failed with PostgreSQL `StringDataRightTruncation` because `plan_generation_jobs.focus` was `varchar(200)`. Release `onboarding-focus-20260910-074017` widens it to `text` and aligns the direct plan request's maximum with the interview's 10,000-character limit. All 1,464 backend tests passed, including a PostgreSQL test exercising staging, exact round-trip preservation, and retry reuse. All nine production services passed health checks. Live retry saved the complete 366-character goal exactly and resumed comparison and blueprint generation.

## Generated comparison and blueprint

Both were saved successfully after the fix. The comparison explicitly declined an overall percentage, rank, or tier; treated eight hours as stated capacity rather than proven discipline; and distinguished one work sample needing review from independent mastery. It proposed a first lesson on separating profit, cash, and receivables using a fresh fictional case.

The blueprint preserved the eight-hour commitment, beginner financial-statement gaps, fictional-business report and spreadsheet outcome, no-investment-purchase constraint, and worked-example → practice → correction → fresh-case learning pattern. It sequenced foundational accounting before independent business evaluation. This supports the tested beginner's stated objective; it is not yet a quality evaluation of generated lesson content.

The final release was saved in the project's existing private ECR registry with manifest digest `sha256:3fffc7961034115d9da15ff86ab1556d8fbd06479273d61a028c8e85f9666c1d`. Publication was initially blocked by automatic approval review; read-only AWS checks established authenticated-account ownership and the exact existing deployment destination, after which the same publication was approved.

## Final end-to-end status

**The interview passed after the fixes; the complete onboarding-to-plan flow did not.** The background plan worker tried the OpenLux balanced backbone route for 45 seconds and then its quality recovery route for 90 seconds. Both returned HTTP 200 but failed to finish their streamed output before the deadline. The job was marked failed rather than publishing an incomplete or generic plan. The simulator correctly shows “Your comparison is safe, but the plan could not finish” and a retry action.

The session, all eight answers, comparison, and blueprint remain saved. Live lesson/practice verification could not proceed because a usable plan was not produced. The onboarding-only Gemini recovery policy does not apply to plan generation. A separate, bounded recovery policy for validated plan artifacts is the next reliability change to evaluate; increasing timeouts alone does not establish quality or predictable latency.

## Remaining quality findings

- Diagnostic selection uses the initial goal. “Find direction” selected generic work-sample checks even after the capability answer clarified business evaluation. This correctly leaves knowledge uncertain, but provides weaker placement evidence than a relevant profit/cash case. Use clarified learning intent to select the diagnostic domain, while keeping each case version stable across retries.
- Some prompts produce long, multi-part questions, especially achievements, capability and learning support. They cover useful information but impose unnecessary reading and answer-planning effort. Shorter wording with optional prompts for missing evidence would be easier for a beginner.
- This is one beginner-path test. It does not establish advanced-investor placement accuracy, all mentor fidelity, or the pedagogical quality of a full course.

Before this walkthrough, the same client passed all 240 Flutter tests and `flutter analyze` reported no issues.
