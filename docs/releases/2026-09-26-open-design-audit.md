# CMPYS design audit — initial findings

## Scope

The requested target is the current CMPYS application, using Open Design while preserving CMPYS's existing design system. This is an initial audit, not a completed visual review or a claim that every design bug has been found. No application code has changed in this task yet.

## Preserve

- Current cool-paper surfaces, green primary actions, ink text, rounded cards and pill navigation.
- Existing type styles, spacing tokens, icon family, reading surfaces and navigation structure.
- Listening controls that replace navigation during playback, with the existing app-menu access and reader auto-hide behavior.

## Initial findings

1. **Entrance effects can reset child state.** `Entrance` and `FeedbackReveal` replace the animated subtree with the bare child on completion. That changes the element hierarchy and can dispose/recreate a stateful control, losing focus or transient input. Existing tests assert that wrappers disappear; they do not assert preservation of child state. Keep a stable hierarchy and test an interactive child across completion and accessibility-setting changes.
2. **Reduced-motion support is incomplete.** Shared typing dots and the Ideas swipe hint start repeating animation controllers without consulting the existing motion preference. The analysis and blueprint waiting screens also start repeating bob effects. Audit controller lifecycle and all render paths so reduced motion stops decorative looping while keeping useful status feedback visible.
3. **Toast motion ignores reduced motion.** The shared toast always translates on entry and exit. It should follow the app's established reduced-motion behavior. Its notification semantics should also be checked with a screen reader.
4. **Ideas interactions need accessibility review.** The private action control uses a gesture detector and icon/count without an explicit action label or selected-state announcement. Verify like, save and comments with keyboard and screen-reader navigation.

These are source-level findings. The state-reset issue still needs a focused reproduction; visual severity and the final interaction treatment need rendered review.

## Baseline validation

The existing usability, primary-screen responsive, app-shell, and listening-navigation suites passed: **87 tests**. Coverage includes narrow phones, landscape, large text and 200% text sizing, along with generated-content fixtures. Passing these checks does not establish that all screens are visually correct or that motion behaves correctly.

## Open Design boundary

An existing CMPYS project is present in Open Design, containing a historical prototype with 37 modeled screens. Its historical brief is reference material, not an instruction to replace the current application's design.

The installed Open Design version is 0.4.1. The requested plugin workflow requires 0.17.0 or newer, and its MCP connection is not registered in the current Codex setup. The official download page lists 0.24.1. Updating the app and registering the connection is pending the user's configuration approval. No Open Design generation has started, and no execution mode has been switched.

## Next verification

- Complete the approved Open Design connection and continue the attributed workflow.
- Use the current app's screens and design tokens as the reference for refinements.
- Reproduce and fix the confirmed interaction and motion defects while preserving the existing visual system.
- Inspect rendered screens and transient states, then rerun focused regressions and the full Flutter checks.

Source for the current Open Design release: https://open-design.ai/download/

## Setup completed — September 27

- The user approved updating Open Design and connecting it to Codex.
- Installed official Open Design 0.24.1 after verifying its Apple signature, notarization, and matching publisher identity. Kept the previous app and a database backup for recovery.
- The user separately approved turning off anonymous metrics and conversation/tool-content uploads. Both settings are saved as `false`. Automatic diagnostic consent in this release requires both settings to be true.
- Registered the local MCP server using the installed Open Design command-line tool. Codex reports the connection enabled, and a direct protocol check successfully initialized it and listed 22 tools, including `collect_brief`, `confirm_brief`, `get_active_context`, `start_run`, and `get_run`. No design generation was started.
- The current task cannot hot-load the newly registered MCP tools. Continue in one new task as required by the Open Design skill.
- No CMPYS application code was changed during setup. The initial audit and original requirement to preserve its design system remain active.
- The historical CMPYS prototype seen earlier is no longer listed in Open Design. The pre-installation database backup already contains zero project records, and the pre-installation project directory was already empty; this update did not delete those records. The CMPYS Flutter source in the workspace remains the authoritative implementation reference.

## Continuation — September 27

The saved findings were reproduced and addressed in the current Flutter app. Rendered review additionally exposed Ideas header/action overlap and truncated reading content at 200% text; these were corrected while preserving the existing visual system. Full validation passed: **368 Flutter tests**, with **no analysis issues**. See `docs/releases/2026-09-27-design-continuation.md` for changes, evidence, and Open Design delivery status.
