# CMPYS Motion Pass Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** One coherent calm-and-premium motion language across CMPYS: fade-through page transitions, tab-switch fades, staggered content entrances, and shimmer skeleton loaders — built as a 4-piece reusable kit in `lib/core/ui/motion/`.

**Architecture:** A small motion kit (MotionConfig, Entrance/EntranceGroup, CmpysSkeleton, CmpysPageTransition + routes) built on `flutter_animate`, consumed by the router, the app shell, and the five tab screens. flutter_animate never appears outside the kit. Spec: `docs/superpowers/specs/2026-07-04-motion-pass-design.md`.

**Tech Stack:** Flutter (SDK ^3.10.4), flutter_animate ^4.5.0, go_router, flutter_test.

## Global Constraints

- `flutter_animate` may only be imported inside `lib/core/ui/motion/` — screens consume kit widgets.
- All durations/curves come from `AppDurations` / `AppCurves` in `lib/app/design_tokens.dart` where a token exists (page transitions = `AppDurations.normal` 300ms, tab fade = `AppDurations.fast` 200ms, stagger = new `AppDurations.stagger` 50ms, entrance curve = `AppCurves.easeOut`).
- Reduced motion (`MediaQuery.disableAnimationsOf(context)` true) must collapse entrances to fade-only, render skeletons static, and drop transition slides — handled inside kit widgets only; screens never check it.
- Stagger cap: items at index ≥ 6 share the index-6 delay.
- Do NOT touch: nav pill spring animation in `_NavChip` (app_shell.dart), inline button spinners (`cmpys_button.dart`), `CmpysTypingDots`/`CmpysThinkFeed` SSE waits, onboarding screens, reels_screen.
- Every task ends with `flutter analyze` clean and `flutter test` green, then a commit.
- Commits end with: `Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>`

## File Structure

```
lib/core/ui/motion/
  motion_config.dart      # reduced-motion switch (static, reads MediaQuery)
  entrance.dart           # Entrance + EntranceGroup (fade + 12px slide-up, staggered)
  skeleton.dart           # CmpysSkeleton.block/.line/.circle shimmer primitives
  page_transition.dart    # CmpysPageTransition.page (go_router) + CmpysPageRoute + CmpysSheetRoute
test/
  motion_entrance_test.dart
  motion_skeleton_test.dart
  motion_page_transition_test.dart
  motion_no_material_page_route_test.dart
```

---

### Task 1: Foundation — flutter_animate dep, stagger token, MotionConfig

**Files:**
- Modify: `pubspec.yaml` (dependencies block, after `flutter_staggered_grid_view`)
- Modify: `lib/app/design_tokens.dart:441-446` (AppDurations)
- Create: `lib/core/ui/motion/motion_config.dart`

**Interfaces:**
- Produces: `AppDurations.stagger` (Duration, 50ms); `MotionConfig.enabled(BuildContext) → bool` used by every later kit widget.

- [ ] **Step 1: Add the dependency**

In `pubspec.yaml`, add under `dependencies:` (next to `flutter_staggered_grid_view: ^0.7.0`):

```yaml
  flutter_animate: ^4.5.0
```

Run: `flutter pub get`
Expected: resolves without downgrades.

- [ ] **Step 2: Add the stagger token**

In `lib/app/design_tokens.dart`, inside `AppDurations` (after `pageTransition`):

```dart
  /// Per-item delay for staggered list entrances (motion kit).
  static const Duration stagger = Duration(milliseconds: 50);
```

- [ ] **Step 3: Create MotionConfig**

Create `lib/core/ui/motion/motion_config.dart`:

```dart
import 'package:flutter/widgets.dart';

/// Central reduced-motion switch for the CMPYS motion kit.
///
/// Reads the platform "disable animations" accessibility setting. Kit
/// widgets collapse to plain fades (or render statically) when motion is
/// off — screens never check this themselves.
abstract final class MotionConfig {
  static bool enabled(BuildContext context) =>
      !MediaQuery.disableAnimationsOf(context);
}
```

- [ ] **Step 4: Verify**

Run: `flutter analyze`
Expected: No issues found.
Run: `flutter test`
Expected: all existing tests pass.

- [ ] **Step 5: Commit**

