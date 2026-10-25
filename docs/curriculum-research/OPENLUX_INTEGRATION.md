# OpenLux integration

Implemented locally on 2026-09-09 and deployed to production on 2026-09-10 (local time). Release: `openlux-20260909-200745`. The practice migration was applied, and all nine application services passed the deployment checks.

## Verified account capabilities

The user supplied a credential for `https://api.openlux.ai`. It was stored in macOS Keychain under the application's named service, not in the repository or dotenv files. The account's authenticated `/v1/models` response listed 17 GPT model IDs. A native Gemini request returned HTTP 404 / `model_not_found`; the credential therefore cannot currently replace the native Google Search route.

Successful bounded synthetic checks:

- GPT-5.6 Terra: streaming JSON request, valid output and usage metadata.
- GPT-5.6 Sol: streaming JSON request, valid output.
- Actual application adapter: Pydantic-validated arithmetic result through Terra, 103 total tokens in the final check.
- Actual interview service: a short Russian question streamed through OpenLux.

GPT-5 mini and GPT-5.4 mini returned HTTP 429 during checks. A non-streaming mini request reported upstream saturation. These observations are temporary account/route availability evidence, not model capability or quality benchmarks. No real user profiles or lesson histories were sent in the probes.

## Routing

Local and production backend configuration select `LLM_PROVIDER=openlux` with:

| Operation | Route |
| --- | --- |
| fast and balanced structured generation | OpenLux / `gpt-5.6-terra` |
| quality structured generation | OpenLux / `gpt-5.6-sol` |
| Interview, tutoring chat, blueprint and comparison streaming | OpenLux / configured balanced model |
| Daily insight cards from supplied evidence | OpenLux / configured balanced model |
| Google-grounded source discovery and verification of missing facts | Existing direct Gemini route |
| Numeric and fixed-choice checks | Existing deterministic application logic |

Fast and balanced intentionally share the verified working Terra route while mini routes are unavailable. This is not a claim that Terra is the cheapest option. Old Yunwu configuration remains separate, including narration; changing provider selection does not imply that this GPT-only credential can serve MiniMax or image models.

OpenLux uses streamed Chat Completions with final usage chunks, no SDK retries, a total request deadline and explicit finish validation. Parseable JSON from a truncated or unfinished stream is rejected. Reasoning GPT requests use `max_completion_tokens` and `reasoning_effort`, without legacy sampling parameters. An explicit configurable reasoning reserve prevents a short interview's visible-answer limit from being entirely consumed by hidden reasoning. Ordinary generation does not silently switch providers. The onboarding-only recovery policy added below is the explicit exception.

The model list controls availability, not advertised support across every OpenLux account. Additional model families require checking their wire format, reasoning settings, response shape and actual access before selecting them.

## Credentials and deployment

Local `.env` contains only the service name `OPENLUX_KEYCHAIN_SERVICE=cmpys.openlux`, endpoint and model choices. `Settings` reads the key from Keychain only when OpenLux is selected and no environment credential was injected. The new credential field is excluded from settings dumps and representation. Headless Keychain reads fail clearly instead of prompting indefinitely. Local processes need a restart to load changed settings; a normal host Python process was used to verify loading.

Production uses `OPENLUX_SECRET_ID=cmpys/prod/app` and `OPENLUX_SECRET_REGION=us-east-1`. At startup, the application reads only the `OPENLUX_API_KEY` field from the encrypted AWS Secrets Manager JSON using the existing instance role. The new key is absent from production dotenv files and Docker container environment configuration. Other existing secret fields were preserved. No IAM permissions or instance metadata policies were changed. Do not set the macOS Keychain service in containers. OpenLux environment passthrough covers five environment blocks and, after YAML inheritance, all nine application services.

Existing curriculum enablement and budget controls were preserved. **Correction verified on 2026-09-10:** the factory was already enabled on the curriculum worker/controller and Beat; reading API-container defaults incorrectly suggested it was disabled. The actual worker daily budget was $12, with $0.60 per job and 150 job starts per day. Catalog-first lesson selection was disabled separately and has now been enabled on the API and five applicable workers/controllers after the owner's request. Flutter changes require a separate client build/distribution. The Secrets Manager JSON also has a Terraform-managed seed definition: review secret-version changes before a future Terraform apply, because the existing seed definition does not include the added OpenLux field.

Grounded product paths still require the existing `GEMINI_API_KEY`. Ordinary OpenLux generation is independently configured: missing optional Google credentials no longer makes `llm_configured` false. To move search calls later, first grant this credential the needed native Gemini routes and verify grounding metadata, source citations and streaming, rather than dropping search from the user flow.

Follow-up on 2026-09-10: authenticated discovery still listed 17 GPT models and no Gemini entries. Gemini 3.6 Flash returned HTTP 404 / `model_not_found` through both native and Chat Completions endpoints; Gemini 2.5 Flash returned the same error through the native endpoint. This is an account-route limitation, not proof that OpenLux cannot serve Gemini generally. The user's routing preference is OpenLux first, with direct Gemini restricted to necessary source retrieval/verification. Comparison now uses its already supplied facts without another search, matching the existing prompt. Daily cards likewise interpret supplied evidence through OpenLux, preserve their per-day cache, and do not silently fall back to Gemini on a gateway error. Missing evidence must stay unknown or produce fewer cards.

