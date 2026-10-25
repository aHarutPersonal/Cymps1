# Evidence-based lesson factory

The curriculum factory prepares source-backed learning modules independently of
user-visible lesson requests. It complements the existing bespoke generator; it
does not replace that fallback until catalog coverage and personalization have
been proven in production.

## Artifact boundaries

- A **canonical module version** contains reviewed concepts, mechanisms,
  misconceptions, neutral examples, session scaffolds, assessments, sources,
  and an explicit technique plan. Published versions are immutable.
- A **learner lesson brief** captures demonstrated capability, gaps, prior
  outcomes, the real project, constraints, preferences, weekly capacity, and
  source-backed mentor evidence IDs.
- A **personalized lesson version** is the complete reader artifact. It may
  select and bridge canonical blocks, but its explanation, worked example,
  guided practice, user artifact, and rubric must depend materially on the
  learner brief. Canonical-only content is never reported as ready.

Normal module updates do not move an active plan away from its pinned version.
A critical revoke performed through the atomic curriculum revocation service
prevents further delivery, invalidates active derivatives, and makes the next
lesson open enqueue a replacement. Operators must not bypass that service with
a raw status update. Generation jobs and immutable lesson versions together
retain semantic input/checkpoint hashes, content and source hashes where
applicable, prompt/gate/model provenance, and pinned parent version IDs.

Mission completion is also pinned to the exact detail-generation artifact.
Legacy content whose generation-job key is truly absent uses a legacy `NULL`
identity; every modern item/step completion stores its exact `artifact_job_id`.
Modern markers are canonical lowercase hyphenated UUIDs and must reference a
retained detail job for the same item and owner; the job's queue status is not
reader authority. Partial/generating artifacts count only explicit substantive
`ready_step_ids`, keep the full step denominator, and cannot reach 100%.
When replacement B begins publishing, B starts with fresh progress and A's
rows remain audit history rather than completing B. The detailed API returns
the artifact token and modern clients echo it on completion mutations.

## Background state machine

`curriculum_control` leases eligible database jobs and publishes bounded work
to the dedicated `curriculum` queue. The processing stages are:

1. grounded source manifest;
2. evidence-rated learning-technique plan;
3. curriculum outline and session contract;
4. complete module draft;
5. independent factual, pedagogical, originality, and structure reviews;
6. up to two targeted repairs;
7. atomic publication of an append-only version.

External pages, search results, model output, and stored excerpts are untrusted
reference data. A writer receives only a sanitized source manifest with stable
source IDs; it never treats source text as instructions. Direct URLs, rights
status, access checks, content hashes, and claim/source bindings are persisted.
The live research path stores provider-grounded support spans from the search
response, not verbatim excerpts fetched from each primary page. Those spans are
independently checked for claim entailment, while all external material remains
`citation_only`; paid or copyrighted material is linked and synthesized rather
than copied.

Jobs are idempotent by semantic input hash, use database leases and
checkpoints, and use bounded retries for transient or insufficient-evidence
failures. Every expired lease consumes an attempt and missing per-job budget
ceilings fail closed. Classification,
deduplication, and routing use the fast tier. Long writing uses the balanced
tier, while a quality model is reserved for independent review or a failed
deterministic gate. Daily admission uses the exact stage reserves of all
running leases. Each durable job also persists a conservative stage reserve
before every paid stage attempt, including retries that later fail or crash, and
reconciles it with job-tagged telemetry without double counting. This is a
conservative soft guard around paid provider calls, not a transactional
guarantee that an in-flight call cannot finish above its estimate; subsequent
stages stop or defer when the guard is exhausted.

## User-time path

Comparison output is converted into structured skill gaps. Catalog matching
first applies hard compatibility checks for skill, outcome, level,
prerequisites, locale, artifact, and time. Semantic similarity may retrieve
candidates but cannot approve one. Only exact or strong compatible matches are
composed; weak matches and composition failures continue through the existing
personalized bespoke generator.

Personal composition must materially bind the learner's gap, project and
constraints. If verified mentor evidence is relevant to that skill, at least
one selected session must use and cite it; when no relevant evidence exists,
the system does not invent or force a mentor reference.

The scheduler packs sequential 40–60 minute sessions into the user's exact
weekly capacity. A multi-session module can continue across weeks, but a
completed session is never repeated. Several sessions can share one weekly
focus when capacity allows. Durable spaced follow-up delivery is a separate
capability: with its flag disabled, a module that requires it cannot publish.

## Rollout controls

- `CURRICULUM_ENABLED` admits autonomous catalog work.
- `CURRICULUM_MAX_RUNNING_JOBS=2` caps curriculum and mentor-evidence leases.
- `CURRICULUM_JOB_BUDGET_USD=0.60` independently caps one durable job. Two
  repair attempts are a ceiling rather than a spending guarantee: the budget
  can stop a later repair. With the default conservative reserves, a complete
  initial pass plus two repairs would reserve `$0.635`, so that worst case is
  intentionally rejected by the default cap.
- `CURRICULUM_DURABLE_SPACING_SCHEDULER_ENABLED=false` blocks modules that
  require spaced follow-ups until durable delivery exists.
- `LESSON_CATALOG_FIRST_ENABLED` enables runtime matching and composition.
- `CURRICULUM_ENABLED` and `LESSON_CATALOG_FIRST_ENABLED` both default to false
  until the pilot taxonomy is seeded and shadow evaluation passes.

The pilot should cover 15–25 high-demand skills in one or two domains. Scale
only after at least 90% of first lessons are ready before open, ready-reader p95
is below two seconds, every mentor claim has an evidence ID, fallback stays at
or below 10%, and blinded factual/helpfulness/personalization evaluation is no
worse than the bespoke baseline. For factual or financial material, keep
unsupervised publication disabled until either source-page/URL-context
verification or a human source audit confirms that provider-grounded synthesis
faithfully represents the cited pages.
