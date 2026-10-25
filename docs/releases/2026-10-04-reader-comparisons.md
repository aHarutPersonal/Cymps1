# Accessible reader comparisons — 4 October 2026

## Delivered behavior

The saved Investment / Speculative Operation ASCII comparison now renders as two vertically stacked, selectable comparison cards in both reading and listening modes. The existing English wording, numbers, explanatory parentheses and order are preserved. CMPYS typography, green/neutral surfaces and existing Material icons are used; no graphics library or raster text was introduced.

The parser intentionally recognizes only two framed groups of sequential numbered points separated by `vs.`/`versus`, and a small explicit `comparison` fence format for new content. Multiple-column tables, incomplete structures, code fences with programming languages and code-like contents fall back to readable code rendering. This is not arbitrary diagram recognition.

Rendering and narration use one semantic comparison string and character ranges. Decorative borders are removed before speech synthesis, while displayed word highlights slice exactly that semantic string. Selection and note creation remain native text operations. A sentence-highlight guard also prevents the active sentence's offsets from coloring unrelated blocks.

Existing narration checkpoints carry a backward-compatible text version. Legacy positions before, inside and after a recognized comparison are mapped to the corresponding text in the same block; subsequent saves include the new version in local, active-session and server cursors. Books, plans, answers and stored notes are not rewritten or deleted.

The generator now receives instructions against ASCII layout and may produce an explicit two-group comparison fence with short headings and bullets. These instructions are guidance, not a promise that every model output will comply; the client parser still validates the structure and falls back safely.

## Evidence

- Exact saved comparison was read from the existing canonical book; no content migration was performed.
- Full Flutter suite: **417 passed**. Final static analysis: **no issues**.
- Backend narration/source-authorization and lesson-generation checks: **101 passed**. Source membership remains strict; altered claims are rejected.
- Widget tests cover widths 320, 430 and 900, text scale 1×/2×, legacy position migration, content preservation, structured new comparisons, and rejection of programming code/malformed boxes.
- Native iOS simulator integration test uses the production `BookReaderScreen`, the exact saved comparison fixture, an isolated repository and controlled narration callbacks. It passed reading/listening rendering, highlighted-word placement, pause, versioned saved position, actual text selection → Add note → Save note, and 200% text rendering.
- These controlled narration callbacks verify the display/speech coordinate contract; this scenario does not claim an additional live Gemini synthesis or acoustic test.
- Screenshots are unedited captures from the running simulator:
  - `assets/reader-comparison/comparison-reading.png`
  - `assets/reader-comparison/comparison-listening.png`
  - `assets/reader-comparison/comparison-large-text.png`

Reproduce screenshots with `flutter drive --no-pub --driver=test_driver/comparison_driver.dart --target=integration_test/reader_comparison_test.dart -d <simulator-id>` from the Flutter app.

## Release

Server release `20261004-163905-reliability` is healthy. Deployed prompt hashes match the local tested prompts; existing books were retained. No database/schema or provider configuration changes.

The final signed iPhone release is **1.0.0 (2)**, using the existing app identity and signing profile. The incremental build initially retained a stale outer signature after its compiled framework changed; rebuilding with the new build number corrected it. Deep/strict signature verification passed before the final install.

CoreDevice confirmed successful in-place installation of build 2 at approximately 20:45 Asia/Yerevan. No uninstall, data wipe or logout was performed. The compiled App.framework SHA-256 is `369a6f2f455a069d380f378d504c8b830eb87d946033742f6ccd725f09751782`.

The phone disconnected before launch verification completed. The launch request failed with a transport timeout and the subsequent device inventory reported unavailable. Therefore installation is confirmed, but launch and the new reader's appearance/audio on the physical phone are not newly verified. Open CMPYS normally to see the update; the screenshots above are from the simulator.

## Device-side follow-up verification

After the owner reported not seeing the change, the phone's own app inventory was queried again at approximately 20:51. It reported CMPYS **1.0.0 (2)** before reinstallation. A full installed-app inventory contained exactly one app whose name or bundle identifier matched CMPYS; no second CMPYS icon/build was found.

The current signed artifact still matched the release hash above, passed deep/strict verification, used the production `lib/main.dart` entry point, and contained `LearningComparisonView` and its comparison-section identifiers. At the owner's renewed request, it was installed in place again at approximately 20:52.

The next launch attempt reached the device but was explicitly rejected by iOS as **Locked**. A subsequent lock-state read reported `passcodeRequired=true`. This is a different, confirmed blocker from the earlier transport timeout: the device must be unlocked to complete launch verification.

The live saved comparison's SHA-256 (`d966bb261f54663283cabe3196b1b4de1d9c85dd33a28663c7614998e3418152`) exactly matched the regression fixture, including its empty fence language and four recognized borders. The application's library, plan and routed book readers use the updated production reader. These checks exclude a stale build number, duplicate CMPYS identity, wrong build entry point, or changed source format as the currently observed explanation. They do not substitute for seeing the updated reader on the unlocked physical phone.
