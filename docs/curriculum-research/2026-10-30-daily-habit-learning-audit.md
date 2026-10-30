# CMPYS daily habits: learning and implementation audit

## Verdict and scope

One recurring habit can be a sensible way to organize practice. The current
habit implementation is not sufficient to establish effective learning: it
supports attendance, timing and journaling, but the displayed exercise lacks
its promised materials, its schedule contradicts its timer, and its completion
record contains no checked evidence of learning.

This audit combines inspection of the deployed simulator habit, tracing the
local generation/API/UI paths, an offline validator probe and learning-science
research. No production data was changed, no completion was submitted, and no
paid generation was triggered. Research supports design principles; it does not
establish the effectiveness of CMPYS or an optimal number of habit cards.

## Why there is one habit

The backbone prompt explicitly prescribes exactly one recurring task below six
hours per week and permits one or two at six hours or more. At six hours it
requires two mission blocks. Both backbone and expanded-plan validation enforce
these counts. The deterministic fallback also creates one recurring task per
week. None of these rules is an empirically established optimal habit count.

The displayed plan has a six-hour weekly budget, so one habit is permitted.
The Today endpoint returns all habit/practice items covering the current
execution week; the frontend renders the returned list without a one-item cap.
The exact model reason for choosing one rather than two was not investigated.
There is no evidence that the UI is hiding a second current-week habit.

Relevant code:

- `cmpys/prompts/plan_backbone_generate.txt:50`: conditional counts and workload.
- `cmpys/backend/app/services/planning/generator.py`: `validate_plan_contract`,
  `validate_backbone_contract`, and `_generate_deterministic_items`.
- `cmpys/backend/app/api/v1/daily_tasks.py:389`: current execution-week filtering.
- `fe/cmpys/lib/features/cmpys/presentation/plan_screen.dart:710`: all-item rendering.

## Observed exercise and concrete gaps

The visible habit is **Daily statement vocabulary drill**. It asks the learner
to match financial-statement terms to a fictional dataset, check an answer key
and record corrections. That can support an introductory discrimination skill.
It does not by itself demonstrate the ability to analyze an unfamiliar business.

### 1. The promised exercise is not supplied

The instructions refer to a supplied worked example, a mini-dataset and an
answer key. The habit screen contains instructions, a timer, a reflection field,
weekly completion dots and a completion button; it has no supplied exercise or
key in the displayed instructions.

The backend's daily-item response explicitly returns `details=None` and skips
the mission lesson/workbook generation path. This is deliberate lightweight
behavior, but it means prose cannot promise those mission capabilities.

The generation schema already requests actual inputs inside the instructions.
The visible artifact violates that request. Existing checks do not establish
that promised material exists and is reachable. Updating a prompt also does not
rewrite already stored plan content.

### 2. Schedule, timer and daily status disagree

- Instructions: three 20-minute sessions on separate days, implying 60 minutes.
- Visible timer and duration: 15 minutes.
- UI: repeats daily and due today.
- Runtime: `rhythm_cadence(60)` returns four sessions of 15 minutes.
- Today selection uses execution-week membership, not scheduled practice days.

Following the displayed 15-minute routine every day would take 105 minutes per
week, rather than the instructions' 60. The stopping rule also says to stop at
20 minutes or eight matches, whichever is later; that can exceed the allocation.

The root cause is independent sources of truth: the model writes cadence in
prose, runtime derives a different cadence from weekly minutes, and the UI
labels every current-week habit as daily. No single stored schedule binds them.

Relevant code: `capacity.py:167`, `daily_tasks.py:257`, and
`habit_detail_view.dart` (`_minutes`, `_header`, `_timerCard`).

### 3. Completion measures participation only

`daily-toggle` records or removes a date-stamped completion. It does not receive
an answer, calculate accuracy, require correction, or verify time spent. The
reflection is optional. Starting or completing the timer is not required to tap
done. That is valid for self-reported participation, but cannot establish mastery.

Keep participation and mastery distinct in any redesign: a sincere attempt
with errors can count as practice while still creating a learning need.

### 4. Feedback and adaptation are missing from this flow

The habit reflection is stored and displayed; this path does not use it to
grade the answer, identify a misconception or select a later exercise. A generic
journal entry is not automatically a useful self-explanation. The learner needs
the relevant source facts and a trustworthy check to correct an error.

The same instructions return during the active execution week. The daily flow
does not schedule individual concepts from previous weeks according to elapsed
time or demonstrated recall. A repeated card can support learner-managed spaced
practice, but does not guarantee which knowledge is revisited or when.

### 5. Calendar streaks conflict with prescribed rest days

The server streak counts consecutive calendar days with at least one habit
completion. A learner following a three-session weekly plan can therefore break
the streak while complying with the plan. Mission completion can also advance
the execution week without carrying a due review of earlier material into Today.

Use scheduled-session adherence and preserve earlier review obligations across
mission progression. Separately, server-date and device-local-date handling
should be reconciled before adding scheduling; a boundary mismatch is a code
risk, not a live failure observed during this daytime inspection.

### 6. The current quality checks miss these defects

`daily_workload_issues` checks explicit numeric phrases such as "60 minutes per
week". It does not reconcile session-count arithmetic or verify referenced
materials. An offline probe with a one-hour allocation returned no issues for:

- Three 20-minute sessions.
- Three 30-minute sessions, despite totaling 90 minutes.
- Instructions referring to an unspecified supplied example, dataset and key.

