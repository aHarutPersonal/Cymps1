# CMPYS Motion Pass — Design

**Date:** 2026-07-04
**Status:** Approved (core-essentials scope)
**Owner decisions:** app-wide pass · calm & premium personality · flutter_animate allowed · motion-kit-first structure · rescoped to core essentials

## Goal

Give CMPYS one coherent, calm, premium motion language across navigation, loading, and content entrances — without slowing down daily use. Build a small reusable kit in `lib/core/ui/motion/` and apply it to the five tabs and all route changes.

## Motion principles

1. **Motion has a job or it doesn't exist** — it shows where something came from, confirms an action, or makes waiting feel shorter. No decoration-only motion.
2. **Fast by default** — navigational/ambient motion at 150–300ms. Nothing a user does twice a day is slowed down.
3. **Ease-out for entrances; spring stays rare** — the nav pill keeps its existing spring (`AppCurves.spring`); no new spring usage in this phase.
4. **Stagger, don't crowd** — list cascades use a 50ms per-item delay, capped at 6 items; later items animate together.
5. **Respect reduced motion** — when `MediaQuery.disableAnimations` is true, all entrances collapse to plain fades and shimmer becomes a static placeholder. Handled centrally in the kit; screens never check it.

## Scope

### In scope (this pass)

**Token addition** ([lib/app/design_tokens.dart](../../../lib/app/design_tokens.dart)):

```dart
// AppDurations
static const Duration stagger = Duration(milliseconds: 50); // per-item cascade delay
```

Existing `fast` (200ms), `normal` (300ms), `pageTransition` (400ms → transitions actually use 300ms via `normal`), `AppCurves.easeOut` cover everything else.

**Dependency:** add `flutter_animate` to pubspec. It is used only *inside* the motion kit; screens consume kit widgets, never flutter_animate directly.

**Motion kit — `lib/core/ui/motion/` (4 components):**

| Component | Behaviour | Notes |
|---|---|---|
| `MotionConfig` | Inherited access to `motionEnabled` (from `MediaQuery.disableAnimations`) | Wraps the app in `app.dart`; every kit widget reads it |
| `EntranceGroup` / `Entrance` | Fade-in + 12px slide-up per child; stagger 50ms by position, cap 6; curve `AppCurves.easeOut`; duration `AppDurations.normal` | Fires **once per screen visit** (guard in state; Riverpod rebuilds must not re-trigger). Reduced motion → fade only |
| `CmpysSkeleton` | Shimmer placeholder blocks using `AppColors.hair` base / `AppColors.paper2` sweep, 1.2s loop, card radius `AppRadii.card` | Composable primitives (line, block, circle) so each screen mirrors its real layout |
| `CmpysPageTransition` | Fade-through: outgoing fades out, incoming fades in + slides up 16px; 300ms, `AppCurves.easeOut` | Exposed both as a go_router `CustomTransitionPage` helper and a `PageRoute` for imperative pushes |

### Application map

**Navigation** ([lib/app/router.dart](../../../lib/app/router.dart) + detail pushes):
- All go_router routes (auth → onboarding → shell) use `CmpysPageTransition`.
- Detail screens currently pushed with `MaterialPageRoute` (pillar detail, plan item reader, idol detail) switch to the `CmpysPageTransition` route. The record screen (a modal entry form) uses a bottom-sheet-style slide-up instead of fade-through.
- Tab switches: the `IndexedStack` swap in [lib/core/ui/app_shell.dart](../../../lib/core/ui/app_shell.dart) gets a 200ms fade-through on branch change. The nav pill's existing spring animation is untouched.

**Entrances** — the five tab screens (`today_screen.dart`, `plan_screen.dart`, `chat_screen.dart`, `compare_screen.dart`, `you_screen.dart`) wrap their top-level card/section lists in `EntranceGroup`. No per-screen custom choreography in this phase.

**Loading** — screen-level centered `CircularProgressIndicator`s on the five tabs are replaced with `CmpysSkeleton` layouts mirroring that screen's real cards. Unchanged: inline button spinners (correct as-is) and SSE conversational waits (`CmpysTypingDots`, `CmpysThinkFeed` already do this job well).

### Out of scope (deferred to a later phase)

- `Celebration` (habit/milestone check-burst) and `CountUp` (animated numbers)
- Compare gauge/radar draw-in choreography and sequenced verdict reveal
- Onboarding cinematics (directional step transitions, mentor-reveal scale-in)
- Reels screen polish, haptics paired with motion

## Error handling / edge cases

- **Rebuild storms:** `Entrance` animates once per screen visit via a state guard; provider-driven rebuilds render children statically thereafter.
- **Reduced motion:** centralized in `MotionConfig`; entrances → fade, shimmer → static, transitions → fade (near-instant).
- **Long lists:** stagger cap of 6 ensures a 30-item list never takes >~600ms to settle.
- **Navigation correctness:** transition swap must not change route behavior (deep links, back-stack, `parentNavigatorKey` for `/ideas`).

## Testing

- `flutter analyze` and existing `flutter test` suite stay green.
- New widget tests: `Entrance` renders its child and completes; `EntranceGroup` respects stagger cap; `CmpysSkeleton` renders without motion when disabled; `CmpysPageTransition` builds a route that completes navigation.
- Manual pass on iOS simulator: tab switching, each tab's first load (skeleton → content), detail pushes, reduced-motion setting.

## Success criteria

- Every route change and tab switch animates with the same fade-through language.
- No screen-level Material spinner remains on the five tabs.
- Each tab's first view cascades in; revisits are instant.
- Reduced-motion users get a fully functional, fade-only experience.
