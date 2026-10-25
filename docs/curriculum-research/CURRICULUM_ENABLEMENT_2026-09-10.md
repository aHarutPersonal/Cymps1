# Production curriculum enablement verification

The owner requested enabling reusable lesson preparation and checking its database results.

## Verified initial state

- The factory was already enabled in the curriculum worker/controller and Beat. API-container defaults were not authoritative for background generation. Earlier statements that the whole factory was disabled were incorrect.
- Actual background configuration: daily budget $12, per-job budget $0.60, daily job-start limit 150. These limits were preserved.
- Catalog-first selection was false on the API and applicable workers.
- The database contained 20 skills, 20 canonical module definitions, 288 generation jobs, and 356 mentor evidence claims, but **zero canonical module versions, personalized lesson versions, and plan lesson assignments**. Definitions and completed mentor-curation jobs are not published lessons.
- Today's recorded curriculum usage was approximately $3.69, entirely mentor claim curation/verification. This is estimated accounting, not a reconciled provider invoice. The effective worker budget was not exceeded.
- A real controller tick reported zero eligible dispatches despite a normal budget. Nineteen current-recipe module jobs were flagged after recipe changes, and the first financial-statements module had failed source research. Other historical module jobs included provider errors and rejected evidence/outline output.

## Applied operations

- Enabled `LESSON_CATALOG_FIRST_ENABLED=true` in production; kept `CURRICULUM_ENABLED=true`.
- Recreated the six services that consume this selection setting, preserving the deployed image and routing. All six were running, the API was healthy, and their injected settings matched. Saved only the previous nonsecret flag values; no new credential files were created.
- Resumed exactly one financial-statement-literacy pilot, preserving its prior failure in an operator-retry checkpoint, its two used attempts, its maximum of three attempts, and its $0.60 job budget. The controller dispatched it through the normal budget, provenance, and quality checks.

## Interpretation

Enabling selection cannot improve cache-hit latency until an eligible module is published. Catalog misses still use the existing bespoke-generation fallback. No generic draft or unverified evidence is being marked as ready to conceal the empty catalog.

## Live pilot result

The pilot **failed** its third source-research attempt. Grounded discovery and structured curation returned successfully, but OpenLux returned an unfinished API error during independent claim verification. No source manifest checkpoint or canonical version was published. The durable job is `FAILED` at `SOURCE_RESEARCH`, with all three attempts consumed and approximately $0.385 recorded across its attempts. The unknown cost of the failed provider response must not be interpreted as zero invoice cost.

The incomplete result was rejected as intended. This verifies failure containment, not lesson quality or successful end-to-end generation. Source discovery currently repeats if a later step within this stage fails, because the completed discovery and curation are not separately checkpointed.

Read-only checks also established that 19 untouched flagged jobs now match the current recipe, pilot definition, and published technique manifest. They were not bulk-restarted while the first pilot was failing.

## Remaining work

- Add a narrowly scoped, bounded recovery for temporary OpenLux failures during curriculum verification, using the already authorized direct Gemini route only when necessary. The existing interview fallback does not cover curriculum verification. Preserve each provider attempt's usage and provenance, recheck budget before recovery, and retain the same source acceptance criteria.
- Preserve completed discovery/curation checkpoints so verification retries do not repeatedly pay for the same research.
- Complete and inspect one published module before restoring the remaining valid flagged jobs. Do not reset attempt counters, erase failed attempts, or mark rejected evidence as verified to manufacture success.
- Verify actual catalog selection and learner-specific composition after a published, compatible module exists. The empty-catalog fallback remains the current behavior.

Configuration enablement is complete. Successful lesson generation and personalization are **not verified**.