Other week checks protect task counts, stored hours, description depth and
instruction length. They do not make these three examples executable or
consistent. The full validation function was not claimed to accept the short
probe texts; the probe specifically isolated the cadence checker.

## What the evidence supports

**Retrieval.** Repeated retrieval improved delayed vocabulary recall in
Karpicke and Roediger's experiment. For a previously taught concept, CMPYS should
invite a first attempt before showing the explanation. A matching task can be
useful early scaffolding, but later checks should require explanation or use
in a new situation. This experiment does not establish that all learning must
be testing. [Original paper](https://learninglab.psych.purdue.edu/downloads/2008/2008_Karpicke_Roediger_Science.pdf).

**Spacing.** Cepeda and colleagues found that effective spacing depended on the
retention interval. A daily app visit is not evidence that a particular concept
was reviewed after a useful delay. Fixed expanding schedules are starting
heuristics, not universal prescriptions. [Original paper](https://doi.org/10.1111/j.1467-9280.2008.02209.x).

**Interleaving.** Brunmair and Richter found substantial differences across
materials. Mix related, already taught distinctions when identifying the right
method is part of the objective; do not randomly mix every topic or assume
word-matching always benefits. [Meta-analysis](https://pubmed.ncbi.nlm.nih.gov/31556629/).

**Feedback.** A 435-study meta-analysis found that feedback effects varied with
the information conveyed. CMPYS should explain the discrepancy and next action,
then allow correction; a completion animation conveys no diagnostic information.
[Meta-analysis](https://www.frontiersin.org/journals/psychology/articles/10.3389/fpsyg.2019.03087/pdf).

**Habit formation.** Lally and colleagues studied repetition of simple behaviors
in stable contexts. Automaticity developed at different rates, and one missed
opportunity did not materially disrupt formation. Applying this to learning is
a design inference: stabilize the cue for starting practice, while changing
practice content as competence develops. Their study does not determine the
number of learning routines a person should have.
[Original study](https://onlinelibrary.wiley.com/doi/10.1002/ejsp.674).

**Real-world boundaries.** A 2026 meta-analysis of 53 school-classroom studies
supports average benefits from retrieval, distributed and interleaved practice,
with important moderators. These findings support testing the mechanisms in
CMPYS; they do not predict adult app outcomes or validate particular timings.
[Meta-analysis](https://link.springer.com/article/10.1007/s10648-026-10225-5).

## Recommended product design

Keep one visible learning routine as a starting product hypothesis. Within it,
select the actual task appropriate for today. An additional habit is justified
when it addresses a distinct goal or behavior and fits the learner's budget.
Adding more checkboxes is not an outcome measure.

For this one-hour weekly practice allocation, a concrete starting design is
three 20-minute sessions. These timings are a design proposal, not a research
constant. They should share a single authoritative schedule with the timer,
Today cards, weekly budget and adherence indicator.

| Session | Learning demand | Observable evidence |
| --- | --- | --- |
| First | After initial teaching, retrieve a few concepts and classify supplied entries | Answer and short rationale before feedback |
| Later in the week | Retry a prior misconception using a different case | Corrected reasoning, with hint use recorded |
| Final scheduled session | Mix related taught distinctions in an unfamiliar case | A justified decision rather than a memorized label |

Each session can allocate approximately four minutes to recall, ten to a case,
four to feedback/correction and two to an error note. Adjust those allocations
to actual work; stop and save unfinished work at the budget limit rather than
padding or silently extending the session. Once vocabulary is secure, shift the
time toward reasoning and application. Preserve a brief later review beyond the
current week inside subsequent weekly budgets.

Reflection should be specific: what was the mistaken rule, what evidence changes
it, and what will distinguish a similar case next time? Reuse the app's lesson
answer, hint and feedback machinery where appropriate. A habit attempt needs
its own session identity so it cannot overwrite an earlier answer or silently
complete a mission.

## Implementation priorities and acceptance checks

1. **Make existing content honest and executable.** Supply every referenced
   input/check or remove the promise. Unify cadence, duration and stopping rule.
   Validate reference availability and session arithmetic. Existing stored
   habits require explicit migration or regeneration as appropriate.
2. **Provide checked practice.** Render the case, capture the first attempt,
   reveal criteria or feedback after attempting, save a correction and keep
   participation separate from mastery. Keep a manual offline-compatible
   exercise when grading is unavailable; do not invent an assessment.
3. **Schedule by learning evidence.** Persist concept links, attempts, hints,
   actual timestamps, local practice days and due reviews. A scheduled rest day
   must not break adherence. Reviews of earlier skills survive week advancement.
4. **Adapt workload and progression.** Use baseline evidence and later responses,
   not self-confidence alone. Do not repeat mastered matching indefinitely or
   require advanced reasoning before its prerequisites are taught.
5. **Evaluate the result.** Compare versions with equivalent learning content
   and time budgets. Measure delayed recall, success on unfamiliar cases,
   misconception recurrence, hint dependence, adherence and actual workload.
   Suggested evaluation windows such as seven and 21 days are product choices.
   Immediate completion and timer minutes are secondary process measures.

No claim of "enough" should be based on a universal habit count or a streak.
For this implementation, the next useful milestone is one fully executable,
scheduled and checked practice routine, followed by evidence that learners
retain and transfer the taught skill.
