# CMPYS project analysis — 9 September 2026

CMPYS already has a substantial implementation of its mentorship and learning journey. The strongest next step is to validate and complete a narrow end-to-end curriculum pilot, then improve coverage and learning outcomes using measured results. A rewrite is not justified by this inspection.

This assessment uses the current source tree, product documents, recent changes, and focused backend tests. The next feature has not yet been specified in this conversation, so the implementation priorities below are proposals based on the documented product direction. Runtime flags, production data, provider behavior, and deployed performance were not inspected.

## Product understanding

The intended experience is: understand the learner's achievements, current capability, goal, constraints, and weekly capacity; select a relevant mentor; compare supported evidence; identify learnable gaps; create a twelve-week plan; and deliver one sequential focus with substantive lessons and practice. Books, narration, mentor conversation, and saved material support that learning journey.

The valuable outcome is demonstrated improvement in a real skill. The comparison creates motivation, the plan organizes execution, and the lesson must help the learner produce something assessable.

## What exists

| Area | Evidence in the current implementation | Practical implication |
|---|---|---|
| Mobile experience | Flutter, Riverpod, GoRouter; onboarding and Today, Plan, Chat, Compare, You tabs | Extend the existing screens and state flow. |
| Session and learner baseline | FastAPI session state machine; structured interview answer keys for achievements, capability, capacity, outcome, constraints, and habits | Personalization has useful structured inputs already. |
| Comparison | Evidence normalization distinguishes incomparable and insufficient evidence; unsupported dimensions return no numeric score | Preserve this contract while improving diagnosis. |
| Plan execution | Background plan/detail jobs, current-week preparation, future-week expansion, sequential progress, artifact-specific completion | Current-week preparation needs end-to-end verification, rather than a new parallel generation mechanism. |
| Readers | Dedicated lesson and book readers, resource integration, narration and resume state | Deliver new curriculum through the existing detail/reader contract. |
| Curriculum factory | Durable jobs, research, technique planning, outlines, writing, reviews, repairs, immutable publication, budgets and leases | Much of the proposed background teaching system is already implemented. |
| Personal composition | Structured catalog matching, learner briefs, mentor evidence, personalized versions, fallback to bespoke generation | Shared curriculum is an input to a personal lesson; it is not the learner-facing final artifact. |

The main backend integration points are [session handling](/Users/harutantonyan/work/cmpys/backend/app/api/v1/sessions.py), [plan jobs](/Users/harutantonyan/work/cmpys/backend/app/tasks/plans.py), [curriculum jobs](/Users/harutantonyan/work/cmpys/backend/app/tasks/curriculum.py), and [catalog lesson composition](/Users/harutantonyan/work/cmpys/backend/app/services/planning/catalog_lessons.py). The mobile entry points are the [router](/Users/harutantonyan/work/fe/cmpys/lib/app/router.dart) and [current-plan controller](/Users/harutantonyan/work/fe/cmpys/lib/features/plan/state/current_plan_provider.dart).

## Gaps that determine the next work

1. **Implementation is ahead of rollout evidence.** Both curriculum admission and catalog-first delivery default to disabled in source and deployment templates. Existing handoff documentation explicitly records missing live provider/worker validation and shadow evaluation. This does not establish whether an environment has overridden the defaults.

2. **Grounded research is not yet full page-level verification.** The research pipeline checks sources and independently verifies claims against provider-grounded support. It does not retrieve and retain the actual supporting passage from every cited page. Domain classification is useful for screening, but cannot establish that an individual page supports a claim. See [research implementation](/Users/harutantonyan/work/cmpys/backend/app/services/curriculum/research.py).

3. **Coverage is intentionally narrow.** The pilot defines twenty skills across investing and entrepreneurship. The default repository retrieves candidates by structured skill identity. Semantic matching is an extension hook, not an active embedding retrieval pipeline. Expand coverage based on recorded misses before investing in broad semantic retrieval. See [pilot definitions](/Users/harutantonyan/work/cmpys/backend/app/services/curriculum/pilot.py).

