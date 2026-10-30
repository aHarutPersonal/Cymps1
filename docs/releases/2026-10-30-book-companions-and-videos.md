# Book companions and supporting videos

Status: implemented and verified locally; AWS deployment is pending approval.

Mission references previously waited for completion of the entire tutorial
sequence before resolution. Video selection was also entirely optional in the
outline. A separate, low-priority preparation path now runs when a learner opens
a tutorial or its recommended book, including for existing missions.

## Learner experience

- A tutorial can show one relevant, checked book idea and an explicitly original
  CMPYS connection to the taught skill. The card opens the book companion.
- Book companions contain one to three short, original tutorials on ideas
  supported by available public evidence. Each includes an original example,
  a small application and a scenario self-check with explanatory feedback.
  The displayed time includes reading and two minutes for the exercise.
- Companions state their limited scope and link their sources. Existing full
  guides and available reading editions remain accessible. Insufficient source
  material produces an honest availability message, not invented lessons.
- Video discovery runs even when the outline selected only books. At most one
  relevant video is offered per tutorial, with its creator, reason to watch,
  evidence description and a short application prompt. Known duration is shown;
  unknown duration is not guessed. Playback uses the existing viewer and includes
  a YouTube fallback when embedding fails.
- Supporting material is optional. It does not replace the core tutorial, count
  toward its required time budget, or award mission completion/mastery.

## Publication and execution

Book companions are shared by canonical book identity. The generator receives
actual retrieved source text, never planner-written book summaries. A separate
review checks primary-source identity, every attributed claim, originality,
scope and answer correctness. Exact evidence quotations must belong to the
referenced sources. Long copied passages are rejected. Stored hashes bind the
approved lessons and their reader text to the review; quarantined or modified
companions and their idea cards are hidden on subsequent reads.

Videos require exact YouTube identity and a matching publicly offered embed.
Relevance is independently checked against substantive creator text or the
creator/institution's own lesson linking the same video. Search snippets, titles,
promotional link lists and unrelated material are insufficient. This verifies
documented relevance and public metadata, not that the entire video has been
watched or independently fact-checked. The UI names the evidence used.

The AWS capability check confirmed configured search access and found a
server-side YouTube watch-page sign-in challenge while oEmbed remained available.
The implementation can use a matching public publisher lesson in that case;
age restrictions, unavailable videos and explicit embedding denial still fail
closed. That fallback is covered by fixtures. A follow-up source-transfer probe
was blocked by automatic approval review and was not run.

Owner checks, approved tutorial versions, durable leases, duplicate-task claims,
bounded provider calls, retry cooldowns and stale-result checks protect the
preparation path. At most two support preparations can be active per mission.
The main tutorial and assessment records are not rewritten. No database migration
or new worker configuration is required.

## Validation

- 212 relevant backend tests passed, including source/evidence rejection,
  unavailable/age-restricted videos and the public publisher fallback.
- One rollback-only PostgreSQL integration test passed: shared book reuse,
  deduplicated preparation, owner isolation, stale-job rejection, retained
  metadata and unchanged tutorial/progress.
- 202 relevant Flutter tests passed; analyzer and targeted Ruff checks passed.
- Four native iOS fixture tests passed: book tutorial navigation and self-check,
  read-only preparation polling/disposal, unavailable support, and video
  provenance/application UI. The player was a test stand-in.
- API schema and Celery task registration were checked.
- The normal simulator app was rebuilt, installed and launched after testing.

Validation made no paid generation calls and did not publish synthetic resources,
submit learner answers or toggle learner completion. Live generated content and
actual video playback still need verification after deployment, within the
existing cumulative QA budget. The deployed server has not been changed.