```bash
git add pubspec.yaml pubspec.lock lib/app/design_tokens.dart lib/core/ui/motion/motion_config.dart
git commit -m "feat(motion): flutter_animate dep, stagger token, MotionConfig"
```

---

### Task 2: Entrance + EntranceGroup

**Files:**
- Create: `lib/core/ui/motion/entrance.dart`
- Test: `test/motion_entrance_test.dart`

**Interfaces:**
- Consumes: `MotionConfig.enabled(context)`, `AppDurations.normal/.stagger`, `AppCurves.easeOut` (Task 1).
- Produces: `Entrance({int index = 0, required Widget child})` widget; `Entrance.delayFor(int index) → Duration`; `EntranceGroup.wrap(List<Widget> children) → List<Widget>`. Tasks 7–9 wrap ListView children with `EntranceGroup.wrap`.

- [ ] **Step 1: Write the failing tests**

Create `test/motion_entrance_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:cmpys/app/design_tokens.dart';
import 'package:cmpys/core/ui/motion/entrance.dart';

void main() {
  testWidgets('Entrance renders its child and settles', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(home: Entrance(child: Text('hello'))),
    );
    expect(find.text('hello'), findsOneWidget);
    await tester.pumpAndSettle();
    expect(find.text('hello'), findsOneWidget);
  });

  testWidgets('Entrance renders under reduced motion', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: const MediaQueryData(disableAnimations: true),
          child: const Entrance(child: Text('calm')),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('calm'), findsOneWidget);
  });

  test('stagger delay is capped at index 6', () {
    expect(Entrance.delayFor(0), Duration.zero);
    expect(Entrance.delayFor(3), AppDurations.stagger * 3);
    expect(Entrance.delayFor(6), AppDurations.stagger * 6);
    expect(Entrance.delayFor(30), AppDurations.stagger * 6);
  });

  test('EntranceGroup.wrap wraps each child with its index', () {
    final wrapped = EntranceGroup.wrap([const Text('a'), const Text('b')]);
    expect(wrapped.length, 2);
    expect((wrapped[0] as Entrance).index, 0);
    expect((wrapped[1] as Entrance).index, 1);
  });
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `flutter test test/motion_entrance_test.dart`
Expected: FAIL — `entrance.dart` does not exist.

- [ ] **Step 3: Implement**

Create `lib/core/ui/motion/entrance.dart`:

```dart
import 'package:flutter/widgets.dart';
import 'package:flutter_animate/flutter_animate.dart';

import '../../../app/design_tokens.dart';
import 'motion_config.dart';

/// Fade + 12px slide-up entrance for one child.
///
/// Plays once per screen visit — the animation runs when the element is
/// first built and never re-triggers on rebuilds. Under reduced motion the
/// slide is dropped and only the fade remains.
class Entrance extends StatefulWidget {
  const Entrance({super.key, this.index = 0, required this.child});

  /// Position in an [EntranceGroup] cascade.
  final int index;
  final Widget child;

  /// Items beyond this index animate together (no extra delay), so long
  /// lists never feel sluggish.
  static const int maxStagger = 6;

  static Duration delayFor(int index) =>
      AppDurations.stagger * index.clamp(0, maxStagger);

  @override
  State<Entrance> createState() => _EntranceState();
}

class _EntranceState extends State<Entrance> {
  bool _played = false;

  @override
  Widget build(BuildContext context) {
    if (_played) return widget.child;

    final animated = widget.child.animate(
      delay: Entrance.delayFor(widget.index),
      onComplete: (_) {
        if (mounted) setState(() => _played = true);
      },
    )..fadeIn(duration: AppDurations.normal, curve: AppCurves.easeOut);

    if (MotionConfig.enabled(context)) {
      animated.move(
        begin: const Offset(0, 12),
        end: Offset.zero,
        duration: AppDurations.normal,
        curve: AppCurves.easeOut,
      );
    }
    return animated;
  }
}

