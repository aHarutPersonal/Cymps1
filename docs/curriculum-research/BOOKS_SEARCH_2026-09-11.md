# Google Books production integration — 11 September 2026

Books API is enabled in the user's Google Cloud project and the supplied key's existing allowlist now includes Books API. The production application loads `GOOGLE_BOOKS_API_KEY` from the existing encrypted AWS application secret, using the server's existing role. The credential is excluded from settings serialization and representation and sent only in the `X-Goog-Api-Key` header. No key value is in this report, the image, or the new configuration references.

Both background catalog discovery and title/author reference lookup use `app/services/google_books.py`. Responses are cached in Redis for 24 hours. Credential-scoped cooldowns apply across workers: 15 minutes for ordinary HTTP 429, one hour for HTTP 403, and 24 hours for an explicitly daily quota. Retry-After can extend the pause up to 24 hours. Cached results remain available during a cooldown. Discovery retains its curated identity fallback. Uncached upstream errors still return a fallback rather than publishing invented source content; this does not guarantee upstream availability.

Release: `books-search-20260911`, private registry digest `sha256:2c89667e6b3c286bfcca76448a488bafe74df77dee1668b5429ae901a8790d30`.

Validation:

- Full backend suite: 1,522 passed against an isolated migrated PostgreSQL database. After the final Redis cleanup guard, 22 focused search/discovery tests passed again.
- All nine production application services running, seven Celery workers responding, readiness checks passing. Existing application configuration preserved; the non-secret Books secret references persisted for future deployments.
- Real deployed application search returned book data. A repeated identical search made zero network calls. Discovery returned six Google Books candidates. Title/author reference lookup returned a matching book. Verification added zero LLM usage events.
- One initial live lookup had an upstream HTTP error. A follow-up succeeded while the other successful queries were served from cache. This is a verified integration, not a claim that Google never returns errors.
- An initial deployment preflight counted both YAML keys and their interpolation variable names, stopped before changing running services, and was corrected to count actual key lines. The successful deployment preserved the previous Compose file for rollback.

No bulk lesson generation was launched. The previously documented one-module library and held curriculum jobs were outside this configuration change.
