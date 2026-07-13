# Council (Agent-Enhanced) — CMPYS Agentic Background Architecture

**Date:** 2026-07-02
**Providers queried:** codex (GPT), gemini (google)
**Mode:** deep/agent-enhanced, detailed verbosity

## Question

Build an agent-based background system for CMPYS: local agents on a remote server that
(1) discover famous people ("idols") and compile structured info (achievements, careers,
personal info, photos), and (2) generate 15-minute reading materials distilled from real
books, storing both in the DB. At request time: DB-first, Gemini LLM generates on a miss.
Which local agents / architecture improves performance without compromising quality?

Existing stack: Python/FastAPI, Celery+Redis (task_time_limit=600s, low_priority queue),
multi-step LLM ingestion pipeline (services/ingestion), Wikipedia/Wikidata providers,
LLM client with retry+JSON-repair+Pydantic validation, Postgres job models
(IdolImportJob, ItemDetailJob, SuggestJob), comparison + planning services.

---

## 🔳 Codex (GPT) — Agent Analysis

**Quality:** good | **Confidence:** high | **Retried:** no

### Key Recommendations
1. Keep Celery+Redis+Postgres; model "agents" as deterministic bounded pipeline stages
   (discovery → collect → extract → verify/dedup → grade → review → publish), not autonomous
   actors. Avoid CrewAI; LangGraph only inside a Celery task; Temporal only for multi-day
   durable workflows.
2. DB-first at request time but never block on a cold full generation (>3-5s): published hit
   / stale-hit + low-priority refresh / skeleton "generating" state with job_id+ETA+fallback.
   Pre-warm from search logs, misses, trending/popular, editorial seeds on a P0-P3 tier.
3. Sources are truth, LLMs are transforms: canonical identity resolution (wikidata_id) before
   write, claim-level evidence + citations + source-reliability tiers, separate grader model,
   auto-publish only above thresholds (quality>=0.85, coverage>=0.8, no legal flags) else human review.
4. Copyright as a rights problem first: classify every book; only full-text-ingest PD/licensed/
   user-owned; ban long quotes + chapter-substitute summaries for unlicensed copyrighted books;
   generate original study guides/commentary only; originality/substitution grader; audit logs; counsel.
5. Idempotency + cost control: deterministic job keys + Postgres partial unique index + advisory
   locks; resumable stage tasks with upsert-on-publish; Redis token buckets; hard budgets; model
   routing; content_version/prompt_version/source_fingerprint/expires_at for freshness.

### Unique Perspective
Resists framework hype; keeps existing Celery substrate and reframes agents as deterministic
auditable stages with a clean Celery vs LangGraph-in-Celery vs Temporal decision boundary.
Unusually concrete on legal: cites U.S. Copyright Office four fair-use factors + Circular 33
idea/expression distinction, translated into a rights-classification pipeline.

### Blind Spots
Assumes a human-review queue + multi-grader eval harness can be built/staffed without sizing
that labor cost or reviewer throughput at long-tail scale. Omits vector-store/embedding specifics,
Gemini concurrency limits for skeleton-on-miss under load, observability/alerting. Legal guidance
is U.S.-centric and explicitly not counsel.

### Full Response
See rendered chat output (full response reproduced there under the Codex <details> block):
Celery-as-substrate recommendation; concrete pipeline diagrams for idols and reading materials;
new tables (agent_runs, content_artifacts, source_documents, evidence_claims, review_items,
generation_costs, canonical_entities); read-through cache pseudocode; claim-level evidence schema;
copyright rights-classification + fair-use citations (copyright.gov/fair-use, Circular 33);
freshness policies; cost budgets + model routing; deterministic job keys + Postgres partial unique
index + enqueue_once advisory lock; Redis token buckets; trade-offs for Celery/LangGraph/Temporal/CrewAI.

---

## 🟦 Gemini (google) — FAILED

Excluded from synthesis. Every attempt returned a hard billing/dunning denial:
`Lightning dunning decision is deny for project: projects/658940560350`. Not transient — a
minimal connectivity test failed identically. NOTE: the same Gemini account powers the app's
runtime on-miss generation path, so this is also a production risk (no provider fallback).

---

## Synthesis (single-source; unchallenged)

Only codex returned substance → high-confidence but unvalidated recommendation, not consensus.

**Core:** Don't build autonomous agents; build deterministic auditable pipelines on the existing
Celery/Redis/Postgres substrate. Framework choice is mostly a distraction (LangGraph only inside
Celery when a flow needs inspectable state + HITL; Temporal only for real durable workflows;
CrewAI is wrong for a citation/review-gated ingestion system).

**Two success determinants:** (1) Quality = sources-are-truth + claim-level citations + canonical
ID + grader + review thresholds. (2) Copyright is a product/legal risk — time-compressed
substitutes for copyrighted books are where fair use is weakest; rights-gate the pipeline and get
counsel before monetizing.

**Cache:** DB-first, never block a request on cold generation; return skeleton/"generating" with
fallback; background agents pre-warm by priority tier.

**Uncovered gaps you own:** reviewer throughput/cost sizing; embedding/vector infra for dedup;
Gemini as a single point of failure (proven by the billing outage — add a provider fallback);
non-U.S. jurisdictions + image-license enforcement.

**Next step:** Re-run the council once Gemini billing is fixed (or add a third provider via
--providers) to get a genuine second opinion on the framework decision and copyright posture,
which currently rest on a single source.