/// Wraps a screen's top-level children in a staggered entrance cascade.
abstract final class EntranceGroup {
  static List<Widget> wrap(List<Widget> children) => [
        for (var i = 0; i < children.length; i++)
          Entrance(index: i, child: children[i]),
      ];
}
```

Note: `child.animate(...)` returns an `Animate` widget; `..fadeIn` / `.move` add effects to it (flutter_animate's fluent API mutates the effect list, so the cascade + conditional add works).

- [ ] **Step 4: Run tests to verify they pass**

Run: `flutter test test/motion_entrance_test.dart`
Expected: 4 tests PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/core/ui/motion/entrance.dart test/motion_entrance_test.dart
git commit -m "feat(motion): Entrance + EntranceGroup staggered cascade"
```

---

### Task 3: CmpysSkeleton shimmer primitives

**Files:**
- Create: `lib/core/ui/motion/skeleton.dart`
- Test: `test/motion_skeleton_test.dart`

**Interfaces:**
- Consumes: `MotionConfig.enabled(context)` (Task 1), `AppColors.paper2`, `AppRadii`.
- Produces: `CmpysSkeleton.block({double height, double width, BorderRadius radius})`, `CmpysSkeleton.line({double width, double height, BorderRadius radius})`, `CmpysSkeleton.circle({double size})`. Tasks 7–8 build loading layouts from these.

- [ ] **Step 1: Write the failing tests**

Create `test/motion_skeleton_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:cmpys/app/design_tokens.dart';
import 'package:cmpys/core/ui/motion/skeleton.dart';

void main() {
  testWidgets('block renders a paper2 container of the given height',
      (tester) async {
    await tester.pumpWidget(
      const MaterialApp(home: CmpysSkeleton.block(height: 96)),
    );
    // One pump only — the shimmer loops forever, pumpAndSettle would hang.
    await tester.pump(const Duration(milliseconds: 100));
    final box = tester.widget<Container>(find.descendant(
      of: find.byType(CmpysSkeleton),
      matching: find.byType(Container),
    ));
    expect((box.decoration as BoxDecoration).color, AppColors.paper2);
  });

  testWidgets('renders statically under reduced motion', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: const MediaQueryData(disableAnimations: true),
          child: const CmpysSkeleton.block(height: 96),
        ),
      ),
    );
    // Static skeleton must settle (no looping animation).
    await tester.pumpAndSettle();
    expect(find.byType(Container), findsOneWidget);
  });
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `flutter test test/motion_skeleton_test.dart`
Expected: FAIL — `skeleton.dart` does not exist.

- [ ] **Step 3: Implement**

Create `lib/core/ui/motion/skeleton.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';

import '../../../app/design_tokens.dart';
import 'motion_config.dart';

/// Shimmer placeholder primitives for screen-level loading states.
///
/// Grey blocks matching the existing loading-card look (paper2), with a
/// soft white sweep looping while motion is enabled. Compose them to
/// mirror the real layout they replace.
class CmpysSkeleton extends StatelessWidget {
  const CmpysSkeleton.block({
    super.key,
    this.height = 96,
    this.width = double.infinity,
    this.radius = AppRadii.lg,
  });

  const CmpysSkeleton.line({
    super.key,
    this.width = 140,
    this.height = 14,
    this.radius = AppRadii.br8,
  });

  const CmpysSkeleton.circle({super.key, double size = 40})
      : width = size,
        height = size,
        radius = AppRadii.brFull;

  final double width;
  final double height;
  final BorderRadius radius;

  @override
  Widget build(BuildContext context) {
    final block = Container(
      width: width,
      height: height,
      decoration: BoxDecoration(color: AppColors.paper2, borderRadius: radius),
    );
    if (!MotionConfig.enabled(context)) return block;
    return block
        .animate(onPlay: (controller) => controller.repeat())
        .shimmer(
          duration: const Duration(milliseconds: 1200),
          color: Colors.white.withValues(alpha: 0.6),
        );
  }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `flutter test test/motion_skeleton_test.dart`
Expected: 2 tests PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/core/ui/motion/skeleton.dart test/motion_skeleton_test.dart
git commit -m "feat(motion): CmpysSkeleton shimmer primitives"
```

---

### Task 4: CmpysPageTransition + routes

**Files:**
- Create: `lib/core/ui/motion/page_transition.dart`
- Test: `test/motion_page_transition_test.dart`

**Interfaces:**
- Consumes: `AppDurations.normal`, `AppCurves.easeOut` (Task 1).
- Produces: `CmpysPageTransition.page<T>({required Widget child, LocalKey? key}) → CustomTransitionPage<T>` (go_router); `CmpysPageRoute<T>({required WidgetBuilder builder})` (replaces MaterialPageRoute); `CmpysSheetRoute<T>({required WidgetBuilder builder})` (slide-up, for the Record modal). Tasks 5–6 consume all three.

- [ ] **Step 1: Write the failing tests**

Create `test/motion_page_transition_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:cmpys/core/ui/motion/page_transition.dart';

void main() {
  testWidgets('CmpysPageRoute pushes and completes', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () => Navigator.of(context).push(
              CmpysPageRoute<void>(builder: (_) => const Text('detail')),
            ),
            child: const Text('go'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('go'));
    await tester.pumpAndSettle();
    expect(find.text('detail'), findsOneWidget);
    // And back.
    final nav = tester.state<NavigatorState>(find.byType(Navigator));
    nav.pop();
    await tester.pumpAndSettle();
    expect(find.text('go'), findsOneWidget);
  });

