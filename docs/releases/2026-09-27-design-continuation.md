# CMPYS design continuation — September 27, 2026

## Reference and scope

Read the saved September 26 design audit and its September 27 setup notes before continuing. The current Flutter application remains authoritative. This pass preserves the existing paper/ink/green palette, typography, card and pill shapes, icon family, and reader/listening behavior.

OpenDesign Cloud brief confirmed by the user: **Mobile app → Connected flows → Polished product UI**. A dedicated CMPYS refinement project uses current plan-waiting and Ideas screenshots as references. Generation succeeded, and the completed interactive prototype covers Ideas → saved ideas and Ideas → comments, plus waiting/feedback states, while preserving the existing design system.

[Open the completed prototype](http://127.0.0.1:63257/projects/cmpys-existing-design-refinements-698b/conversations/0b3526f0-c629-44aa-b11b-a62795de58bb/files/cmpys-mobile-prototype.html).

## OpenDesign review

Verified the rendered saved-idea journey, like/save state, comment draft restoration, keyboard trapping and Escape/focus restoration, local comment posting, 320px Ideas at 200% text through the reading ending, and Plan retry/pause/ready transitions. Review fixes scope drafts by idea, prevent closing timers from hiding reopened comments, make inactive content inert, retain accessible names on compact navigation, and remove expired toast actions from keyboard interaction. The Plan action now sits after its status card, clear of navigation. Product copy uses original practice notes and keeps implementation details outside the phone. The prototype's REVIEW-NOTES.md records these checks and remaining limits; all refinements are saved in its version history.

## Implemented in the Flutter app

- Reproduced loss of editable child state in both `Entrance` and `FeedbackReveal`: the original editable element was disposed when the reveal completed. Both now keep a stable widget hierarchy and retain draft text and focus through completion and changes to motion preferences. Finished effects remain inert and do not replay on parent rebuilds.
- Shared typing dots, Ideas swipe hints and heart effects, and analysis/blueprint bob effects now respect reduced motion. Waiting indicators stop ticking under reduced motion while status text remains available. Blueprint readiness and Ideas transitions also honor the preference.
- Toasts expose a live-region announcement and fade without translation under reduced motion. Dismissal timers are canceled when the overlay is disposed.
- Ideas like/save controls expose toggle state, all rail actions have explicit labels, and the existing controls support keyboard focus and activation. Decorative double-tap handlers no longer create unlabeled accessibility actions.
- Visual inspection found overlap and truncation that the earlier overflow-only tests did not detect: 200% Ideas text entered the header, and the landscape action rail overlapped refresh. The reading viewport now sits below the measured header and above the action controls. Long text scrolls without ellipsis; large-text and landscape views retain the same controls in a bottom row, with visible scroll affordance and previous/next actions at the end. A single-item feed no longer promises another idea.

## Validation

- **368 Flutter tests passed** across the full suite.
- **Flutter analysis: no issues found.**
- New regression coverage checks editable state/focus retention, stopped reduced-motion tickers, toast announcements and translation, Ideas keyboard/toggle semantics, header/content/action separation, full reading content, and previous/next navigation with and without motion.
- Rendered and inspected Ideas at 320×568, 390×844 with enlarged text, 320×568 at 200% text, and 844×390 landscape. Long-content end states were captured separately to verify access to the author and navigation controls. Visual fixtures use locally cached fonts and synthetic data.
- Existing reader, listening-navigation, app-shell, and responsive tests remain part of the passing full suite. This pass did not change reader or listening code.

Visual evidence: `fe/cmpys/docs/releases/assets/design-continuation-2026-09-27/`.

## Delivery limits

The app changes are local and have not been deployed or installed on a device during this task. Automated semantics checks are not a substitute for a full native VoiceOver review. The Open Design artifact is a separate interactive design prototype, not a backend-connected production application.
