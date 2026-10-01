# Reusable lesson latency pilot

## Verified result of the authorized continuation

**The pilot is blocked by substantive quality findings; zero canonical module versions are published. App latency improvement is not yet demonstrated.**

- Current deployed release: `originality-locality-20260910`; all nine application services healthy. Full backend verification: **1,474 passed**.
- Today's recorded curriculum usage estimate: **$5.741758**. Retained reserves for unresolved provider usage: **$0.976922**. Total committed estimate: **$6.718680**, within the Owner's $10 authorization. These figures are internal accounting estimates, not provider invoices.
- The business-quality revision has verified sources, a technique plan, outline, saved draft and independent structure review. Its own recorded usage estimate is $1.242282. Source research and the final writer output were reused rather than regenerated during rechecks.
- The independent structure review scored **0.50** and rejected three concrete mismatches: three rubric criteria where the technique plan requires five scored dimensions; self-audit where the plan specifies reviewer feedback; and a missing one-sentence-rule task for each business-quality dimension.
- The existing two-repair limit and all attempt/cost history remain intact. The failed pilot stays flagged. Other catalog jobs were not resumed. No unchecked lesson was published.

### Required next implementation

1. Make the technique plan reflect actual in-app capabilities. Bind feedback tasks to an implemented practice/review flow rather than promising an unavailable peer. The writer, practice UI and review engine must share the same exercise inputs and rubric.
2. Carry the planned five scored rubric dimensions into the canonical schema, writer and validator, with deterministic coverage checks. Do the same for mandatory technique steps so omissions are caught before expensive downstream reviews.
3. Design reusable delivery for sequential sessions. The current module's 40–60 minute partitions do not each contain a complete explanation/example/practice/assessment cycle, so the compact route still falls back to full composition. The generic 2,400–2,800-word constraint on every session also conflicts with practice-heavy sequential sessions. Replace it with a validated workload/content contract, preserving canonical blocks and their order.
4. Validate real learning time and task completeness, not just the sum of declared minutes. The final candidate now includes synthetic task data and answer keys, but its duration has not been validated with learners. Publication and end-to-end app testing remain outstanding.

The following sections preserve the detailed audit trail; earlier proposed or pending states are historical.

## Changes

- Source discovery and curation now save separate durable, content-hashed checkpoints before the next paid call. Identity includes the target, research prompts, technique registry and tiers. A changed identity invalidates reuse; corrupt records are rejected. Independent verification still runs. A rejected factual claim invalidates curation, while preserving discovery for a fresh claim set.
- Only the running worker holding a live source-research lease can persist these checkpoints. Saving failure stops the next paid substage. Incomplete OpenLux API streams can use the existing bounded job retry policy.
- Complete published sessions use a compact adaptation response rather than generating the entire lesson again. The server retains the exact teaching blocks, learner instructions, success criteria, artifact and rubric. Rendering preserves block order, including retrieval before explanations and feedback after practice. Five learner-binding dimensions and source/mentor identity checks remain active.
- Incomplete legacy sessions retain full composition. The compact route requests 4,000 output tokens of headroom instead of 12,000; actual token use and latency are not yet measured. Publication and personalized lesson length gates remain active.
- Reuse markers are private server-owned model attributes, not fields accepted from provider JSON. Modified canonical content cannot use the reuse exemption. Composer/gate identity changed to invalidate old personal composition caches.
- No new provider, automatic Gemini curriculum fallback, or Batch API integration was added.

## Validation

- Local targeted regression suite: 123 passed (one database-dependent case omitted locally).
- Full backend suite against a fresh isolated server verification database: 1,468 passed.
- Tests cover recovery after verification failure without repeated discovery/curation; checkpoint corruption and changed targets; stopping after a persistence failure; compact response schema and alias restoration; unchanged teaching prose exactly once in original order; rejecting modified reuse or a forged JSON marker; and legacy incomplete sessions.
- Server read before deployment: zero canonical module versions. Nineteen unused current-recipe jobs remain flagged; only one business-quality pilot is selected for resumption, preserving its $0.60 job budget and three-attempt limit. Daily budget remains $12.

## Deployment and live outcome