  testWidgets('CmpysSheetRoute pushes and completes', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () => Navigator.of(context).push(
              CmpysSheetRoute<void>(builder: (_) => const Text('sheet')),
            ),
            child: const Text('open'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.text('sheet'), findsOneWidget);
  });
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `flutter test test/motion_page_transition_test.dart`
Expected: FAIL — `page_transition.dart` does not exist.

- [ ] **Step 3: Implement**

Create `lib/core/ui/motion/page_transition.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../app/design_tokens.dart';

/// Shared fade-through page transition — the CMPYS navigation language.
///
/// Incoming content fades in while sliding up slightly; under reduced
/// motion only the fade remains. Exposed for go_router ([page]) and for
/// imperative pushes ([CmpysPageRoute]); modal entry screens use the
/// bottom-sheet-style [CmpysSheetRoute] instead.
abstract final class CmpysPageTransition {
  static const Duration duration = AppDurations.normal;

  static Widget buildTransition(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    final curved = CurvedAnimation(parent: animation, curve: AppCurves.easeOut);
    final fade = FadeTransition(opacity: curved, child: child);
    if (MediaQuery.disableAnimationsOf(context)) return fade;
    return SlideTransition(
      position: Tween<Offset>(
        begin: const Offset(0, 0.02), // ~16px on a typical phone height
        end: Offset.zero,
      ).animate(curved),
      child: fade,
    );
  }

  /// go_router page with the shared fade-through transition.
  static CustomTransitionPage<T> page<T>({
    required Widget child,
    LocalKey? key,
  }) {
    return CustomTransitionPage<T>(
      key: key,
      child: child,
      transitionDuration: duration,
      reverseTransitionDuration: duration,
      transitionsBuilder: buildTransition,
    );
  }
}

/// Fade-through route for imperative detail pushes (replaces
/// MaterialPageRoute across the app).
class CmpysPageRoute<T> extends PageRouteBuilder<T> {
  CmpysPageRoute({required WidgetBuilder builder})
      : super(
          transitionDuration: CmpysPageTransition.duration,
          reverseTransitionDuration: CmpysPageTransition.duration,
          pageBuilder: (context, animation, secondaryAnimation) =>
              builder(context),
          transitionsBuilder: CmpysPageTransition.buildTransition,
        );
}

/// Bottom-sheet-style slide-up route for modal entry screens (Record).
class CmpysSheetRoute<T> extends PageRouteBuilder<T> {
  CmpysSheetRoute({required WidgetBuilder builder})
      : super(
          transitionDuration: CmpysPageTransition.duration,
          reverseTransitionDuration: CmpysPageTransition.duration,
          pageBuilder: (context, animation, secondaryAnimation) =>
              builder(context),
          transitionsBuilder: (context, animation, secondaryAnimation, child) {
            final curved =
                CurvedAnimation(parent: animation, curve: AppCurves.easeOut);
            if (MediaQuery.disableAnimationsOf(context)) {
              return FadeTransition(opacity: curved, child: child);
            }
            return SlideTransition(
              position: Tween<Offset>(
                begin: const Offset(0, 1),
                end: Offset.zero,
              ).animate(curved),
              child: child,
            );
          },
        );
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `flutter test test/motion_page_transition_test.dart`
Expected: 2 tests PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/core/ui/motion/page_transition.dart test/motion_page_transition_test.dart
git commit -m "feat(motion): fade-through page transition + sheet route"
```