4. **A catalog hit still needs personal composition.** An uncached match can require an LLM call. Existing current-week background preparation is therefore essential to the promised fast reader experience. Measure readiness before the learner opens a lesson, including restart, retry, and week-transition cases.

5. **Durable spaced follow-ups are incomplete.** The system deliberately blocks modules requiring durable spacing when delivery is unavailable. Persisted due dates, attempts, responses, and completion would be a meaningful next learning feature once the core pilot works.

6. **Documentation has drifted.** The older roadmap describes minimal intake and outdated model choices; current code includes a richer diagnostic baseline and more provider routes. Some old feature statuses are not reliable guides to the present implementation. Align a short current acceptance specification with the code before choosing the next feature.

7. **Operational visibility needs a product-specific view.** Existing job and usage records can support a curriculum view showing failed stages, repair reasons, published coverage, catalog misses, composition failures, preparation latency, and cost per accepted lesson. Global enablement flags alone do not provide a selective learner pilot.

## Recommended implementation sequence

| Priority | Concrete work | Completion criteria |
|---|---|---|
| 1. Establish the pilot | Select three existing skills and several contrasting learner briefs; define expected evidence, artifacts, capacity, and reader behavior; add a repeatable scenario runner and results report | Each scenario traverses research through publication, personalization, reading, completion, and week advancement; failures have an identifiable stage and cause. |
| 2. Verify source support | Extend source records with retrieved passage, retrieval timestamp, content hash, and explicit claim-to-passage verification; represent inaccessible evidence explicitly | Published factual claims have inspectable support, or the module is withheld for review. |
| 3. Prove preparation | Instrument the existing current-week enqueue/composition path; cover worker interruption, duplicate delivery, catalog miss, and changing learner inputs | Target at least 90% first lessons ready before opening, ready-reader p95 below two seconds, and fallback at or below 10% within the selected pilot. These are existing rollout targets, not measured results. |
| 4. Evaluate teaching quality | Compare catalog-personalized and bespoke lessons without revealing their origin; assess factual correctness, learner fit, actionable practice, and resulting artifacts | The catalog path meets or exceeds the bespoke baseline on the agreed rubric, with cost and latency recorded alongside quality. |
| 5. Connect practice to adaptation | Persist submitted artifacts and rubric results; use them to update demonstrated capabilities and the next lesson brief; then implement durable retrieval follow-ups | A learner's actual performance changes subsequent instruction and follow-ups survive an app or worker restart. |
| 6. Scale deliberately | Add selective rollout controls and a curriculum operations view; expand high-demand skills; add semantic retrieval only when measured misses justify it | Coverage and reliability improve without relaxing prerequisites, evidence, personalization, or workload gates. |

The recommended first deliverable is one inspectable scenario: a learner with a concrete goal and weekly capacity receives a sourced lesson, completes its artifact, and progresses to the next appropriately chosen session. This tests the product's promise across existing components.

## Engineering approach

Keep the current architecture. Several orchestration files now contain thousands of lines, so extract smaller research, matching, composition, publication, and recovery services as those areas change. Keep behavior and tests stable during those extractions rather than combining a broad refactor with pilot work.

There are existing uncommitted changes in curriculum validation, research, budgets, provider routing, prompts, and deployment wiring. This analysis did not modify them. Their behavior should be included in the pilot baseline rather than assuming the last commit represents the full project.

## Verification performed

Two focused backend runs passed: **159 tests total**. They cover curriculum schemas and pipeline contracts, catalog personalization, interview inputs, plan execution, week preparation, and comparison scoring.

One live-database pilot-seeding test was deliberately deselected. No live database migrations, real provider calls, production changes, Flutter tests, or mobile UI runs were performed. These results support the tested contracts; they do not establish deployment readiness or actual teaching quality.

The existing [curriculum design](/Users/harutantonyan/work/cmpys/backend/docs/curriculum_factory.md) and [implementation review handoff](/Users/harutantonyan/work/cmpys/backend/docs/curriculum_factory_change_review.md) provide further background, with historical claims that still need current runtime verification.
