# Direct Z.ai evaluation — 15 September 2026

Both authorized model requests returned HTTP 200 and finish_reason=stop. No Qwen requests, production changes, or private profile transfers were made. Token was supplied to a hidden prompt, used in process memory and not written to evaluation files.

| Model | Total request time | Input tokens | Output tokens, including reasoning | Estimated USD |
|---|---:|---:|---:|---:|
| GLM-5.3 | 42.44 s | 476 | 1736 | 0.0083048 |
| GLM-5.3-Flash | 19.96 s | 476 | 1819 | 0.0009809 |

Total estimated cost: **$0.0092857**, based on returned usage and the published uncached API rates. This is a token estimate, not a reconciled billing statement. The conservative pre-request reserve was $0.04203275, below the $0.10 test cap.

Both outputs passed valid JSON, required field, transaction-ID, practice field and ten numerical answer checks. The balance sheet reconciles: cash $1520 + receivables $100 + inventory $240 = loan $500 + equity $1360.

Read [GLM-5.3 output](glm-5.3.md) and [Flash output](glm-5.3-flash.md). These are original model outputs, not published lessons.

Review found one shared ambiguity: practice 2 starts from the original balances but does not explicitly tell the learner to reset after practice 1. Clarify that these are independent exercises before publication. A 15-minute duration was proposed by both models, not measured with learners.

The initial handwritten cash expectation contained an arithmetic error ($1420). It was corrected to $1520 by summing signed cash flows and checking the balance sheet. Saved model responses were revalidated, with no extra API requests. Both models had returned the correct cash value originally.

This test covers a small synthetic accounting activity only. It does not establish full-length lesson quality, source accuracy, mentor fidelity, app-schema compatibility, concurrency, or response-time reliability. Production model routing remains unchanged.

[Z.ai pricing](https://docs.z.ai/guides/overview/pricing) · [Chat API](https://docs.z.ai/api-reference/llm/chat-completion)