Candidate release: `catalog-reuse-20260910`. Image published to the existing private registry after full verification. Deployment completed: all nine application services are healthy and use the new image; model routes and secret references were preserved. The normal controller dispatched exactly one unused business-quality job, preserving its $0.60 job budget and attempt history. The live result is being checked; publication and end-to-end app reuse must not yet be claimed.

Live database verification: the business-quality pilot persisted both discovery and curation checkpoints before independent verification. Catalog-first and factory flags are true in the running curriculum controller; daily budget is still $12.

## Final live result for this run

The independent OpenLux verification timed out without a complete response. The durable ledger estimate reached $0.604844; this is internal estimated accounting under the configured conservative OpenLux rates, not a reconciled provider invoice. The job consumed one of three attempts.

The normal controller then blocked the pilot with `curriculum_job_budget_exhausted` before a further call. Both discovery and curation remain saved. No module was published, so actual catalog-hit app latency is still unverified. Other flagged jobs were not resumed. The daily budget remains $12; its observed estimated committed spend remains below the daily threshold.

Proposed next action, pending Owner approval: raise only this pilot's admission budget from $0.60 to $3, preserve its attempt counter and history, and resume from the saved research. This does not change provider routing, global limits, or publication requirements. A local reviewable operation script is prepared but not executed. No automatic Gemini curriculum fallback is implemented.

## Approved continuation

The Owner approved $3 for this pilot, then authorized today's work up to $10. The $3 pilot budget was applied and its used-attempt count was preserved. A repeat OpenLux verification did not replay discovery or curation; it failed with a complete but unusable response format. The ledger estimate increased only from $0.604844 to $0.605794, confirming that the expensive research substages were reused.

A scoped recovery implementation now supports an explicitly recorded, content-hashed per-job source-verification route through the existing configured Gemini quality model. No global provider change or automatic fallback is made. The recovery route participates in the stage input hash; usage records identify the actual provider and the original failed route. Acceptance still requires complete output, exact claim/source identity, positive independent verification, confidence threshold and deterministic support overlap. Recovery has a bounded deadline, disables schema repair, and reserves at least $0.50 before the call through the normal budget gate.

The full backend regression suite for this follow-up release passed: 1,469 tests on an isolated database. Candidate release: `verification-recovery-20260910`. The narrow operation checks that today's committed curriculum estimate plus the pilot's entire remaining budget stays below $10 before it can dispatch. Global daily configuration remains unchanged; only this pilot is enabled. Recovery deployment and live outcome are being checked.

## Corrected source revision

The direct Gemini recovery returned, but the combined source-acceptance gate rejected `claim_cycle_normalization`. The stored exception did not separate model rejection, confidence and lexical overlap; the preceding deterministic scan found a minimum full-source overlap of approximately 0.3478 against a 0.35 gate. This is a publication-gate failure, not conclusive evidence of a false factual assertion or a model-quality ranking. The original job remains failed with all three attempts retained.

Research curation now receives bounded diagnostic feedback after a source-verification rejection. Discovery stays cached; rejected candidate claims are kept for diagnostics and the unverified curation is regenerated. An expanded regression test verifies this recovery flow. Release `research-feedback-20260910` passed all 1,469 backend tests and was deployed with all nine services healthy.

An audited revision job (`3a701110-2cf0-4238-b7a7-b3ae8c7ceafb`) was created for the business-quality module. It references the original failed job, reuses only its research and explicit verification-route checkpoints, and starts its own cost ledger; the original ledger and attempt counters were not reset. Its budget is $4.32, calculated from the remaining $10 authorization after $5.177312 of daily committed estimates and a $0.50 buffer. It does not restart the other catalog jobs. Live generation is being checked.

## Recovery across later stages

The corrected revision passed source verification and persisted both its verified manifest and technique plan. OpenLux subsequently timed out repeatedly at outline generation. The job was held between attempts, preserving its two used outline attempts, rather than paying for another identical request during deployment.

Release `stage-recovery-20260910` adds a task-local provider recovery context for later generation/review stages. Recovery accepts only the configured native Gemini quality model, requires a complete response, records actual provider usage, and keeps all existing target, source, structural and pedagogical gates. A context variable is reset on exit, so unrelated jobs retain OpenLux. Source checkpoint identity is unchanged when no generic recovery route is present. Explicit routes participate in their own stage hashes. The worker also supports an opt-in policy to record a route after bounded gateway failures; no global policy was enabled.

