# CMPYS integrated release validation — 4 October 2026

The final frontend patch was applied to the current backend checkout without conflicts. Its SHA-256 was `45a6597f1f532c3c6ab07dffdced7624ef5c6fd6a0125b1dd91b1e4d09007e47`. All 29 source/evidence files matched the reviewed manifest before and after dependency resolution and the release build. Backend and unrelated files were preserved.

## Published backend

- Backend image: `20261004-143912-reliability`; migration `m4n5o6p7q8r9`.
- Trusted public HTTPS is active, with certificate identity/chain validation and successful renewal dry run. Renewal timer enabled/active.
- The later proxy-only Compose update matches the repository exactly, SHA-256 `56c398c2848a575de0a0e71cc6792e043f8ad965a4513d69afc76fa10f112f62`. App port bound to host loopback; public forwarding metadata is overwritten at nginx. Forged forwarding identity did not become a recovery limiter identity.
- Full backend suite: 1,817 passed. Subsequent focused deployment suite: 17 passed, including the new port/proxy contract. Additional full HTTP-to-PostgreSQL recovery round trip: passed. One existing Google SDK deprecation warning.
- Live registration, login, refresh, profile, comparison, plan, practice and invalid recovery-code checks passed on synthetic accounts.

## Combined client

- `flutter pub get`: succeeded with the checked-in dependency versions.
- `flutter analyze --no-pub`: no issues.
- `flutter test --no-pub`: **407 passed** in the integrated checkout.
- `flutter build ios --release --no-codesign --no-pub`: succeeded; Xcode phase 51.8 seconds, `Runner.app` 26.6 MB.
- The build uses HTTPS by default. It is an unsigned release artifact: signing is still required before device installation or distribution. No physical iPhone was installed or changed.
- Native recovery and live HTTPS audio at 1×/1.5×/2× were tested by the frontend executor on the exact files verified by the manifest. These lengthy native scenarios were not unnecessarily repeated after byte-identical integration. See the [frontend evidence](../../fe/cmpys/docs/releases/2026-10-04-frontend-validation.md).

## Actual generation timing

A new synthetic account, completed intake, new plan and no copied backbone/checkpoint produced a roadmap **89.828 seconds** after starting results generation and its first approved lesson at **157.910 seconds**. Results alone took **26.567 seconds**. These are normal API-flow timings measured inside the server, excluding mobile/WAN/rendering time; not percentiles or an all-users guarantee. Later final-state inspection confirmed **both generated first-week mission jobs completed without errors**. Recovery timing measurements in earlier notes are separate and must not be presented as fresh-user results.

## Remaining release work

Recovery code, one-time tokens, session revocation, client form and controlled SMTP test are complete. Production email is deliberately unavailable because the owner has no mail service connected yet. Read-only SES inspection confirmed the same project AWS account is in sandbox with no verified identities; the [SES connection proposal](2026-10-04-email-connection-proposal.md) describes the sender/domain decision, costs, verification and production-access requirements. No new email service, external mail or domain purchase was authorized or performed.

Legacy HTTP compatibility remains for installed builds and must be retired after client migration. The new build uses HTTPS. Physical-device validation is deferred with installation at the owner's request. Background audio/lock-screen and Android device behavior were not exhaustively verified. The evidence supports the tested MVP flows, not a guarantee of zero bugs or an unrestricted public production launch before these remaining steps.
