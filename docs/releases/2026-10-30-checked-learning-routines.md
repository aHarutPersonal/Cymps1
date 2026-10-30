# Checked learning routines — 2026-10-30

This release replaces generated habit checkboxes with scheduled review of real,
previously attempted lesson exercises. One routine can now contain recall,
application, feedback and correction. More habits are not treated as a learning
outcome. This implements the audit's executable-practice milestone; it does not
establish an optimal schedule or prove improved learner outcomes.

## Behavior

- One schedule drives Today, the detail timer and weekly minutes. The default is
  Monday, Wednesday and Friday: a 60-minute allocation becomes three 20-minute
  sessions. Indivisible budgets are split exactly, without rounding overspend.
  Learners can choose days and a starting cue. Changes start the next Monday,
  preserving the current week's allocation and historical practice days.
- Existing generated scripts are replaced in API responses with an executable
  review flow. The original saved prose remains intact. No migration or paid
  regeneration is required to remove promises of nonexistent datasets and keys.
- A review draws only from owned, current, published lesson workbooks that the
  learner actually attempted. It supplies the existing inputs, answer fields,
  feedback and worked solution. Source publication and version checks also run
  when a saved review is reopened. Changed or withdrawn sources fail closed.
- Each date has a separate practice record. Review answers do not overwrite a
  lesson attempt or complete a mission. Unsubmitted drafts can carry into later
  reviews and are marked as resumed rather than fresh independent recall.
- Due selection spans execution weeks, prioritizes earlier errors or hint use,
  and fits cases into the session allocation. A first successful, unassisted
  review extends the interval through conservative 3/7/14/30-day defaults;
  errors or help reset it to one day. Same-day retries cannot inflate spacing.
  Calendar availability still determines when the learner sees a due review.
- Generated routines require at least one checked attempt to log participation.
  A failed latest attempt requires a correction or a specific correction note.
  This is participation evidence, not a claim that every case was mastered.
  Review summaries explicitly describe retention on familiar cases. New
  applications remain part of lesson practice.
- Today excludes unavailable reviews and rest days from its required total.
  It shows actual practice dates and counts rather than inventing consecutive
  calendar activity. Device UTC offset keeps dates consistent for review,
  reflection and completion. Stale reflections cannot silently move to a new day.
- New user-created personal habits retain their own instructions and manual
  participation path. Generated learning routines use checked reviews.
- Planner prompts and deterministic checks reject conflicting cadence totals,
  nonexistent promised materials and instructions to exceed the session cap.

## Validation

- 660 backend regression tests passed; the opt-in database test was skipped in
  that isolated run. Coverage includes scheduling, exact budgets, source
  ownership/version/publication, due selection, draft carry, completion gates,
  local-date handling, prompt contracts and existing plan/lesson behavior.
  After the final prompt clarification, the relevant 145-test subset passed again.
- Three checks passed with the existing local PostgreSQL test database,
  including a complete review attempt/correction/completion flow and existing
  goal staging. Synthetic data was isolated in rollback transactions.
- 167 affected Flutter tests passed. The analyzer reported no issues in the
  changed app files and native integration test.
- The iOS native fixture smoke passed on iPhone 16 Plus / iOS 18.6: open dated
  review, submit a wrong answer, reveal the worked solution, correct the answer,
  finish and log participation. No lesson completion method is available in
  the fixture repository. The flow disables network access after warming fonts.
- Numeric persistence and native checks made no provider calls. Review
  preparation itself is deterministic. Normal text-answer assessment retains
  the existing model-backed checking path and its existing cost controls.

## Boundaries

Reviews become available only after lesson practice has been attempted and is
due. A failed lesson-generation artifact is not repaired by this change. The
release does not generate novel transfer cases, verify physical performance,
measure actual time spent, or replace a delayed-outcome learning study. Timer
caps guide and save work; they do not claim to verify attention or mastery.

Older clients need the updated app to open and submit the new generated review
flow. No database schema change is required.

## AWS deployment and normal app

- Runtime source commit: `c004536977702645fd182cafb6fef4326059b411` on local
  `main`. Release tag: `20261030-160533` (ARM64). This was a manual release
  from the tested checkout, not a claim that GitHub main was updated.
- The repository's rollback-enabled deployment completed successfully. API,
  PostgreSQL, Redis, all workers and beat passed its readiness checks. All nine
  application services were independently confirmed running the release image.
- SHA-256 comparison of 256 application, prompt and runtime support files found
  zero missing files and zero differences between the checkout and running API.
- The normal iOS app was rebuilt, installed and launched against AWS using the
  existing signed-in session. Today and the habit detail both showed
  `Mon, Wed, Fri · 20 min`. Existing logged participation remained intact.
- The live schedule sheet showed Monday/Wednesday/Friday selected and stated
  that changes start next Monday. It was dismissed without changing preferences.
  Live checks did not submit answers, toggle completion or trigger paid content
  generation. The full answer/correction flow was verified by the native fixture
  and rollback-only database test above.

Only this release record changed after the deployed source commit.
