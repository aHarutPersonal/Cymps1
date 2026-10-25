# Listening navigation — 2026-09-26

The listening controls now replace the bottom navigation during an active listening session, including loading and paused playback. This removes the stacked bars shown in the reported iPhone screenshots and returns the space to page content.

The grid button opens an app menu with Today, Plan, Chat, Compare, and You. Selecting a destination preserves each tab's route, including the current reader, without stopping playback. Closing the menu leaves the current screen unchanged. Stop listening restores the normal bottom navigation. Voice styles remain available under Narration options.

The reader accounts for the bottom safe area once, eliminating the extra empty space above the player. The menu scrolls on small screens and with enlarged text, and has accessible labels and touch targets.

## Validation

- All 357 Flutter tests passed; static analysis reported no issues.
- New navigation tests cover playing, paused and preparing states; menu dismissal; tab switching and reader preservation; voice selection; stop; 320-point screens with 2× text; and keyboard visibility.
- Simulator build and visual verification passed: one listening bar on Today and the reader, app menu navigation, return to the same reader passage, and restoration of normal navigation after stopping.
- No backend changes are needed for this fix.

## iPhone update

The fresh Release package passed strict code-signature validation, was installed in place on the connected iPhone, and launched successfully. Its running process was confirmed after launch. Installation preserved the existing app data.

The initial incremental package contained stale outer signing resources. Rebuilding from fresh iOS output resolved this; the old generated artifacts were preserved in temporary storage. A transient device connection reset resolved on retry.
