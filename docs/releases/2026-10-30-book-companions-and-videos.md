# Book companions and supporting videos

Status: deployed and verified with a fresh account in the iOS simulator.

AWS release `20261030-185436` is healthy across all nine application services.
All 257 deployed application/prompt file hashes match the approved local source.

The release includes the original feature and live-test corrections through
`9b1c98a`. Real outputs exposed an oEmbed call mismatch, weak book discovery,
missing self-check fields, evidence typography/quotation issues and overlong
idea-card connections. The fixes retain strict publication checks, use primary
sources, repair malformed structured output once, and search for the actual
skill being taught. Video playback now has accessible native Play/Pause controls
whose state follows the embedded player's events.

Mission references previously waited for completion of the entire tutorial
sequence before resolution. Video selection was also entirely optional in the
outline. A separate, low-priority preparation path now runs when a learner opens
a tutorial or its recommended book, including for existing missions.

## Learner experience

- A tutorial can show one relevant, checked book idea and an explicitly original
  CMPYS connection to the taught skill. The card opens the book companion.
- Book companions contain one to three short, original tutorials on ideas
  supported by available public evidence. Each includes an original example,
  a small application and a self-check with explanatory feedback.
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
referenced sources after harmless typography/Markdown normalization. Positive
reviews with malformed evidence receive at most one independent repair attempt;
unsupported claims or invalid repaired evidence still prevent publication. Long copied passages are rejected. Stored hashes bind the
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
closed. That fallback is covered by fixtures. After deployment approval, a live
AWS check successfully matched the exact video in Google's public IFrame API
documentation to its public oEmbed metadata and publisher evidence. This was
an availability-path check, not a learner recommendation or content review.

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
- After all live corrections, 147 targeted backend tests and 27 targeted Flutter
  tests passed; targeted Ruff, analyzer and whitespace checks passed.
- Fresh synthetic account registration, onboarding, plan generation, first
  tutorial generation and tutorial self-check feedback passed in the simulator.
- The new account received three five-minute lessons for *They Say / I Say*,
  grounded in a first-person interview with the authors. The companion list,
  source attribution and actual lesson body were checked on the deployed backend.
- The final support preparation published a matching book idea card and a
  verified Scribbr thesis-writing video. Both rendered in the normal app after
  deployment, and the idea card opened the three-lesson companion.
- Actual APU Global and Scribbr video playback passed in the normal iOS build: advancing
  video frames, player-reported playing state and successful native Pause were
  observed. This is separate from the earlier fixture-player tests.
- Automation could not scroll the live companion lesson (`noWindowsAvailable`),
  so its generated self-check was inspected in the API data; interaction and
  feedback remain covered by widget and native fixture tests. The live questions
  were recall questions, although the drafting prompt asks for scenario checks.

The initial local validation made no paid generation calls. Live checks used a
new synthetic account and account-scoped QA processes with the existing shared
ledger. There were 93 additional provider/search requests, costing $1.06771180;
cumulative committed spend is $16.94836285 of the authorized $18 cap, with no
pending reservations. The ledger was retained. Only the synthetic account's
onboarding and support data were changed; no real learner progress was altered.
The normal production-backend simulator build was restored and the new account
was signed in. Both temporary QA containers are stopped, and the temporary SSH
tunnel is closed. The account remains signed in with the tested video paused.
