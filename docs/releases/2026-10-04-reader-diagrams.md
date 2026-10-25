# Existing book diagrams — 4 October 2026

## Behavior

The client now renders the existing saved teaching diagrams in *The Intelligent Investor* and *Achievement Deconstruction Canvas*: single framed notes, independent horizontal flows, two-way allocation links, aligned columns, vertical chains and the playbook tree. The previously delivered Investment / Speculative comparison remains supported. This work continues the uncommitted reader changes in the current checkout; no older worktree files were copied over them.

Recognition is intentionally narrow. Programming-language fences, code-like contents, incomplete arrows, dangling connectors and ambiguous connector columns keep the readable code fallback. Independent lines do not acquire arrows merely because they share a frame. Vertical connectors retain their source and destination parts; the two playbook branches share Non-Negotiable Principles as their parent. When stacking a flow would make a link ambiguous, a small source caption identifies its actual parent. These captions are not part of narration or text selection.

The parser preserves source wording, numbers and operators. Rendering, selection and narration share the same semantic string and character ranges. Exactly one Markdown code escaping layer is removed for the narration AST; FlutterMarkdown's already-unescaped AST is left untouched. Literal entities in source code stay literal. Local and server narration positions from text versions 1 and 2 map to the same words in version 3; existing books, plans, notes and answers are retained.

## Evidence

- The initial test reproduced failed recognition of the actual Mr. Market block through `BookNarrationDocument.fromMarkdown`, despite direct parsing succeeding.
- Twelve exact minimal diagrams from the saved API responses and the full first chapter are retained as fixtures without account credentials or progress data.
- **427 Flutter unit/widget tests passed.** **Static analysis: no issues.** The suite covers every diagram's labels and explicit link count, vertical source/destination parts, common tree parent, bidirectional links, no invented frame links, v1/v2 positions, code/entity fallback, and 320 px rendering at 100% and 200% text.
- **Three native simulator scenarios passed** in the production `BookReaderScreen`: Mr. Market, the playbook tree, and a v2 server cursor migration. Checks include reading, controlled word highlighting, pause clearing, actual selection → Add note → Save note, reopen/resume at the same word, and large text. The test initially looked for the first-listen button after resume; it was corrected to use the restored player dock. This was a test-harness assumption, not a product failure.
- The native test uses isolated local repositories and controlled narrator callbacks. It verifies the reader's speech/display coordinate contract; it does **not** claim another live synthesis, acoustic alignment measurement, or audible phone test.
- After the tests, the ordinary `main.dart` simulator build reopened the existing saved book at chapter 5, Designing Transferable Operational Playbooks. Its full chapter and both rendered branches were visually inspected in the live app; it was left open on that diagram.
- Backend content authorization already compares normalized source words. Client tests establish the same words and order for all twelve fixtures; no backend change, content regeneration or data migration was needed.

Unedited simulator screenshots:

- `assets/reader-diagrams/mr-market-reading.png`
- `assets/reader-diagrams/mr-market-listening.png`
- `assets/reader-diagrams/mr-market-large-text.png`
- `assets/reader-diagrams/playbook-tree-reading.png`
- `assets/reader-diagrams/playbook-tree-listening.png`
- `assets/reader-diagrams/playbook-tree-large-text.png`

Reproduce from the Flutter client:

```sh
flutter test --no-pub
flutter analyze --no-pub
LANG=en_US.UTF-8 LC_ALL=en_US.UTF-8 flutter drive --no-pub --driver=test_driver/diagram_driver.dart --target=integration_test/reader_diagram_test.dart -d <simulator-id> --dart-define=ENABLE_LOGGING=false
```

## Release status

Signed release **1.0.0 (3)** built successfully with the existing app identity and signing profile. `codesign --verify --deep --strict --verbose=2` passed for the complete application. App.framework SHA-256: `4c928565f5c525b6ed08b86b25d6e0e2e71e1a4712fd690c3701804c77d4f3ee`.

CoreDevice confirmed successful in-place installation on the paired iPhone 16 Pro. A subsequent device-side app query reports **Cmpys 1.0.0, Bundle Version 3**. No uninstall, data wipe or logout was performed.

The ordinary launch request was rejected by iOS with **Locked**; the lock-state read also reported `passcodeRequired=true`. The signed build and installation are verified; launch and the updated diagrams on the physical display are not. The owner subsequently stated that the phone is not connected and requested completion without waiting. Device inventory reports `transportType: localNetwork`, protocol TCP, and a now-disconnected tunnel, consistent with wireless reachability without a cable. No further device action is pending in this run. The screenshots above are from the simulator. No audible-phone test is claimed.

The signed artifact is retained separately from Flutter's transient output at `build/releases/cmpys-reader-1.0.0-3.app.zip` relative to the repository root. It contains the signed `Runner.app`; the ZIP integrity and its compiled framework hash were verified. The ordinary simulator app was rebuilt and installed after the integration tests, replacing the test entry point.

Final scope clarification from the owner: verification is limited to the simulator for now. Do not install or launch on the physical iPhone in continuation of this run. The historical installation above occurred before that clarification; no physical-device smoke check is required for completion of this reader task.

Automatic approval review rejected a proposed force-relaunch because terminating an existing app could lose unsaved state. The actual verification used the safer ordinary launch without termination; no additional authorization for forced closure is needed to continue after unlocking.