---

### Task 5: Wire transitions into the router and tab switches

**Files:**
- Modify: `lib/app/router.dart` (every GoRoute `builder:` → `pageBuilder:`)
- Modify: `lib/core/ui/app_shell.dart:74-93` (wrap navigationShell in a fade-on-switch)

**Interfaces:**
- Consumes: `CmpysPageTransition.page` (Task 4), `AppDurations.fast`, `AppCurves.easeOut`.
- Produces: nothing consumed later — this is leaf wiring.

- [ ] **Step 1: Convert router builders**

In `lib/app/router.dart`, add the import:

```dart
import '../core/ui/motion/page_transition.dart';
```

Convert every `GoRoute` from `builder:` to `pageBuilder:`. Pattern (apply to all nine routes — splash, auth, forgotPassword, cmpysOnboarding, ideas, and the five shell-branch routes):

```dart
GoRoute(
  path: AppRoutes.splash,
  pageBuilder: (context, state) => CmpysPageTransition.page(
    key: state.pageKey,
    child: const SplashScreen(),
  ),
),
```

Also update the class doc comment at `router.dart:21` — change "pushed with `MaterialPageRoute`" to "pushed with `CmpysPageRoute`" (Task 6 makes that true).

- [ ] **Step 2: Add the tab-switch fade**

In `lib/core/ui/app_shell.dart`, change the body Stack's first child from:

```dart
Positioned.fill(child: navigationShell),
```

to:

```dart
Positioned.fill(
  child: _TabFade(
    index: navigationShell.currentIndex,
    child: navigationShell,
  ),
),
```

and add at the bottom of the file:

```dart
/// Fades the incoming branch in on tab switch (the IndexedStack swap is
/// otherwise a hard cut). The outgoing branch disappears instantly —
/// duplicating the shell tree for a cross-fade would break its GlobalKeys.
class _TabFade extends StatefulWidget {
  const _TabFade({required this.index, required this.child});

  final int index;
  final Widget child;

  @override
  State<_TabFade> createState() => _TabFadeState();
}

class _TabFadeState extends State<_TabFade>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: AppDurations.fast,
    value: 1,
  );

  @override
  void didUpdateWidget(_TabFade oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.index != widget.index &&
        !MediaQuery.disableAnimationsOf(context)) {
      _controller.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: CurvedAnimation(parent: _controller, curve: AppCurves.easeOut),
      child: widget.child,
    );
  }
}
```

- [ ] **Step 3: Verify**

Run: `flutter analyze`
Expected: No issues found.
Run: `flutter test`
Expected: all tests pass (including `test/app_shell_test.dart`).

- [ ] **Step 4: Commit**

```bash
git add lib/app/router.dart lib/core/ui/app_shell.dart
git commit -m "feat(motion): fade-through router transitions + tab-switch fade"
```

---

### Task 6: Replace MaterialPageRoute app-wide

**Files:**
- Test: `test/motion_no_material_page_route_test.dart` (create — source-scan test, same pattern as `test/no_legacy_design_copy_test.dart`)
- Modify (every `MaterialPageRoute` call site):
  - `lib/features/cmpys/presentation/you_screen.dart` (~8 sites: lines 55, 89, 94, 98, 115, 120, 123, 192)
  - `lib/features/cmpys/presentation/chat_screen.dart:309`
  - `lib/features/cmpys/presentation/detail_screens.dart` (~9 sites: lines 401, 408, 413, 455, 1221, 1231, 1240, 1247, 1260)
  - `lib/features/cmpys/presentation/compare_screen.dart:236` and `:270`
  - `lib/features/cmpys/presentation/plan_screen.dart:285` and `:356`
  - `lib/features/plan/presentation/backend_plan_widgets.dart:18`
  - `lib/features/plan/presentation/plan_item_detail_screen.dart:405`

**Interfaces:**
- Consumes: `CmpysPageRoute`, `CmpysSheetRoute` (Task 4).
- Produces: nothing consumed later.

- [ ] **Step 1: Write the failing source-scan test**

Create `test/motion_no_material_page_route_test.dart`:

```dart
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('feature code uses CmpysPageRoute/CmpysSheetRoute, not MaterialPageRoute',
      () {
    final offenders = Directory('lib/features')
        .listSync(recursive: true)
        .whereType<File>()
        .where((f) => f.path.endsWith('.dart'))
        .where((f) => f.readAsStringSync().contains('MaterialPageRoute'))
        .map((f) => f.path)
        .toList();
    expect(offenders, isEmpty,
        reason:
            'Push details with CmpysPageRoute (or CmpysSheetRoute for modal '
            'entry screens) from lib/core/ui/motion/page_transition.dart.');
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/motion_no_material_page_route_test.dart`
Expected: FAIL listing ~7 offending files.

- [ ] **Step 3: Replace the call sites**

In every file listed above, add the motion import (path from `lib/features/cmpys/presentation/`):

```dart
import '../../../core/ui/motion/page_transition.dart';
```

(from `lib/features/plan/presentation/` it is the same `../../../core/ui/motion/page_transition.dart`).

Then replace mechanically — `MaterialPageRoute(` → `CmpysPageRoute(` and `MaterialPageRoute<void>(` → `CmpysPageRoute<void>(` — with **one exception**: the Record modal push at `compare_screen.dart:270` becomes a sheet:

```dart
CmpysSheetRoute(builder: (_) => const CmpysRecordScreen())
```