Validation: 1,470 backend tests passed on the isolated verification database; all nine deployed services are healthy. For this single pilot, the remaining stages were explicitly routed through native Gemini following the repeated cross-stage OpenLux failures. The verified source manifest and technique plan remain reusable. Its $4.32 budget and attempt counters are preserved. At admission, the conservative daily committed estimate was $6.079672; adding the pilot's entire remaining budget remained below the Owner's $10 authorization. These are internal cost estimates, not reconciled invoices. Publication and actual catalog-hit latency are still pending live verification.

## Live quality and accounting findings

The nine-block, 240-minute outline is a sequential module. Its contiguous 40–60 minute sessions do not each contain explanation, worked example, practice and assessment; they therefore do not currently qualify for compact reuse. Publishing this module alone will not prove the requested app latency improvement.

The first draft had approximately 1,200 words of block prose, with multiple 25–35 minute blocks containing only 120–200 words. More seriously, it referred to absent data sheets, ten observations, company profiles and a peer reviewer. It was blocked by deterministic source-overlap checking before later LLM reviews. A first originality repair did not clear the overlap. The final bounded repair is being supplied concrete operator findings requiring complete in-app synthetic datasets, numerical worked solutions, independent transfer tasks, feedback without unavailable peers, justified per-block time allocations, and appropriately qualified financial inferences. No originality threshold was weakened.

The budget gate also retained full admission reserves for complete native Gemini calls after their positive usage had been recorded. The follow-up `usage-settlement-20260910` release settles future native recovery reserves only when the number of complete responses and their total tokens exactly match the ledger delta from before the call. Unknown outcomes and mismatched/missing telemetry keep their reserves. Historical attempt records remain intact. Tests cover accurate settlement, missing-event/token mismatches, idempotence, and preserving unknown failed-call debt. Full backend suite: 1,472 passed.

A narrowly audited operation was prepared to settle exactly three historical native calls: outline, draft and repair. Each has one successful schema-valid Gemini event inside its attempt timestamps and matching positive cost, on a recovery route with schema repair disabled. The redundant reserve is $2.109124. All gateway calls with unknown usage remain reserved. It also preserves the existing two repair attempts and adds the observed quality findings to the final repair input. This operation requires the corrected deployment and is not a reset of usage or attempt history.

The settlement release was deployed successfully; all nine services passed health and configuration verification. The audited historical settlement and final targeted repair were executed. Known recorded curriculum spend was $5.493626; retained unknown-cost reserves were $0.976922; total committed estimate was $6.470548 before the next call. The current job's estimated cost became $1.293236, with $0.994150 in usage events. No global budget was raised, no unknown-cost debt was erased, and the existing repair counter remains two. The normal controller dispatched exactly this one job. Final quality outcome is pending.

## Originality false positive isolated

The final repair was initially flagged with 66.7% and 57.1% reported source overlap. Reproduction on the saved draft found **zero exact seven-token shingle matches** for either source. The reported percentage came from unbounded longest-common-subsequence matching, collecting individual vocabulary words across thousands of words of unrelated prose. It was not evidence of those percentages of copied phrases.

The fix retains whole-draft exact shingle matching and replaces unbounded fuzzy matching with overlapping windows up to three source lengths. Nearby interleaved copying, padded full copies, copied subsections, and source copying distributed across short fields remain covered by passing regression tests. A new regression distinguishes isolated domain vocabulary scattered through a long text from actual copying. On the unchanged real draft, maximum localized overlap is 45.45%, below the unchanged 55% threshold.

Release `originality-locality-20260910` passed all 1,474 backend tests. An audited draft-recheck path validates the saved draft's content hash and reruns deterministic checks plus structure review without another writer call. Other factual, pedagogical and originality reviews remain mandatory. Its marker is consumed after the stage so a later legitimate repair cannot accidentally skip writing. A test proves no generator is called during recheck, structure review still runs, and altered saved content is rejected. Deployment and recheck outcome are pending.

The locality release was deployed; all nine services passed health/configuration checks. The audited hash-bound recheck was dispatched without a writer call, with the existing two-repair counter and $4.32 job budget preserved. Daily committed accounting at recheck admission was $6.664906 ($5.687984 usage estimate plus $0.976922 retained unknown-cost reserve).
