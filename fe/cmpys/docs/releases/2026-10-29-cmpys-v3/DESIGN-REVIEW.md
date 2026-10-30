# CMPYS v3 design review — 29 October 2026

Review method: design-taste-frontend, using its app-screen criteria. Reviewed 11 saved iOS captures from the 28 October walkthrough and checked relevant current Flutter source. This is a visual and source review, not a fresh live walkthrough. The screenshots are 1290 × 2796; small-phone, tablet, desktop, keyboard and larger-text behavior were not newly verified.

The skill's browser inspector measures HTML/CSS DOM elements and its source linter excludes Dart. Neither was run or represented as passing for this native Flutter implementation. No application source was changed. No direction was drawn because this is a review of an existing design.

**Assessment:** a recognizable editorial identity, with excessive visual ceremony on screens meant for daily work. Keep the warm paper, serif voice, real mentor portraits and clear evidence distinctions. Make the next learning action lead the composition.

## Round 1

- Seen in one second: large editorial headings and a dark floating navigation bar.
- Idea: learning from a chosen mentor becomes a personal study journal, organized around a current learning plan and evidence at the same age.
- Live thing: choosing a mentor and committing weekly capacity; later learning and practice execution were not exercised in this review.
- Layout words by screen: Today=stacked greeting/tasks; Plan=header/controls/blueprint/tasks; Compare=paired identities/summary/perspective/evidence; You=profile/stat tiles/portrait/library; Intake=conversation/input; Lab=portrait/checklist/footer.
- Provisional subjective scores: design 6.5 · usability 6 · creativity 7 · content 7 → overall 6.5.
- Caps/adjustments: apply app criteria, not the marketing-page requirements for four photographs, motion counts or a live element. Preserve existing brand colors and typography rather than treating a palette preference as an accessibility defect. Scores cover inspected screens, not the unseen reader and practice experience.

## The three highest-value changes

### 1. Put the learning task ahead of the introduction

**Evidence:** `23-today-preparing.png`, `29-plan.png`, `26-compare.png`, `24-mission-failed.png`.

Today uses a 44-point greeting before the task area. Plan uses a 42-point title, metadata chips, a segmented control, a week strip and a large blueprint before the current mission. Compare spends most of its opening view on identities, an availability summary and a perspective card before its dimensions. The mission title wraps to three large lines.

The hierarchy is attractive at first encounter but delays the answer to each screen's daily question:

| Screen | Question to answer first | Suggested change |
| --- | --- | --- |
| Today | What can I do now? | Compact greeting; current tutorial and action first. While preparing, promote the available habit and keep preparation status secondary. |
| Plan | What is this week's work? | Current week and mission first; reduce the blueprint to a summary that expands. |
| Compare | What does the evidence actually support? | Compact identity row; evidence coverage and dimensions before the longer perspective. |
| You | Where are my saved work and settings? | Retain recognizable identity; reduce the three separate zero-stat tiles. |

Reserve the largest serif compositions for discovery and meaningful transitions. Try 28–32-point operational titles while retaining the same typeface and visual character.

### 2. Correct contrast in the actual components

**Evidence:** `17-intake-hours.png`, `30-you.png`; current `design_tokens.dart`, `v3/buttons.dart`, `v3/tab_bar.dart` and `design_usability_test.dart`.

Calculated from the current sRGB tokens using relative luminance:

| Foreground / background | Contrast | Implication |
| --- | --- | --- |
| White / ember `#EC6E38` | 3.06:1 | Actual primary-button pairing misses the skill's 4.5:1 text target. |
| White / ember2 `#C94E0C` | 4.59:1 | Existing darker action tone is a suitable replacement. |
| ink3 `#7E7983` / paper `#F5F2EC` | 3.80:1 | Secondary information using this token is too faint for the skill's text target. |
| ink3 / card `#FFFDF9` | 4.18:1 | Still below 4.5:1. |
| ink2 `#5D5962` / paper | 6.12:1 | Existing stronger text tone provides a usable option. |

These are token calculations, not screenshot-pixel measurements. Opacity and photographic backgrounds require separate checks. The current test checks white against **ember2**, while `V3ButtonKind.primary` uses **ember**. Verify the rendered component pairing when fixing this.

Bottom-navigation labels are explicitly **9.5 points**. Increase them toward 11–12 points and improve inactive-label brightness without relying on the active glow to establish legibility.

### 3. Simplify the persistent bottom navigation

**Evidence:** the four main-tab captures; current `v3/tab_bar.dart`.

The navigation combines a glass gradient, blur, a substantial shadow, a filled active pill, an orange marker, a count badge and a raised mentor portrait. Its dark mass competes with the page's important content on every tab.

Retain the five destinations and mentor identity. Use an opaque dark surface, one clear selected-state treatment, readable labels and a restrained portrait. Remove the glow and redundant selection marks. Make a settled capture after the change to verify the bar remains visually secondary and content can scroll clear of it.

## Additional findings

- **Essential content enters too slowly.** `V3Rise` fades/slides over 650 ms, with Plan's current-week section delayed another 300 ms. Some washed-out regions in the captures are consistent with this entrance behavior; they are not proof that the settled text has that opacity. Show operational content immediately and reserve motion for user feedback, sheets and meaningful transitions.
- **Portrait crops need consistency.** Discovery's purple close-up and You's warm crop show the same mentor differently; the You card cuts the portrait to an extreme face crop. Use a consistent natural or monochrome treatment and a crop that retains the face. Place text on a dependable neutral scrim.
- **Missing evidence is honest but repetitive.** Keeping unknown scores unscored is a strength. Five nearly identical missing-evidence cards, however, make the comparison feel stalled. Summarize shared mentor-data gaps once; distinguish what the learner can supply from evidence the service must obtain. Offer a next step only when it can address the actual gap.
- **The weekly-capacity control is a strong product detail.** The large chosen value, stepper, slider, presets and daily equivalent explain the commitment concretely. The shown 4.5 hours/week is consistent with about 39 minutes/day. Keep this clarity while correcting button contrast.

## Captured defects already addressed in source

The lab-ready capture has footer text overlapping the comparison card and claims the first tutorial is ready before Today shows preparation. Current source has an opaque footer ground, measured bottom spacing and a separate tutorial-readiness check. The comparison detail capture contains `needs_review` and internal-sounding wording; current source has a prose-normalization function for these strings.

These are **fixes found in source**, not newly verified runtime fixes. Do not count the old screenshots as evidence that these exact defects remain. New settled captures are needed to confirm them.

## Remaining verification

After any revision, capture settled states on a narrow phone and with larger text, including keyboard-open intake, loading, missing evidence and errors. Inspect the actual reader and practice flow before rating the complete learning experience. The existing release notes say those flows were not completed in the captured live run.
