import 'dart:async';

import 'support/design_capture.dart';
import 'package:cmpys/app/design_tokens.dart';
import 'package:cmpys/app/router.dart';
import 'package:cmpys/core/ui/app_shell.dart';
import 'package:cmpys/core/ui/motion/page_transition.dart';
import 'package:cmpys/core/ui/v3/v3.dart';
import 'package:cmpys/features/cmpys/data/cmpys_seed.dart';
import 'package:cmpys/features/cmpys/data/record_restore.dart';
import 'package:cmpys/features/cmpys/state/cmpys_backend_sync.dart';
import 'package:cmpys/features/cmpys/state/cmpys_store.dart';
import 'package:cmpys/features/plan/models/plan_models.dart';
import 'package:cmpys/features/plan/state/current_plan_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _shellPaths = ['/one', '/two', '/three', '/four', '/five'];

GoRouter _buildShellRouter({
  bool scrollable = false,
  String? initialLocation,
}) => GoRouter(
  initialLocation: initialLocation ?? _shellPaths.first,
  routes: [
    StatefulShellRoute.indexedStack(
      builder: (_, _, navigationShell) =>
          AppShell(navigationShell: navigationShell),
      branches: [
        for (final path in _shellPaths)
          StatefulShellBranch(
            observers: [ShellPushObserver()],
            routes: [
              GoRoute(
                path: path,
                routes: [
                  GoRoute(
                    path: 'detail',
                    builder: (_, _) => const ColoredBox(
                      color: Colors.white,
                      child: Text('detail'),
                    ),
                  ),
                ],
                builder: (_, _) => scrollable
                    ? ListView(
                        children: [
                          Text(path),
                          for (var i = 0; i < 60; i++)
                            SizedBox(height: 80, child: Text('$path row $i')),
                        ],
                      )
                    : ColoredBox(color: Colors.white, child: Text(path)),
              ),
            ],
          ),
      ],
    ),
  ],
);

/// A store seeded with a mentor, so the centre tab has a portrait to show.
class _ShellStore extends CmpysStore {
  _ShellStore(CmpysIdol idol) {
    state = state.copyWith(idol: idol);
  }
}

TodayTaskItem _habit(String id, {required bool done}) => TodayTaskItem(
  id: id,
  title: 'Habit $id',
  type: 'habit',
  estimatedHours: 1,
  completedToday: done,
);

TodayView _today(List<TodayTaskItem> items) => TodayView(
  items: items,
  streak: 0,
  completedToday: items.where((i) => i.completedToday).length,
  totalToday: items.length,
);

/// How many times the shell started the Record restore.
var _restores = 0;

List<Override> _shellOverrides({
  Future<TodayView?> Function()? today,
  CmpysIdol? mentor,
}) => [
  cmpysBackendSyncProvider.overrideWith((ref) async {}),
  cmpysRecordRestoreProvider.overrideWith((ref) async => _restores++),
  todayViewProvider.overrideWith((ref) => (today ?? () async => null)()),
  cmpysStoreProvider.overrideWith(
    (ref) => _ShellStore(mentor ?? cmpysPlaceholderIdol),
  ),
];

Widget _shellApp(
  GoRouter router, {
  bool disableAnimations = false,
  Future<TodayView?> Function()? today,
  CmpysIdol? mentor,
}) {
  return ProviderScope(
    overrides: _shellOverrides(today: today, mentor: mentor),
    child: MaterialApp.router(
      routerConfig: router,
      builder: disableAnimations
          ? (context, child) => MediaQuery(
              data: MediaQuery.of(context).copyWith(disableAnimations: true),
              child: child!,
            )
          : null,
    ),
  );
}

const _pill = Key('v3-tab-bar');

double _pillHeight(WidgetTester tester) =>
    tester.getSize(find.byKey(_pill)).height;

/// The glass's outline (rounded pill minus the notch) at the given height.
Path _glassPath(WidgetTester tester, double height) => tester
    .widget<ClipPath>(find.byKey(const Key('tab-bar-glass-clip')))
    .clipper!
    .getClip(Size(350, height));

double _labelOpacity(WidgetTester tester, int i) => tester
    .widget<AnimatedOpacity>(find.byKey(ValueKey('tab-bar-label-$i')))
    .opacity;

