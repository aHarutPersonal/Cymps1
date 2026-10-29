# CMPYS v3: release notes

Release: the CMPYS v3 design (app and backend), the final-review fix wave and the live-run fixes.
Status: verified locally. Not committed yet.

## What's new for learners
- **New look across the app** from the CMPYS v3 design: Today, Plan, Mentor, Compare, You, onboarding, the mentor lab, reading and practice.
- **Richer intake (12 questions):** typed answers with starting points, single and multi-select cards, a 1–5 scale, number pickers, and weekly hours from 1 to 15 in half-hour steps.
  - Answering "I don't have one yet" is recorded as missing evidence, not as a weak answer.
- **Compare v3:** five dimensions (knowledge, practice, capital and resources, network, written judgment). Each comes with the learner's evidence, the mentor's record at the same age, and an honest "Evidence missing" when there's nothing comparable. An unscored dimension is never shown as zero.
- **Tutorials:** native visuals (formula, diagram, comparison, worked steps, chart, quick check) plus number and multi-select practice with hints, revision and a result panel.
  - Optional: one illustration per tutorial (see "Illustrations" below).
- **Narration** no longer reads quotation marks or ampersands aloud.
- **The Record follows the account:** on sign-in, wins saved to the account are restored from the server, so they survive a reinstall or a logout and login. Restored and synced wins read "Saved to your record".
- **Local data is kept per account.**
  - An involuntary sign-out (for example an expired session) keeps notes, saved items and wins for that account; signing back in brings them back.
  - A deliberate logout still clears them. Another account on the same device never sees them.
- **Age is locked after intake** ("Your age is set at intake so comparisons stay fair."), so the profile and Compare can't disagree.
- **Settings show only working toggles** (Sound & haptics). Reminders, mentor messages and the weekly digest are hidden until they're built.
- **Mentor lab:** after the plan is built, the lab checks the first mission once, read-only. When Tutorial 1 is already prepared it ticks and shows "Your plan is ready to begin."; otherwise it says "Tutorial 1 is on its way."
- **Compare starting checks:** an open answer that can't be auto-graded reads "Reviewed by your mentor"; a wrong answer reads "Revisit this specific skill".

## Before you deploy (order matters)
1. **Ship the app first, or with the backend.**
   - Old app builds can't show Compare v3 (they show its error state) and can't answer multi-select practice.
   - There is no forced-update gate (owner decision), so users must update from the store.
   - Say so in the store listing and any support messaging.
2. **Stage everything before pushing.**
   - About 50 files under `cmpys/` are new and untracked: modules, migrations, prompts and tests.
   - Run `git status --untracked-files=all cmpys/` and make sure nothing is left behind. A push to `main` deploys the backend automatically.
3. **Database:** one Alembic head, `p7q8r9s0t1u2`. The v3 migrations are additive and reversible; the fix wave added none.
4. **Batch the deploy, then leave generation alone.**
   - This release changes prompts and the lesson preflight code. Any lesson or curriculum generation in flight when the backend deploys loses its private progress and starts again.
   - Deploy once, at a quiet time.
5. **Comparison facts.**
   - Compare needs verified mentor facts, either seeded in the catalog or fetched through Gemini.
   - In the live run the local Gemini key had no credits, so every dimension showed "Evidence missing".
   - Before release, confirm production has catalog facts for the launch mentors, or working Gemini billing.
6. **Illustrations.**
   - `TUTORIAL_ILLUSTRATIONS_ENABLED` is off by default (daily cap: `TUTORIAL_ILLUSTRATION_DAILY_CAP`, default 200).
   - Turning it on only illustrates tutorials published afterwards.
   - Illustrations run on the `low_priority` queue; its worker mounts the media volume.

## App-first window (new app, old backend)
- Field hints and mission "peek" do nothing until the backend is updated.
- The app no longer opens every mission card on an old backend, because opening one could start paid generation. Only the mission to work on is read, so the Plan tab's "This week" summary counts only that mission until the backend updates.
- New completion requests send `?complete=`. Old backends ignore it and toggle as before.

## Cost and safety changes
- **Mentor profile imports:** at most 5 new imports per user per 24 hours. A completed import is reused, and a failed one can be retried.
- **Lesson generation:**
  - A practice activity that shows numbers without declaring them as case data is now caught and corrected at the activity step, not after the whole lesson package.
  - An inconsistent tutorial outline no longer blocks repairs; it's passed to the writer as guidance.
  - When the evidence check fails, the affected activity gets a targeted repair instead of the lesson failing outright.
- **Answer leaks:** practice rubric rows and criteria no longer state the answer before the learner responds.
- **Intake chat:** internal instructions no longer leak into the mentor's message (prompt rewording plus a final scrub).
- **Connection retry:** a provider connection that stalls before any text is retried once. Read timeouts are never retried.

## Live run (2026-10-28)
- **Scope:** a full simulated new user on the iOS simulator against a local backend, using Z.ai, with a cap of $1; $0.73 spent.
- **Screenshots** are in `docs/releases/assets/v3/`.
- **Walked and working:** sign-up → onboarding → discovery → all 12 intake questions (every control kind) → mentor lab → Today → mission → Compare → Plan → You.
- **Not walked live:** the tutorial reader, quick check and practice flow. The first tutorial didn't publish in 7 attempts. Each attempt exposed a different generation-gate failure, and all of them are now fixed with tests.
  - **Re-run the walkthrough after deploy** to confirm a first tutorial publishes and practice works end to end.

## Upgrade notes (local data)
- The app moves its local store to a per-account key on first launch after the update. The data goes to the account that was last signed in on the device, and nothing is lost.
- A new registration on a device never adopts another account's data.
- Wins from older builds that reached the server are matched on restore, so they aren't duplicated. Older device-only wins stay as they are.

## Verification
- Backend: 5265 passed, 7 skipped; one migration head.
- App: `flutter analyze` clean; 1378 tests passed.
- The whole branch was reviewed by three area reviewers; the fix wave had two scoped re-reviews, both approved. The owner-decision changes had their own review (approved), focused on data safety.

## Known issues
- **Password field (simulator only?):** on the iOS simulator, typing into the hidden password field kept only the last character. With the password shown it worked. Verify on a real device.
- **Test isolation (developers):** backend tests write usage rows into the database named in `cmpys/backend/.env`. Earlier runs left tasks in the dev Redis queue. Run tests with `REDIS_URL=redis://localhost:6379/15`, and don't run them while live workers are up.
- **Mission tutorial count:** a 210-minute mission can list about 35 tutorials. This predates v3 and matches the time allocation.
- **Outline wording:** a tutorial outline with an inconsistent description (for example "five sections" naming four) now generates, but that description is still shown as written.
- **Haptics before sign-in:** the splash and sign-in screens use the default (on) even when a user turned haptics off, because the setting belongs to the account and loads after sign-in.
- **Switching accounts on one device:** if account A is signed out involuntarily and account B then signs in, A's data stays on the device. A goes through onboarding again on return, but wins and notes are kept. An account deleted on the server leaves its local data on the device until the app is reinstalled.
