# iOS simulator verification — 15 September 2026

Tested the installed CMPYS development app on iPhone 16 Plus / iOS 18.6 against the deployed backend. This was an actual UI walkthrough, not a fresh build or onboarding reset. No learner plan or completed practice answers were replaced.

## Verified

- App launches and restores the saved mentor/account session, including after a full terminate/relaunch.
- Home, Plan, Compare, Chat and Profile tabs open.
- Saved 12-week plan displays 1 of 36 tasks completed; first week remains 1 of 2 required missions complete. Later weeks remain locked.
- Prepared financial-statements lesson opens in the reader; navigation advances from part 1 to part 2 of 22.
- In-app practice opens with all three completed cases, saved numeric answers, written explanations, feedback and transfer-case result intact. Completed fields are appropriately disabled. No new grading request was made in this walkthrough.
- Compare renders evidence by dimension, without the earlier failure banner. Incompatible capital measures and missing discipline evidence have no numeric score.
- One new synthetic accounting question received a complete streamed answer and check question. Production telemetry identifies `guided_learning_stream`, `zai`, `glm-5.3-flash`, success, 3.737 seconds and $0.0003229 estimated token cost. That estimate is not an invoice. The answer was appropriate for the stated credit-sale example, although “cash is $0” would be more precise as “cash received from this transaction is $0.”
- Chat survives tab switching.
- Production readiness check passed for database and Redis.

## Failures and remaining issues

1. **Next project unavailable:** Fictional Shop Revenue & Expense Mapping shows the explicit “This lesson isn’t available yet” state. No content/practice is offered. The saved plan cannot progress through this mission. The app correctly avoids offering a futile retry.
2. **Chat restoration bug:** after terminating/relaunching the app, the new chat exchange is absent from the screen. `chat_screen.dart` initializes an empty in-memory `_msgs` list and does not fetch history in `initState`. This observation does not establish deletion of the server transcript.
3. **Legacy instructions:** home daily practice still asks for paper; the unavailable project still asks for an external spreadsheet and promises 30 transactions without supplying them. Existing reference cards also expose internal labels such as `visual_verbal` and `retrieval_practice`.
4. **Background generation failure:** recent production telemetry contains a failed `curriculum_module_outline` call through GLM-5.3 at about 120 seconds, with unknown billed usage. Other research calls succeeded. This confirms that background lesson preparation cannot be declared reliable from this UI test.
5. The separate semantic-quality issue documented in DEPLOYMENT.md is not resolved by these checks.

## Scope limits

No new onboarding flow, full plan generation, new lesson publication, or new practice attempt was triggered in the saved learner account. Their synthetic backend results remain separate evidence in DEPLOYMENT.md. No fresh iOS build or code fix was performed in this verification turn. The UI was left running for inspection.

**Conclusion:** app startup, existing lesson/practice access, comparison rendering and a new GLM chat reply work. End-to-end progression and chat restoration do not yet pass.