void main() {
  setUpAll(prepareDesignCapture);
  test('app shell uses the canonical five-tab IA', () {
    expect(
      appShellDestinations.map((destination) => destination.label).toList(),
      ['Today', 'Plan', 'Mentor', 'Compare', 'You'],
    );
  });

  for (final textScale in [1.0, 2.0]) {
    testWidgets(
      'all five navigation labels remain visible at $textScale scale',
      (tester) async {
        tester.view.physicalSize = const Size(320, 568);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        addTearDown(() => tester.binding.setSurfaceSize(null));
        final router = _buildShellRouter();
        addTearDown(router.dispose);
        await tester.pumpWidget(
          ProviderScope(
            overrides: _shellOverrides(),
            child: MaterialApp.router(
              routerConfig: router,
              builder: (context, child) => MediaQuery(
                data: MediaQuery.of(
                  context,
                ).copyWith(textScaler: TextScaler.linear(textScale)),
                child: RepaintBoundary(key: designCaptureKey, child: child!),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        await captureDesign(tester, 'navigation-$textScale');
        for (var i = 0; i < appShellDestinations.length; i++) {
          final label = find.text(appShellDestinations[i].label);
          expect(label.hitTestable(), findsOneWidget);
          final target = find.byKey(ValueKey('floating-nav-item-$i'));
          expect(tester.getSize(target).width, greaterThanOrEqualTo(48));
          expect(tester.getSize(target).height, greaterThanOrEqualTo(48));
          await tester.tap(target);
          await tester.pumpAndSettle();
          expect(find.text(_shellPaths[i]), findsOneWidget);
          expect(tester.takeException(), isNull);
        }
      },
    );
  }

  testWidgets('branch content drops nav clearance while keyboard is open', (
    tester,
  ) async {
    double? clearance;
    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: const MediaQueryData(viewInsets: EdgeInsets.only(bottom: 300)),
          child: Builder(
            builder: (context) {
              clearance = AppShell.bottomNavClearance(context, extra: 2);
              return const SizedBox.shrink();
            },
          ),
        ),
      ),
    );

    expect(clearance, 14);
  });

  testWidgets('navigation hides for the keyboard and returns after dismissal', (
    tester,
  ) async {
    final router = _buildShellRouter();
    addTearDown(router.dispose);
    addTearDown(tester.view.resetViewInsets);
    await tester.pumpWidget(_shellApp(router));
    await tester.pumpAndSettle();
    expect(find.text('Today'), findsOneWidget);
    tester.view.viewInsets = const FakeViewPadding(bottom: 300);
    await tester.pumpAndSettle();
    expect(find.text('Today'), findsNothing);
    tester.view.resetViewInsets();
    await tester.pumpAndSettle();
    expect(find.text('Today'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('shell leaves keyboard resizing to its active branch', (
    tester,
  ) async {
    final router = _buildShellRouter();
    addTearDown(router.dispose);

    await tester.pumpWidget(_shellApp(router));
    await tester.pumpAndSettle();

    final shellScaffold = find.descendant(
      of: find.byType(AppShell),
      matching: find.byType(Scaffold),
    );
    expect(shellScaffold, findsOneWidget);
    expect(
      tester.widget<Scaffold>(shellScaffold).resizeToAvoidBottomInset,
      isFalse,
    );

    final systemUi = tester.widget<AnnotatedRegion<SystemUiOverlayStyle>>(
      find.descendant(
        of: find.byType(AppShell),
        matching: find.byType(AnnotatedRegion<SystemUiOverlayStyle>),
      ),
    );
    expect(systemUi.value.statusBarIconBrightness, Brightness.dark);
    expect(systemUi.value.systemNavigationBarIconBrightness, Brightness.dark);
  });

  testWidgets('floating selector visibly travels to the selected tab', (
    tester,
  ) async {
    final router = _buildShellRouter();
    addTearDown(router.dispose);
    await tester.pumpWidget(_shellApp(router));
    await tester.pumpAndSettle();

    final selector = find.byKey(const ValueKey('floating-nav-selector'));
    final planTab = find.byKey(const ValueKey('floating-nav-item-1'));
    final startX = tester.getCenter(selector).dx;

    await tester.tap(planTab);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    final midX = tester.getCenter(selector).dx;

    await tester.pumpAndSettle();
    final endX = tester.getCenter(selector).dx;

    expect(midX, greaterThan(startX));
    expect(midX, lessThan(endX));
    expect(find.text('/two'), findsOneWidget);
  });

  testWidgets('floating selector snaps under reduced motion', (tester) async {
    final router = _buildShellRouter();
    addTearDown(router.dispose);
    await tester.pumpWidget(_shellApp(router, disableAnimations: true));
    await tester.pumpAndSettle();

    final selector = find.byKey(const ValueKey('floating-nav-selector'));
    final planTab = find.byKey(const ValueKey('floating-nav-item-1'));
    final startX = tester.getTopLeft(selector).dx;

    await tester.tap(planTab);
    await tester.pump();
    final selectedX = tester.getTopLeft(selector).dx;
    await tester.pump(const Duration(milliseconds: 100));

    expect(selectedX, greaterThan(startX));
    expect(tester.getTopLeft(selector).dx, closeTo(selectedX, 0.01));
  });

  testWidgets('entering the app restores the Record from the server (owner '
      'decision 1)', (tester) async {
    _restores = 0;
    final router = _buildShellRouter();
    addTearDown(router.dispose);
    await tester.pumpWidget(_shellApp(router));
    await tester.pumpAndSettle();
    expect(_restores, 1);
    // Switching tabs doesn't fetch again.
    await tester.tap(find.byKey(const ValueKey('floating-nav-item-1')));
    await tester.pumpAndSettle();
    expect(_restores, 1);
  });

  testWidgets('centre_tab_shows_mentor_label', (tester) async {
    final semantics = tester.ensureSemantics();
    final router = _buildShellRouter();
    addTearDown(router.dispose);
    await tester.pumpWidget(_shellApp(router));
    await tester.pumpAndSettle();

    expect(find.text('Mentor'), findsOneWidget);
    expect(find.text('Chat'), findsNothing);
    Finder centre() => find.bySemanticsLabel('Mentor');
    expect(
      tester.getSemantics(centre()),
      containsSemantics(
        label: 'Mentor',
        isButton: true,
        hasSelectedState: true,
        isSelected: false,
      ),
    );

    await tester.tap(find.byKey(const ValueKey('floating-nav-item-2')));
    await tester.pumpAndSettle();
    expect(find.text('/three'), findsOneWidget);
    expect(
      tester.getSemantics(centre()),
      containsSemantics(
        label: 'Mentor',
        isButton: true,
        hasSelectedState: true,
        isSelected: true,
      ),
    );
    semantics.dispose();
  });

  group('mentor avatar', () {
    setUp(() => SharedPreferences.setMockInitialValues({}));

    testWidgets('shows the selected mentor greyscale with an online dot', (
      tester,
    ) async {
      final router = _buildShellRouter();
      addTearDown(router.dispose);
      await tester.pumpWidget(_shellApp(router, mentor: cmpysIdols.first));
      await tester.pumpAndSettle();

      final avatar = find.byKey(const Key('tab-bar-mentor-avatar'));
      expect(avatar, findsOneWidget);
      expect(
        find.descendant(of: avatar, matching: find.byType(ColorFiltered)),
        findsOneWidget,
        reason: 'the portrait is rendered grayscale with contrast',
      );
      expect(
        find.descendant(of: avatar, matching: find.byType(Image)),
        findsOneWidget,
      );
      final dot = find.byKey(const Key('tab-bar-online-dot'));
      expect(tester.getSize(dot), const Size(11, 11));
      expect(
        (tester.widget<DecoratedBox>(dot).decoration as BoxDecoration).color,
        const Color(0xFF43A96E),
      );
    });

    testWidgets('falls back to initials without a portrait', (tester) async {
      final router = _buildShellRouter();
      addTearDown(router.dispose);
      await tester.pumpWidget(_shellApp(router));
      await tester.pumpAndSettle();

      final avatar = find.byKey(const Key('tab-bar-mentor-avatar'));
      expect(
        find.descendant(of: avatar, matching: find.byType(Image)),
        findsNothing,
      );
      expect(
        find.descendant(of: avatar, matching: find.text('M')),
        findsOneWidget,
      );
    });

    testWidgets('the ember conic ring only shows while Mentor is active', (
      tester,
    ) async {
      final router = _buildShellRouter();
      addTearDown(router.dispose);
      await tester.pumpWidget(_shellApp(router));
      await tester.pumpAndSettle();

      final ring = find.byKey(const Key('tab-bar-mentor-ring'));
      BoxDecoration decoration() =>
          tester.widget<DecoratedBox>(ring).decoration as BoxDecoration;
      expect(decoration().gradient, isNull);

      await tester.tap(find.byKey(const ValueKey('floating-nav-item-2')));
      await tester.pumpAndSettle();
      final gradient = decoration().gradient! as SweepGradient;
      expect(gradient.colors, [
        const Color(0xFFEC6E38),
        const Color(0xFFE4B750),
        const Color(0xFF8A81EF),
        const Color(0xFFEC6E38),
      ]);
    });
  });

  group('Today badge', () {
    testWidgets('today_badge_counts_undone_habits', (tester) async {
      final router = _buildShellRouter();
      addTearDown(router.dispose);
      await tester.pumpWidget(
        _shellApp(
          router,
          today: () async => _today([
            _habit('a', done: false),
            _habit('b', done: true),
            _habit('c', done: false),
          ]),
        ),
      );
      await tester.pumpAndSettle();

      final badge = find.byKey(const Key('tab-bar-badge'));
      expect(badge, findsOneWidget);
      expect(
        find.descendant(of: badge, matching: find.text('2')),
        findsOneWidget,
      );
      expect(tester.getSize(badge).height, 16);
      expect(
        tester.getSize(badge).width,
        greaterThanOrEqualTo(16),
        reason: 'min width 16',
      );
      final decoration =
          tester.widget<Container>(badge).decoration! as BoxDecoration;
      expect(decoration.color, const Color(0xFFEC6E38));
    });

    testWidgets('the count reaches screen readers without renaming the tab', (
      tester,
    ) async {
      final semantics = tester.ensureSemantics();
      final router = _buildShellRouter();
      addTearDown(router.dispose);
      await tester.pumpWidget(
        _shellApp(
          router,
          today: () async =>
              _today([_habit('a', done: false), _habit('b', done: false)]),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        tester.getSemantics(find.bySemanticsLabel('Today')),
        containsSemantics(
          label: 'Today',
          value: '2 left',
          isButton: true,
          hasSelectedState: true,
          isSelected: true,
        ),
      );
      semantics.dispose();
    });

    for (final scenario in <String, Future<TodayView?> Function()>{
      'every habit is done': () async =>
          _today([_habit('a', done: true), _habit('b', done: true)]),
      'there are no habits': () async => _today(const []),
      'the plan is not ready': () async => null,
      'today has not loaded yet': () => Completer<TodayView?>().future,
    }.entries) {
      testWidgets('is hidden when ${scenario.key}', (tester) async {
        final router = _buildShellRouter();
        addTearDown(router.dispose);
        await tester.pumpWidget(_shellApp(router, today: scenario.value));
        await tester.pumpAndSettle();
        expect(find.text('Today'), findsOneWidget);
        expect(find.byKey(const Key('tab-bar-badge')), findsNothing);
      });
    }

    testWidgets('follows habits as they are ticked off', (tester) async {
      final router = _buildShellRouter();
      addTearDown(router.dispose);
      var done = false;
      await tester.pumpWidget(
        _shellApp(
          router,
          today: () async =>
              _today([_habit('a', done: done), _habit('b', done: false)]),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        find.descendant(
          of: find.byKey(const Key('tab-bar-badge')),
          matching: find.text('2'),
        ),
        findsOneWidget,
      );
      done = true;
      ProviderScope.containerOf(
        tester.element(find.byType(AppShell)),
      ).invalidate(todayViewProvider);
      await tester.pumpAndSettle();
      expect(
        find.descendant(
          of: find.byKey(const Key('tab-bar-badge')),
          matching: find.text('1'),
        ),
        findsOneWidget,
      );
    });
  });

  group('compact mode', () {
    Finder scrollable() => find.byType(ListView).first;

    testWidgets('tab_bar_compacts_on_scroll_down_and_restores_on_up', (
      tester,
    ) async {
      final router = _buildShellRouter(scrollable: true);
      addTearDown(router.dispose);
      await tester.pumpWidget(_shellApp(router));
      await tester.pumpAndSettle();
      expect(_pillHeight(tester), 58);
      expect(_labelOpacity(tester, 0), 1);

      // 23 pt corners and a notch 18.5 pt deep.
      expect(_glassPath(tester, 58).contains(const Offset(6.3, 6.3)), isFalse);
      expect(_glassPath(tester, 58).contains(const Offset(175, 19)), isTrue);

      await tester.drag(scrollable(), const Offset(0, -250));
      await tester.pumpAndSettle();
      expect(_pillHeight(tester), 50);
      // 20 pt corners, and the notch sits 1 pt higher (centre at -9).
      expect(_glassPath(tester, 50).contains(const Offset(6.3, 6.3)), isTrue);
      expect(_glassPath(tester, 50).contains(const Offset(175, 19)), isFalse);
      for (var i = 0; i < 5; i++) {
        expect(_labelOpacity(tester, i), 0, reason: 'label $i hidden');
      }
      // Compact is still tappable at the 44 pt minimum.
      expect(
        tester
            .getSize(find.byKey(const ValueKey('floating-nav-item-1')))
            .height,
        greaterThanOrEqualTo(44),
      );

      await tester.drag(scrollable(), const Offset(0, 120));
      await tester.pumpAndSettle();
      expect(_pillHeight(tester), 58);
      expect(_labelOpacity(tester, 0), 1);
    });

    testWidgets('does not compact until 60 px have scrolled', (tester) async {
      final router = _buildShellRouter(scrollable: true);
      addTearDown(router.dispose);
      await tester.pumpWidget(_shellApp(router));
      await tester.pumpAndSettle();

      await tester.drag(scrollable(), const Offset(0, -50));
      await tester.pumpAndSettle();
      expect(_pillHeight(tester), 58);

      await tester.drag(scrollable(), const Offset(0, -40));
      await tester.pumpAndSettle();
      expect(_pillHeight(tester), 50);
    });

    testWidgets('ignores a scroll of 8 px or less', (tester) async {
      final router = _buildShellRouter(scrollable: true);
      addTearDown(router.dispose);
      await tester.pumpWidget(_shellApp(router));
      await tester.pumpAndSettle();
      final position = tester
          .state<ScrollableState>(find.byType(Scrollable).first)
          .position;

      // Past 60 px and back to a restored bar.
      await tester.drag(scrollable(), const Offset(0, -250));
      await tester.pumpAndSettle();
      await tester.drag(scrollable(), const Offset(0, 100));
      await tester.pumpAndSettle();
      expect(_pillHeight(tester), 58);

      position.jumpTo(position.pixels + 6);
      await tester.pumpAndSettle();
      expect(_pillHeight(tester), 58, reason: '6 px is a nudge');

      // The same direction keeps adding up.
      position.jumpTo(position.pixels + 6);
      await tester.pumpAndSettle();
      expect(_pillHeight(tester), 50);
    });

    testWidgets('restores within 20 px of the bottom', (tester) async {
      final router = _buildShellRouter(scrollable: true);
      addTearDown(router.dispose);
      await tester.pumpWidget(_shellApp(router));
      await tester.pumpAndSettle();
      final position = tester
          .state<ScrollableState>(find.byType(Scrollable).first)
          .position;

      await tester.drag(scrollable(), const Offset(0, -300));
      await tester.pumpAndSettle();
      expect(_pillHeight(tester), 50);

      // Still scrolling down, but only 40 px are left: stays compact.
      position.jumpTo(position.maxScrollExtent - 40);
      await tester.pumpAndSettle();
      expect(_pillHeight(tester), 50);

      // 10 px from the end the bar comes back even though motion is downward.
      position.jumpTo(position.maxScrollExtent - 10);
      await tester.pumpAndSettle();
      expect(_pillHeight(tester), 58);
    });

    testWidgets('always restores on tab change', (tester) async {
      final router = _buildShellRouter(scrollable: true);
      addTearDown(router.dispose);
      await tester.pumpWidget(_shellApp(router));
      await tester.pumpAndSettle();

      await tester.drag(scrollable(), const Offset(0, -250));
      await tester.pumpAndSettle();
      expect(_pillHeight(tester), 50);

      await tester.tap(find.byKey(const ValueKey('floating-nav-item-3')));
      await tester.pumpAndSettle();
      expect(find.text('/four'), findsOneWidget);
      expect(_pillHeight(tester), 58);
      expect(_labelOpacity(tester, 3), 1);
    });

    testWidgets('stays full size for screen-reader navigation', (tester) async {
      final router = _buildShellRouter(scrollable: true);
      addTearDown(router.dispose);
      await tester.pumpWidget(
        ProviderScope(
          overrides: _shellOverrides(),
          child: MaterialApp.router(
            routerConfig: router,
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context).copyWith(accessibleNavigation: true),
              child: child!,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.drag(scrollable(), const Offset(0, -250));
      await tester.pumpAndSettle();
      expect(_pillHeight(tester), 58);
    });

    testWidgets('snaps instead of springing under reduced motion', (
      tester,
    ) async {
      final router = _buildShellRouter(scrollable: true);
      addTearDown(router.dispose);
      await tester.pumpWidget(_shellApp(router, disableAnimations: true));
      await tester.pumpAndSettle();
      await tester.drag(scrollable(), const Offset(0, -250));
      await tester.pump();
      expect(_pillHeight(tester), 50);
    });
  });

  group('paper fades', () {
    testWidgets('cover the tabs, 58 px on top and 104 px at the bottom', (
      tester,
    ) async {
      final router = _buildShellRouter();
      addTearDown(router.dispose);
      await tester.pumpWidget(_shellApp(router));
      await tester.pumpAndSettle();
      final size = tester.view.physicalSize / tester.view.devicePixelRatio;

      final top = find.byKey(const Key('tab-fade-top'));
      final bottom = find.byKey(const Key('tab-fade-bottom'));
      expect(tester.getTopLeft(top).dy, 0);
      expect(tester.getSize(top).height, 58);
      expect(tester.getSize(top).width, size.width);
      expect(tester.getBottomLeft(bottom).dy, size.height);
      expect(tester.getSize(bottom).height, 104);
      for (final fade in [top, bottom]) {
        expect(tester.widget<IgnorePointer>(fade).ignoring, isTrue);
        expect(
          tester
              .widget<AnimatedOpacity>(
                find.descendant(
                  of: fade,
                  matching: find.byType(AnimatedOpacity),
                ),
              )
              .opacity,
          1,
        );
      }
    });

    testWidgets('an opaque paper ground covers the status bar on tabs', (
      tester,
    ) async {
      // A phone with a 59 pt status bar (Dynamic Island): taller than the
      // design's 58 pt fade, so a fade alone let content show under the
      // clock.
      tester.view.padding = FakeViewPadding(
        top: 59 * tester.view.devicePixelRatio,
      );
      addTearDown(tester.view.resetPadding);
      final router = _buildShellRouter(scrollable: true);
      addTearDown(router.dispose);
      await tester.pumpWidget(_shellApp(router));
      await tester.pumpAndSettle();

      final ground = find.byKey(const Key('tab-ground-top'));
      expect(tester.getTopLeft(ground).dy, 0);
      expect(tester.getSize(ground).height, 59);
      expect(tester.widget<ColoredBox>(ground).color, AppColors.paper);
      expect(AppColors.paper.a, 1);
      // The fade starts under the ground and stays short.
      final top = find.byKey(const Key('tab-fade-top'));
      expect(tester.getTopLeft(top).dy, 0);
      expect(tester.getSize(top).height, 59 + 11);
      expect(tester.widget<IgnorePointer>(top).ignoring, isTrue);
      expect(find.descendant(of: top, matching: ground), findsOneWidget);

      // Off with the fade on the Mentor tab.
      await tester.tap(find.byKey(const ValueKey('floating-nav-item-2')));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<AnimatedOpacity>(
              find.ancestor(of: ground, matching: find.byType(AnimatedOpacity)),
            )
            .opacity,
        0,
      );
    });

    testWidgets('are off on the Mentor (chat) tab and back on elsewhere', (
      tester,
    ) async {
      final router = _buildShellRouter();
      addTearDown(router.dispose);
      await tester.pumpWidget(_shellApp(router));
      await tester.pumpAndSettle();
      double opacity(String key) => tester
          .widget<AnimatedOpacity>(
            find.descendant(
              of: find.byKey(Key(key)),
              matching: find.byType(AnimatedOpacity),
            ),
          )
          .opacity;

      await tester.tap(find.byKey(const ValueKey('floating-nav-item-2')));
      await tester.pumpAndSettle();
      expect(opacity('tab-fade-top'), 0);
      expect(opacity('tab-fade-bottom'), 0);

      await tester.tap(find.byKey(const ValueKey('floating-nav-item-3')));
      await tester.pumpAndSettle();
      expect(opacity('tab-fade-top'), 1);
      expect(opacity('tab-fade-bottom'), 1);
    });

    testWidgets('never swallow touches meant for the page', (tester) async {
      var taps = 0;
      final router = GoRouter(
        initialLocation: '/a',
        routes: [
          StatefulShellRoute.indexedStack(
            builder: (_, _, shell) => AppShell(navigationShell: shell),
            branches: [
              for (var i = 0; i < 5; i++)
                StatefulShellBranch(
                  routes: [
                    GoRoute(
                      path: i == 0 ? '/a' : '/b$i',
                      builder: (_, _) => Stack(
                        children: [
                          Positioned(
                            top: 4,
                            left: 100,
                            child: GestureDetector(
                              key: const Key('under-top-fade'),
                              behavior: HitTestBehavior.opaque,
                              onTap: () => taps++,
                              child: const SizedBox(width: 48, height: 48),
                            ),
                          ),
                          Positioned(
                            bottom: 72,
                            left: 100,
                            child: GestureDetector(
                              key: const Key('under-bottom-fade'),
                              behavior: HitTestBehavior.opaque,
                              onTap: () => taps++,
                              child: const SizedBox(width: 16, height: 16),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
            ],
          ),
        ],
      );
      addTearDown(router.dispose);
      await tester.pumpWidget(_shellApp(router));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('under-top-fade')));
      await tester.tap(find.byKey(const Key('under-bottom-fade')));
      expect(taps, 2);
    });
  });

  testWidgets('tab bar sits 20 px from the sides and bottom, 58 px tall', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final router = _buildShellRouter();
    addTearDown(router.dispose);
    await tester.pumpWidget(_shellApp(router));
    await tester.pumpAndSettle();

    final rect = tester.getRect(find.byKey(_pill));
    expect(rect.left, 20);
    expect(rect.right, 370);
    expect(rect.bottom, 844 - 20);
    expect(rect.height, 58);
    // The selector is 16.8% wide, inset 1.6% inside the first fifth.
    final selector = tester.getRect(
      find.byKey(const ValueKey('floating-nav-selector')),
    );
    expect(selector.left, closeTo(20 + 350 * .016, .01));
    expect(selector.width, closeTo(350 * .168, .01));
    expect(selector.top, rect.top + 6);
    expect(selector.bottom, rect.bottom - 6);
  });

  group('hidden while a page is pushed', () {
    Future<void> pumpShell(
      WidgetTester tester,
      GoRouter router, {
      bool disableAnimations = false,
    }) async {
      await tester.pumpWidget(
        _shellApp(router, disableAnimations: disableAnimations),
      );
      await tester.pumpAndSettle();
    }

    double viewportHeight(WidgetTester tester) =>
        tester.view.physicalSize.height / tester.view.devicePixelRatio;

    bool barOnScreen(WidgetTester tester) =>
        tester.getTopLeft(find.byKey(_pill)).dy < viewportHeight(tester);

    NavigatorState branchNavigator(WidgetTester tester) =>
        Navigator.of(tester.element(find.text('/one')));

    testWidgets('slides away on an imperative push and back on pop', (
      tester,
    ) async {
      final router = _buildShellRouter();
      addTearDown(router.dispose);
      await pumpShell(tester, router);
      final restingTop = tester.getTopLeft(find.byKey(_pill)).dy;
      expect(barOnScreen(tester), isTrue);

      final navigator = branchNavigator(tester);
      unawaited(
        navigator.push(
          CmpysPageRoute<void>(
            builder: (_) => const ColoredBox(
              color: Colors.white,
              child: Center(child: Text('pushed detail')),
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 120));
      final midTop = tester.getTopLeft(find.byKey(_pill)).dy;
      expect(midTop, greaterThan(restingTop), reason: 'slides, not snaps');
      expect(barOnScreen(tester), isTrue);

      await tester.pumpAndSettle();
      expect(find.text('pushed detail'), findsOneWidget);
      expect(barOnScreen(tester), isFalse, reason: 'fully off screen');
      expect(find.text('Today').hitTestable(), findsNothing);

      navigator.pop();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 120));
      expect(
        tester.getTopLeft(find.byKey(_pill)).dy,
        lessThan(viewportHeight(tester)),
        reason: 'animating back in',
      );
      await tester.pumpAndSettle();
      expect(tester.getTopLeft(find.byKey(_pill)).dy, restingTop);
      expect(find.text('Today').hitTestable(), findsOneWidget);
    });

    testWidgets('hides for declarative nested routes, also on a cold start', (
      tester,
    ) async {
      final router = _buildShellRouter(initialLocation: '/one/detail');
      addTearDown(router.dispose);
      await pumpShell(tester, router);
      expect(find.text('detail'), findsOneWidget);
      expect(barOnScreen(tester), isFalse, reason: 'cold start on a reader');

      router.go('/one');
      await tester.pumpAndSettle();
      expect(barOnScreen(tester), isTrue);

      router.go('/one/detail');
      await tester.pumpAndSettle();
      expect(barOnScreen(tester), isFalse);
    });

    testWidgets('paper fades step aside for the pushed page', (tester) async {
      final router = _buildShellRouter();
      addTearDown(router.dispose);
      await pumpShell(tester, router);
      double fade() => tester
          .widget<AnimatedOpacity>(
            find.descendant(
              of: find.byKey(const Key('tab-fade-bottom')),
              matching: find.byType(AnimatedOpacity),
            ),
          )
          .opacity;
      expect(fade(), 1);
      router.go('/one/detail');
      await tester.pumpAndSettle();
      expect(fade(), 0);
    });

    testWidgets('a dialog or sheet does not count as a page', (tester) async {
      final router = _buildShellRouter();
      addTearDown(router.dispose);
      await pumpShell(tester, router);
      unawaited(
        showDialog<void>(
          context: tester.element(find.text('/one')),
          useRootNavigator: false,
          builder: (_) => const AlertDialog(content: Text('Are you sure?')),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Are you sure?'), findsOneWidget);
      expect(barOnScreen(tester), isTrue);
    });

    testWidgets('another tab shows the bar although this one has a page', (
      tester,
    ) async {
      final router = _buildShellRouter();
      addTearDown(router.dispose);
      await pumpShell(tester, router);
      router.go('/one/detail');
      await tester.pumpAndSettle();
      expect(barOnScreen(tester), isFalse);

      // The listening menu switches branches without popping the reader.
      final shell = tester.widget<AppShell>(find.byType(AppShell));
      shell.navigationShell.goBranch(1);
      await tester.pumpAndSettle();
      expect(find.text('/two'), findsOneWidget);
      expect(barOnScreen(tester), isTrue);

      shell.navigationShell.goBranch(0);
      await tester.pumpAndSettle();
      expect(find.text('detail'), findsOneWidget);
      expect(barOnScreen(tester), isFalse);
    });

    testWidgets('snaps away under reduced motion', (tester) async {
      final router = _buildShellRouter();
      addTearDown(router.dispose);
      await pumpShell(tester, router, disableAnimations: true);
      router.go('/one/detail');
      await tester.pump();
      await tester.pump();
      expect(barOnScreen(tester), isFalse);
    });

    testWidgets('cannot be tapped or read while hidden', (tester) async {
      final router = _buildShellRouter();
      addTearDown(router.dispose);
      await pumpShell(tester, router);
      IgnorePointer touches() => tester.widget<IgnorePointer>(
        find
            .ancestor(
              of: find.byKey(_pill),
              matching: find.byType(IgnorePointer),
            )
            .first,
      );
      ExcludeSemantics semantics() => tester.widget<ExcludeSemantics>(
        find
            .ancestor(
              of: find.byKey(_pill),
              matching: find.byType(ExcludeSemantics),
            )
            .first,
      );
      expect(touches().ignoring, isFalse);
      expect(semantics().excluding, isFalse);

      router.go('/one/detail');
      await tester.pumpAndSettle();
      expect(touches().ignoring, isTrue);
      expect(semantics().excluding, isTrue);
    });
  });

  group('centre notch', () {
    testWidgets('the glass has a 28.5 px circular cut-out at the top centre', (
      tester,
    ) async {
      final router = _buildShellRouter();
      addTearDown(router.dispose);
      await tester.pumpWidget(_shellApp(router));
      await tester.pumpAndSettle();
      final clip = tester.widget<ClipPath>(
        find.byKey(const Key('tab-bar-glass-clip')),
      );
      final path = clip.clipper!.getClip(const Size(350, 58));
      // Circle: centre 10 px above the pill, radius 28.5 -> bottoms out 18.5
      // px into the glass.
      expect(path.contains(const Offset(175, 1)), isFalse);
      expect(path.contains(const Offset(175, 17)), isFalse);
      expect(path.contains(const Offset(175, 20)), isTrue);
      // At 8 px down the circle is 22 px either side of the centre.
      expect(path.contains(const Offset(175 - 20, 8)), isFalse);
      expect(path.contains(const Offset(175 + 20, 8)), isFalse);
      expect(path.contains(const Offset(175 - 25, 8)), isTrue);
      expect(path.contains(const Offset(175 + 25, 8)), isTrue);
      expect(path.contains(const Offset(10, 29)), isTrue);
    });

    testWidgets('the avatar that fills the notch is tappable above the pill', (
      tester,
    ) async {
      final router = _buildShellRouter();
      addTearDown(router.dispose);
      await tester.pumpWidget(_shellApp(router));
      await tester.pumpAndSettle();
      final pill = tester.getRect(find.byKey(_pill));

      // Beside the avatar, above the pill: the page, not the Mentor tab.
      await tester.tapAt(Offset(pill.center.dx + 26, pill.top - 8));
      await tester.pumpAndSettle();
      expect(find.text('/one'), findsOneWidget);

      // On the part of the avatar that rises above the pill.
      await tester.tapAt(Offset(pill.center.dx, pill.top - 8));
      await tester.pumpAndSettle();
      expect(find.text('/three'), findsOneWidget);
    });
  });

  group('tap feedback', () {
    double scaleOf(WidgetTester tester, int tab) => tester
        .renderObject<RenderBox>(
          find
              .descendant(
                of: find.byKey(ValueKey('floating-nav-item-$tab')),
                matching: find.byType(V3Icon),
              )
              .first,
        )
        .getTransformTo(null)
        .getMaxScaleOnAxis();

    Finder ripples() => find.byWidgetPredicate(
      (widget) => widget.runtimeType.toString() == '_TbRipple',
    );

    Finder rings() => find.byWidgetPredicate(
      (widget) => widget.runtimeType.toString() == '_TbRing',
    );

    testWidgets('the tapped glyph pops and a ripple spreads from the touch', (
      tester,
    ) async {
      final router = _buildShellRouter();
      addTearDown(router.dispose);
      await tester.pumpWidget(_shellApp(router));
      await tester.pumpAndSettle();
      expect(ripples(), findsNothing);

      final plan = find.byKey(const ValueKey('floating-nav-item-1'));
      final touch = tester.getTopLeft(plan) + const Offset(10, 12);
      await tester.tapAt(touch);
      // One frame to route, one to start the pop's clock, then 100 ms in.
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 1));
      await tester.pump(const Duration(milliseconds: 1));
      await tester.pump(const Duration(milliseconds: 100));

      // `tbPop` swells the glyph past 1 on its way (peak 1.18 at 35%).
      final glyph = find.descendant(of: plan, matching: find.byType(V3Icon));
      final pop = tester
          .renderObject<RenderBox>(glyph.first)
          .getTransformTo(null)
          .getMaxScaleOnAxis();
      expect(pop, greaterThan(1.05));

      // The 120 pt disc is centred on the touch point, inside the cell.
      expect(ripples(), findsOneWidget);
      final disc = tester.getRect(ripples());
      expect(disc.size, const Size(120, 120));
      expect(disc.center.dx, closeTo(touch.dx, .5));
      expect(disc.center.dy, closeTo(touch.dy, .5));

      await tester.pumpAndSettle();
      expect(
        tester
            .renderObject<RenderBox>(glyph.first)
            .getTransformTo(null)
            .getMaxScaleOnAxis(),
        closeTo(1, 1e-6),
        reason: 'settles back to rest',
      );
    });

    testWidgets('tapping the current tab pops it again', (tester) async {
      final router = _buildShellRouter();
      addTearDown(router.dispose);
      await tester.pumpWidget(_shellApp(router));
      await tester.pumpAndSettle();
      final today = find.byKey(const ValueKey('floating-nav-item-0'));
      final glyph = find.descendant(of: today, matching: find.byType(V3Icon));
      double scale() => tester
          .renderObject<RenderBox>(glyph)
          .getTransformTo(null)
          .getMaxScaleOnAxis();
      expect(scale(), closeTo(1, 1e-6));
      await tester.tap(today);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 1));
      await tester.pump(const Duration(milliseconds: 100));
      expect(scale(), greaterThan(1.05));
    });

    testWidgets('the Mentor ring pulses on every tap of the centre tab', (
      tester,
    ) async {
      final router = _buildShellRouter();
      addTearDown(router.dispose);
      await tester.pumpWidget(_shellApp(router));
      await tester.pumpAndSettle();
      expect(rings(), findsNothing);

      await tester.tap(find.byKey(const ValueKey('floating-nav-item-2')));
      await tester.pump();
      expect(rings(), findsOneWidget);
      await tester.pumpAndSettle();
      final first = tester.widget(rings()).key;

      await tester.tap(find.byKey(const ValueKey('floating-nav-item-2')));
      await tester.pump();
      expect(tester.widget(rings()).key, isNot(first), reason: 'replays');
      await tester.pumpAndSettle();
    });

    testWidgets('are skipped under reduced motion', (tester) async {
      final router = _buildShellRouter();
      addTearDown(router.dispose);
      await tester.pumpWidget(_shellApp(router, disableAnimations: true));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('floating-nav-item-1')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(ripples(), findsNothing);
      expect(scaleOf(tester, 1), closeTo(1, 1e-6));
      await tester.tap(find.byKey(const ValueKey('floating-nav-item-2')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(rings(), findsNothing);
    });
  });

  test('every branch of the production router reports pushed pages', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final router = container.read(routerProvider);
    addTearDown(router.dispose);
    final shell = router.configuration.routes
        .whereType<StatefulShellRoute>()
        .single;
    expect(shell.branches, hasLength(5));
    for (final branch in shell.branches) {
      expect(branch.observers?.whereType<ShellPushObserver>(), hasLength(1));
    }
  });
}
