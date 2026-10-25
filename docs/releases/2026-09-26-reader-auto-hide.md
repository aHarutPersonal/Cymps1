# Reader controls and scroll behavior — 2026-09-26

Removed the fixed Contents / Notes / Next toolbar from the book reader. Contents, notes, and saving now live in the header's Book menu. Listening is a header action when no listening session is active. Next chapter / Finish book appears after the chapter text; horizontal chapter swiping remains available.

The reader's content scrolls into the space previously occupied by fixed controls. End padding allows the last action to clear the floating navigation or listening dock. Reader messages also clear the dock instead of covering its controls.

The app's bottom navigation and listening controls hide after deliberate downward scrolling and return on upward scrolling. A small accessible arrow button also restores them by tap or upward swipe. Hiding the player does not stop playback. Programmatic scrolling, including narration tracking, does not hide controls. Accessible navigation keeps controls visible, and transitions between tabs or listening states restore them. Reduced-motion settings are respected.

## Validation

- All 359 Flutter tests passed; static analysis found no issues.
- Gesture tests cover hide/reveal, the recovery handle, continued playback, ignored programmatic scrolling, and accessible navigation.
- Reader tests verify Contents, chapter navigation, Notes, narration recovery, and narrow layouts after relocation of controls.
- Simulator build passed; the reader was visually checked without its old fixed toolbar. Native simulator gesture injection was unavailable; finger gestures were verified through Flutter widget tests.
- Fresh iPhone Release build passed strict code-signature validation.

## Installation

The iPhone became unavailable before installation. The owner chose to install later. The signed update is ready; the existing phone installation is unchanged by this follow-up.