Remove any now-unused `material.dart` imports only if the analyzer flags them (it won't — these files use Material widgets throughout).

- [ ] **Step 4: Run tests to verify they pass**

Run: `flutter test test/motion_no_material_page_route_test.dart`
Expected: PASS.
Run: `flutter analyze && flutter test`
Expected: clean, all green.

- [ ] **Step 5: Commit**

```bash
git add -A lib/features test/motion_no_material_page_route_test.dart
git commit -m "feat(motion): all detail pushes use CmpysPageRoute/CmpysSheetRoute"
```

---

### Task 7: Today screen — entrances + skeletons

**Files:**
- Modify: `lib/features/cmpys/presentation/today_screen.dart` (ListView children ~line 91; `_habitsLoadingCard` ~line 650; `_ideaLoadingCard` ~line 670)

**Interfaces:**
- Consumes: `EntranceGroup.wrap` (Task 2), `CmpysSkeleton` (Task 3).
- Produces: nothing consumed later.

- [ ] **Step 1: Wrap the ListView children**

Add imports:

```dart
import '../../../core/ui/motion/entrance.dart';
import '../../../core/ui/motion/skeleton.dart';
```

At `today_screen.dart:91`, wrap the existing children list:

```dart
child: ListView(
  padding: EdgeInsets.fromLTRB(18, 14, 18, AppShell.bottomNavClearance(context)),
  children: EntranceGroup.wrap([
    _topBar(context, st, idol, name),
    // ... every existing child stays exactly as it is ...
  ]),
),
```

(Only the wrapping changes; the child expressions inside are untouched. The `..._planGeneratingHint(context, ref)` spread stays inside the list — spread elements are wrapped individually by `wrap`.)

- [ ] **Step 2: Replace the loading spinners with skeletons**

`_habitsLoadingCard` (line ~650) — replace the whole method body:

```dart
Widget _habitsLoadingCard() {
  return const CmpysSkeleton.block(height: 96);
}
```

`_ideaLoadingCard` (line ~670) — replace the Container-with-spinner (keep the kicker):

```dart
Widget _ideaLoadingCard() {
  return const Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Padding(
        padding: EdgeInsets.only(left: 2, bottom: 12),
        child: CmpysKicker('Idea for you today'),
      ),
      CmpysSkeleton.block(height: 120),
    ],
  );
}
```

Do NOT touch the small inline spinner in `_planGeneratingHint` (line ~168) — that is an in-card progress affordance, not a screen-loading state.

- [ ] **Step 3: Verify**

Run: `flutter analyze && flutter test`
Expected: clean, all green.

- [ ] **Step 4: Commit**

```bash
git add lib/features/cmpys/presentation/today_screen.dart
git commit -m "feat(motion): Today tab entrance cascade + skeleton loaders"
```

---

### Task 8: Plan screen — entrances + skeletons

**Files:**
- Modify: `lib/features/cmpys/presentation/plan_screen.dart` (ListView ~line 42; roadmap loading case ~line 152-168; daily-rhythm loading ~line 520-539)

**Interfaces:**
- Consumes: `EntranceGroup.wrap` (Task 2), `CmpysSkeleton` (Task 3).
- Produces: nothing consumed later.

- [ ] **Step 1: Wrap the ListView children**

Add imports:

```dart
import '../../../core/ui/motion/entrance.dart';
import '../../../core/ui/motion/skeleton.dart';
```

At `plan_screen.dart:42`, wrap the ListView's `children:` list with `EntranceGroup.wrap([...])`, same pattern as Task 7 Step 1.

- [ ] **Step 2: Replace the two loading spinners**

Roadmap `CurrentPlanStatus.loading` case (~line 152) — replace the centered spinner block with a skeleton stack that mirrors week cards:

```dart
case CurrentPlanStatus.loading:
  return [
    ...blueprint,
    const CmpysSkeleton.block(height: 120),
    const SizedBox(height: 12),
    const CmpysSkeleton.block(height: 120),
    const SizedBox(height: 12),
    const CmpysSkeleton.block(height: 120),
  ];
```

Daily-rhythm `today == null` case (~line 520) — replace the Container-with-spinner:

```dart
if (today == null) {
  return [const CmpysSkeleton.block(height: 96)];
}
```

- [ ] **Step 3: Verify**

Run: `flutter analyze && flutter test`
Expected: clean, all green.

- [ ] **Step 4: Commit**

```bash
git add lib/features/cmpys/presentation/plan_screen.dart
git commit -m "feat(motion): Plan tab entrance cascade + skeleton loaders"
```

---

### Task 9: Compare, You, Chat — entrances

**Files:**
- Modify: `lib/features/cmpys/presentation/compare_screen.dart` (ListView ~line 58)
- Modify: `lib/features/cmpys/presentation/you_screen.dart` (ListView ~line 35)
- Modify: `lib/features/cmpys/presentation/chat_screen.dart` (intro header inside `_messages`, ~line 331)

**Interfaces:**
- Consumes: `Entrance`, `EntranceGroup.wrap` (Task 2).
- Produces: nothing consumed later.

- [ ] **Step 1: Compare + You**

In both files add:

```dart
import '../../../core/ui/motion/entrance.dart';
```

and wrap each screen's top-level `ListView(children: [...])` list with `EntranceGroup.wrap([...])` — same pattern as Task 7 Step 1. All existing child expressions stay untouched (including the `...c.strengths.map(_strengthCard)` spread in compare_screen).

- [ ] **Step 2: Chat intro only**

Chat's ListView is the message log — messages must NOT cascade (streaming content stays plain per the spec). Only the intro header (mentor avatar + name + hint, the first `Center(...)` child inside `_messages` at ~line 332) gets a single entrance:

```dart
children: [
  Entrance(
    child: Center(
      child: Column(
        // ... existing avatar/name/hint Column unchanged ...
      ),
    ),
  ),
  const SizedBox(height: 18),
  // ... rest of the message children unchanged ...
],
```

Add the same entrance import to chat_screen.dart.

- [ ] **Step 3: Verify**

Run: `flutter analyze && flutter test`
Expected: clean, all green.

- [ ] **Step 4: Full-suite sanity + commit**

Run: `flutter test`
Expected: all tests pass, including the four motion test files.

```bash
git add lib/features/cmpys/presentation/compare_screen.dart lib/features/cmpys/presentation/you_screen.dart lib/features/cmpys/presentation/chat_screen.dart
git commit -m "feat(motion): entrance cascades on Compare, You, Chat tabs"
```

---

## Manual verification (after all tasks)

On the iOS simulator (`flutter run`):
1. Splash → auth → shell: every route change fades through.
2. Switch all five tabs: incoming tab fades in (200ms); nav pill spring unchanged.
3. Each tab's first view: cascade entrance; switch away and back: content appears instantly (no replay).
4. Today/Plan with a cold backend: shimmer skeletons instead of spinners.
5. Push a detail (pillar, settings, idol): fade-through; open Record from Compare: slides up.
6. Enable "Reduce Motion" in simulator accessibility settings: everything still works, fades only, skeletons static.