## Cost accounting

OpenLux events and curriculum provenance carry `provider=openlux`; they are not priced using the old Yunwu recharge/group formula. Until the account tariff is reconciled, budget accounting uses explicit conservative estimates of $10 input / $50 output per million tokens, configurable through `OPENLUX_INPUT_USD_PER_MILLION` and `OPENLUX_OUTPUT_USD_PER_MILLION`. These are safety reserves, not verified OpenLux prices or a prediction of the invoice. They can cause existing background budget gates to stop work earlier. Actual cost optimization remains dependent on the account's route prices and availability of cheaper models.

## Validation

Provider tests cover schema propagation, reasoning parameters, usage-only final chunks, missing credentials, malformed and incomplete JSON, timeout, sanitized errors, streaming routing, provenance, pricing and key exclusion. The regression run includes routing, telemetry, budgets, intake streaming, curriculum logic, catalog personalization and practice.

Final result: 233 tests passed; one database-dependent test was excluded from the successful regression run after separately confirming the environment failure described below. Ruff checks and formatting passed for the new Python files. Consumer cancellation also closes the upstream stream. The final configuration check loaded OpenLux successfully from Keychain, verified all three selected model routes and confirmed that the provided credential was absent from the eight inspected project/configuration files.

Follow-up routing validation: 86 focused tests passed, including comparison routing, daily feed caching, gateway errors without a direct-Gemini fallback, and continued ordinary configuration without Google credentials. Ruff and whitespace checks passed. This verifies the routing change; no new claim about comparative pedagogical quality is made.

The initial local database-dependent pilot seed test could not run because local PostgreSQL was unavailable. Deployment validation subsequently resolved this coverage gap using a separate test database on the production host, without directing tests at production application data: **all 1,457 backend tests passed**. A clean migration to the latest revision also passed in that isolated database.

Post-deployment checks passed through the running API container: OpenLux structured generation with Terra, an actual interview stream, encrypted credential loading, and direct Gemini model access. The public reverse-proxy readiness endpoint confirmed both PostgreSQL and Redis are available. Production Alembic revision is `j1k2l3m4n5o6` (head), and `lesson_practices` exists. The Gemini check verifies model access, not a full grounded-search quality evaluation. All nine application services use the release image and matching OpenLux routes. Database backups, previous configuration and the previous image were retained for recovery.

The ARM64 release image was built on the server and published to the existing private ECR repository under `openlux-20260909-200745`. The registry confirmed manifest digest `sha256:2cac1aab56874e1e615013587dbb8cd3755bdf3aff0c14ea2ff786d767733332`. The deployment pins this tag; the `latest` alias was not changed. Registry publication used a short-lived authorization token passed through memory and an environment-backed credential helper, without writing the token to Docker configuration.

The first deployment attempt restored the previous release after a verifier command incorrectly omitted Docker's required PID column. The verifier was corrected, deployment was rerun, and all nine services passed. This was a deployment-check failure; the candidate services had been running without restarts. The database migration is additive and remained applied during that rollback.

## Live onboarding follow-up, 2026-09-10

Simulator testing found two consecutive first-question failures: the OpenLux Terra interview request timed out at 60 seconds; a synthetic onboarding-shaped Sol request also timed out at 40 seconds. Simpler Terra requests still worked, so the prior smoke test did not establish reliability for full interview prompts.

Release `onboarding-20260910-072859` adds a narrow recovery policy. If direct Gemini is configured, an interview tries OpenLux for up to 20 seconds. Only a temporary transport, timeout, rate-limit, or upstream-server failure before any answer text may recover once through Gemini using the same prompts, without search and with a 35-second SDK timeout. Partial text, invalid output, authentication errors, other operations and missing Gemini credentials do not trigger this recovery. Recovery is logged and successful Gemini usage retains its actual provider identity.

All 1,462 backend tests passed in an isolated database. Nine production services passed deployment checks; the database schema was unchanged. The private registry confirmed release digest `sha256:217111e54987de1f762c5d7f5d1bff1df901f0ca11ccf80dcd9bda3bd98da20d`. After deployment, the same simulator interview resumed successfully; the first two successful turns used OpenLux and took approximately 10–11 seconds. This observed recovery does not by itself prove a live Gemini fallback occurred; fallback behavior is covered by focused tests.

The subsequent `onboarding-focus-20260910-074017` release fixes a separate live failure when a detailed intake goal exceeded the old plan-job `varchar(200)` column. Migration `k2l3m4n5o6p7` widens that field to `text`; all 1,464 tests and nine service checks passed. The full test goal was preserved exactly on retry, and the comparison and blueprint were generated and saved. Current registry digest: `sha256:3fffc7961034115d9da15ff86ab1556d8fbd06479273d61a028c8e85f9666c1d`.

Public reference: [OpenLux API documentation](https://doc.openlux.ai/en/reference/v1). Actual account availability and working requests were verified directly against the user-designated endpoint.
