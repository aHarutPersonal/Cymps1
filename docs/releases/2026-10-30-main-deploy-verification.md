# Main merge and deployment verification — 2026-10-30

The tutorial-speed branch tip (`c901d69`) is an ancestor of local `main`.
The merge retained the prompt, intake-evidence, generation-speed and
one-ahead tutorial changes. GitHub `main` still points to `39dde1f`; this was
a manual deployment from local `main`, not a deployment from GitHub `main`.

## Corrections before deployment

The combined regression run found two prompt-contract failures: an offsetting
effects instruction no longer used the wording protected by its regression
check, and the tutorial writer exceeded its existing 5,743-character limit.
Commit `00020c902e7e8538c09c391c50ae2a9ad3af5efb` restores the explicit
per-item/net-effect instruction and compacts the writer without removing its
learning, privacy, arithmetic or native-rendering requirements. Existing
regression expectations were retained.

## AWS release

- Source revision: `00020c902e7e8538c09c391c50ae2a9ad3af5efb`.
- Release tag: `20261030-121117` (ARM64).
- The repository deployment script completed successfully, including its
  migration, API readiness and worker queue-binding checks.
- All nine runtime services use the release image. PostgreSQL and Redis are
  healthy. Public HTTPS readiness reports both dependencies ready.
- Migration head: `p7q8r9s0t1u2`.
- SHA-256 comparison of 254 application, prompt and runtime support files
  found zero differences between the verified source and the running web image.

## Validation

- 1,452 backend regression tests passed, covering changed tests plus intake,
  prompt delivery, deployment, planning, recovery and native-block contracts.
  These ran with a dummy provider and isolated unavailable database/Redis URLs.
- 260 Flutter regression tests passed, including intake controls, one-ahead
  generation, plans, practice, tutorial rendering and completion celebrations.
- Native iOS smoke passed on iPhone 16 Plus / iOS 18.6: continuous reader,
  native comparison, reading/practice timing, contents jump, saved text answer,
  artifact-bound completion and celebration.
- The native smoke was updated from the obsolete paginated-reader assertions.
  Setup preloads public fonts; the test flow disables network access and uses
  fixture repositories and in-memory preferences. It does not complete real
  learner work or make provider calls.
- The normal app was rebuilt and launched against AWS. Its existing signed-in
  session, mentor-lab transition, Today, plan and mission views loaded.

## Remaining live-content limitation

The existing account's first mission has a failed tutorial-generation artifact.
A read-only aggregate check confirmed one matching failed mission, with the
failure predating this deployment and no active replacement generation.
No raw production identifiers, learner text or error messages were exported by
that check. The simulator displays the retry action correctly.

Fresh paid lesson generation was not rerun. Therefore the fixture smoke verifies
native reading/practice behavior, but does not establish that a newly generated
lesson passes the live provider and publication pipeline. The existing failed
artifact remains available for an explicit retry.

Only the integration test and this report changed after the AWS release; neither
changes the deployed runtime.
