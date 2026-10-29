import 'dart:async';

import 'package:cmpys/core/network/dio_client.dart';
import 'package:cmpys/core/storage/token_store.dart';
import 'package:cmpys/core/ui/app_shell.dart';
import 'package:cmpys/core/ui/narration_dock_page.dart';
import 'package:cmpys/features/cmpys/state/cmpys_backend_sync.dart';
import 'package:cmpys/core/ui/v3/tab_bar.dart';
import 'package:cmpys/features/plan/presentation/book_narration.dart';
import 'package:cmpys/features/plan/presentation/book_narration_dock.dart';
import 'package:cmpys/features/plan/presentation/book_reader_screen.dart';
import 'package:cmpys/features/plan/state/book_narration_remote_controller.dart';
import 'package:cmpys/features/plan/state/current_plan_provider.dart';
import 'package:cmpys/features/session/data/content_resources_repository.dart';
import 'package:cmpys/features/session/models/content_resource.dart';
import 'package:cmpys/core/ui/v3/v3.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// A book for the real reader: one chapter, two sentences.
class _Books extends ContentResourcesRepository {
  _Books() : super(dioClient: DioClient(tokenStore: TokenStore()));

  @override
  Future<ContentResource> getResource(String resourceId) async =>
      const ContentResource(
        id: 'book-1',
        kind: 'llm_book_summary',
        canonicalKey: 'book:one',
        title: 'Decision Systems',
        authorOrCreator: 'A. Author',
        licenseStatus: 'llm_summary',
        isSaved: false,
        progressPercent: 0,
        contentMarkdown:
            '## One\n\nA first sentence to narrate. A second one follows.\n',
      );

  @override
  Future<List<ContentHighlight>> listHighlights(String resourceId) async =>
      const [];

  @override
  Future<ContentResource> updateProgress(
    String resourceId, {
    required int progressPercent,
    Map<String, dynamic>? cursorJson,
    bool? completed,
  }) => getResource(resourceId);
}

/// Speaks until stopped, and counts stops.
class _Narrator implements BookNarrator {
  final List<String> spoken = [];
  int stops = 0;
  Completer<void>? _speech;

  @override
  void setProgressHandler(BookNarrationProgressHandler? handler) {}

  @override
  void setErrorHandler(BookNarrationErrorHandler? handler) {}

  @override
  Future<void> initialize({required double speed}) async {}

  @override
  Future<void> setSpeed(double speed) async {}

  @override
  Future<void> speak(String text) {
    spoken.add(text);
    return (_speech = Completer<void>()).future;
  }

  @override
  Future<void> stop() async {
    stops++;
    if (_speech case final speech? when !speech.isCompleted) speech.complete();
  }

  @override
  Future<void> dispose() async {
    if (_speech case final speech? when !speech.isCompleted) speech.complete();
  }
}

/// The mission route's page: a mission (which carries the dock) until it
/// turns out to be a habit (which does not).
final ValueNotifier<bool> _missionIsHabit = ValueNotifier<bool>(false);

GoRouter _router({bool scrollable = false, Widget Function()? book}) =>
    GoRouter(
  routes: [
    StatefulShellRoute.indexedStack(
      builder: (_, _, shell) => AppShell(navigationShell: shell),
      branches: [
        for (var i = 0; i < 5; i++)
          StatefulShellBranch(
            observers: [ShellPushObserver()],
            routes: [
              GoRoute(
                path: i == 0 ? '/' : '/tab$i',
                builder: (context, _) => SingleChildScrollView(
                  key: ValueKey('scroll-tab-$i'),
                  physics: scrollable
                      ? null
                      : const NeverScrollableScrollPhysics(),
                  child: Column(
                    children: [
                      Text('Screen $i'),
                      if (scrollable) const SizedBox(height: 2400),
                      SizedBox(
                        key: const Key('content-clearance'),
                        height: AppShell.bottomNavClearance(context),
                      ),
                    ],
                  ),
                ),
                routes: [
                  // Stands in for the book, library, mission and record
                  // pages, which carry the dock.
                  GoRoute(
                    path: 'reader',
                    builder: (_, _) =>
                        const NarrationDockPage(child: Text('Open reader')),
                  ),
                  // Lessons, practice, web and video pages do not.
                  GoRoute(
                    path: 'lesson',
                    builder: (_, _) => const Text('Open lesson'),
                  ),
                  GoRoute(
                    path: 'mission',
                    builder: (_, _) => ValueListenableBuilder<bool>(
                      valueListenable: _missionIsHabit,
                      builder: (_, habit, _) => habit
                          ? const Text('Habit page')
                          : const NarrationDockPage(
                              child: Text('Mission page'),
                            ),
                    ),
                  ),
                  GoRoute(
                    path: 'book',
                    builder: (_, _) => book?.call() ?? const SizedBox(),
                  ),
                ],
              ),
            ],
          ),
      ],
    ),
  ],
);

Future<void> _mount(
  WidgetTester tester,
  GoRouter router,
  BookNarrationRemoteController remote, {
  double textScale = 1,
  bool accessibleNavigation = false,
  List<Override> overrides = const [],
}) async {
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        cmpysBackendSyncProvider.overrideWith((ref) async {}),
        // The shell's Today badge reads this; keep the plan off the network.
        todayViewProvider.overrideWith((ref) async => null),
        bookNarrationRemoteControllerProvider.overrideWith((ref) => remote),
        ...overrides,
      ],
      child: MaterialApp.router(
        routerConfig: router,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(
            padding: const EdgeInsets.only(bottom: 34),
            textScaler: TextScaler.linear(textScale),
            accessibleNavigation: accessibleNavigation,
            // The dock's waves loop while playing; settle-based tests run
            // with reduced motion.
            disableAnimations: true,
          ),
          child: child!,
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void _listen(
  BookNarrationRemoteController remote,
  Object owner, {
  bool playing = true,
  bool preparing = false,
}) => remote.attach(
  ownerToken: owner,
  onToggle: () async =>
      remote.update(ownerToken: owner, playing: !remote.playing),
  onPrevious: () async {},
  onNext: () async {},
  onSeek: (_) async {},
  onStyleChanged: (_) async {},
  onSpeedChanged: (_) async {},
  onStop: () async {},
  playing: playing,
  preparing: preparing,
  progress: .35,
  resourceId: 'essays',
  title: 'The Essays of Warren Buffett',
  author: 'Warren Buffett',
  chapterIndex: 0,
  duration: const Duration(minutes: 10),
);

void main() {
  Rect dockRect(WidgetTester tester) =>
      tester.getRect(find.byKey(BookNarrationDock.dockKey));

  testWidgets('the dock sits above the visible tab bar and drops to the '
      'bottom when the tabs hide', (tester) async {
    final router = _router();
    addTearDown(router.dispose);
    final remote = BookNarrationRemoteController();
    await _mount(tester, router, remote);
    _listen(remote, Object());
    await tester.pumpAndSettle();

    // Both are visible: the tab bar keeps its place under the dock.
    expect(find.text('Today').hitTestable(), findsOneWidget);
    final bar = tester.getRect(find.byKey(const Key('v3-tab-bar')));
    final lifted = dockRect(tester);
    // Design: dock bottom 90 over a bar at bottom 20 (same baseline: the
    // bar's bottom offset for this device).
    final baseline = V3TabBar.bottomOffsetFor(34);
    expect(844 - lifted.bottom, baseline + 70);
    expect(lifted.bottom, lessThan(bar.bottom - V3TabBar.height));
    expect(lifted.height, BookNarrationDock.preferredHeight);
    expect(lifted.left, 12);
    expect(lifted.right, 390 - 12);
    expect(
      tester.getSize(find.byKey(const Key('content-clearance'))).height,
      baseline + 70 + BookNarrationDock.preferredHeight + 22,
    );

    // A pushed page hides the tab bar; the dock drops to bottom 30.
    router.go('/reader');
    await tester.pumpAndSettle();
    expect(find.text('Open reader'), findsOneWidget);
    expect(find.text('Today').hitTestable(), findsNothing);
    final dropped = dockRect(tester);
    expect(844 - dropped.bottom, baseline + 10);
    expect(remote.playing, isTrue);

    // Back on the tab: lifted again.
    router.go('/');
    await tester.pumpAndSettle();
    expect(844 - dockRect(tester).bottom, baseline + 70);
    expect(find.text('Today').hitTestable(), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('tapping the dock opens the full player over the tab bar', (
    tester,
  ) async {
    final router = _router();
    addTearDown(router.dispose);
    final remote = BookNarrationRemoteController();
    await _mount(tester, router, remote);
    _listen(remote, Object());
    await tester.pumpAndSettle();
    final dock = dockRect(tester);
    await tester.tapAt(Offset(dock.left + 30, dock.center.dy));
    await tester.pumpAndSettle();
    expect(find.text('Now listening'), findsOneWidget);
    expect(find.text('Today').hitTestable(), findsNothing);
    await tester.tap(find.bySemanticsLabel('Back'));
    await tester.pumpAndSettle();
    expect(find.text('Now listening'), findsNothing);
    expect(find.text('Today').hitTestable(), findsOneWidget);
    expect(remote.playing, isTrue);
  });

  testWidgets('scrolling compacts the tab bar and keeps the dock in place', (
    tester,
  ) async {
    final router = _router(scrollable: true);
    addTearDown(router.dispose);
    final remote = BookNarrationRemoteController();
    await _mount(tester, router, remote);
    final scroll = find.byKey(const ValueKey('scroll-tab-0'));
    double barHeight() =>
        tester.getSize(find.byKey(const Key('v3-tab-bar'))).height;

    // The v3 tab bar never hides for scrolling: it goes compact (50 pt, no
    // labels) and stays reachable.
    expect(barHeight(), 58);
    await tester.drag(scroll, const Offset(0, -250));
    await tester.pumpAndSettle();
    expect(barHeight(), 50);
    expect(
      find.byKey(const ValueKey('floating-nav-item-0')).hitTestable(),
      findsOneWidget,
    );
    await tester.drag(scroll, const Offset(0, 120));
    await tester.pumpAndSettle();
    expect(barHeight(), 58);
    expect(find.text('Today').hitTestable(), findsOneWidget);

    _listen(remote, Object());
    await tester.pumpAndSettle();
    final before = dockRect(tester);
    await tester.drag(scroll, const Offset(0, -180));
    await tester.pumpAndSettle();
    expect(dockRect(tester), before);
    expect(
      find.byKey(const Key('book-narration-play-pause')).hitTestable(),
      findsOneWidget,
    );
    expect(remote.playing, isTrue);
    expect(tester.takeException(), isNull);
  });

  testWidgets('accessible navigation remains visible during scrolling', (
    tester,
  ) async {
    final router = _router(scrollable: true);
    addTearDown(router.dispose);
    await _mount(
      tester,
      router,
      BookNarrationRemoteController(),
      accessibleNavigation: true,
    );
    await tester.drag(
      find.byKey(const ValueKey('scroll-tab-0')),
      const Offset(0, -250),
    );
    await tester.pumpAndSettle();
    expect(find.text('Today').hitTestable(), findsOneWidget);
  });

  testWidgets('the dock follows listening, pause and preparation', (
    tester,
  ) async {
    final router = _router();
    addTearDown(router.dispose);
    final remote = BookNarrationRemoteController();
    final owner = Object();
    await _mount(tester, router, remote);
    expect(find.byKey(BookNarrationDock.dockKey), findsNothing);
    _listen(remote, owner);
    await tester.pumpAndSettle();
    expect(find.byKey(BookNarrationDock.dockKey), findsOneWidget);
    expect(find.text('Today'), findsOneWidget);

    await tester.tap(find.byKey(const Key('book-narration-play-pause')));
    await tester.pumpAndSettle();
    expect(remote.playing, isFalse);
    expect(find.bySemanticsLabel('Play'), findsOneWidget);
    remote.update(ownerToken: owner, preparing: true);
    await tester.pump();
    expect(find.byType(V3Spinner), findsOneWidget);
    remote.update(ownerToken: owner, preparing: false);
    await tester.pumpAndSettle();

    remote.release(owner);
    await tester.pumpAndSettle();
    expect(find.byKey(BookNarrationDock.dockKey), findsNothing);
    expect(find.text('Today'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('the dock stays off the Mentor tab', (tester) async {
    final router = _router();
    addTearDown(router.dispose);
    final remote = BookNarrationRemoteController();
    await _mount(tester, router, remote);
    _listen(remote, Object());
    await tester.pumpAndSettle();
    router.go('/tab2');
    await tester.pumpAndSettle();
    expect(find.text('Screen 2'), findsOneWidget);
    expect(find.byKey(BookNarrationDock.dockKey), findsNothing);
    expect(
      tester.getSize(find.byKey(const Key('content-clearance'))).height,
      V3TabBar.clearanceFor(34),
    );
    router.go('/tab1');
    await tester.pumpAndSettle();
    expect(find.byKey(BookNarrationDock.dockKey), findsOneWidget);
    expect(remote.playing, isTrue);
  });

  testWidgets('the dock fits narrow screens and large text, and hides for '
      'the keyboard', (tester) async {
    final router = _router();
    addTearDown(router.dispose);
    addTearDown(tester.view.resetViewInsets);
    final remote = BookNarrationRemoteController();
    await _mount(tester, router, remote, textScale: 2);
    tester.view.physicalSize = const Size(320, 568);
    await tester.pumpAndSettle();
    _listen(remote, Object());
    await tester.pumpAndSettle();
    final play = tester.getSize(
      find.byKey(const Key('book-narration-play-pause')),
    );
    expect(play.width, greaterThanOrEqualTo(44));
    expect(play.height, greaterThanOrEqualTo(44));
    // Large text makes the pill taller; the clearance under it follows, so
    // the last row is never hidden behind it.
    final dock = dockRect(tester);
    expect(dock.height, greaterThan(BookNarrationDock.preferredHeight + 6));
    expect(
      tester.getSize(find.byKey(const Key('content-clearance'))).height,
      closeTo(568 - dock.top + 22, .01),
    );
    tester.view.viewInsets = const FakeViewPadding(bottom: 300);
    await tester.pumpAndSettle();
    expect(find.byKey(BookNarrationDock.dockKey), findsNothing);
    expect(find.text('Today'), findsNothing);
    tester.view.resetViewInsets();
    await tester.pumpAndSettle();
    expect(find.byKey(BookNarrationDock.dockKey), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('the dock shows over the book, library, mission and record '
      'pages only', (tester) async {
    final router = _router();
    addTearDown(router.dispose);
    final remote = BookNarrationRemoteController();
    await _mount(tester, router, remote);
    _listen(remote, Object());
    await tester.pumpAndSettle();
    router.go('/lesson');
    await tester.pumpAndSettle();
    expect(find.text('Open lesson'), findsOneWidget);
    expect(find.byKey(BookNarrationDock.dockKey), findsNothing);
    router.go('/reader');
    await tester.pumpAndSettle();
    expect(find.text('Open reader'), findsOneWidget);
    expect(find.byKey(BookNarrationDock.dockKey), findsOneWidget);
    router.go('/');
    await tester.pumpAndSettle();
    expect(find.byKey(BookNarrationDock.dockKey), findsOneWidget);
    expect(remote.playing, isTrue);
  });

  testWidgets('the dock leaves a page that drops its dock mark', (
    tester,
  ) async {
    _missionIsHabit.value = false;
    addTearDown(() => _missionIsHabit.value = false);
    final router = _router();
    addTearDown(router.dispose);
    final remote = BookNarrationRemoteController();
    await _mount(tester, router, remote);
    _listen(remote, Object());
    await tester.pumpAndSettle();
    router.go('/mission');
    await tester.pumpAndSettle();
    expect(find.text('Mission page'), findsOneWidget);
    expect(find.byKey(BookNarrationDock.dockKey), findsOneWidget);
    _missionIsHabit.value = true;
    await tester.pumpAndSettle();
    expect(find.text('Habit page'), findsOneWidget);
    expect(find.byKey(BookNarrationDock.dockKey), findsNothing);
    expect(remote.playing, isTrue);
  });

  testWidgets('app menu switches tabs without stopping or resetting the '
      'reader', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final narrator = _Narrator();
    final router = _router(
      book: () => BookReaderScreen(
        resourceId: 'book-1',
        fallbackTitle: 'Decision Systems',
        narrator: narrator,
      ),
    );
    addTearDown(router.dispose);
    final remote = BookNarrationRemoteController();
    await _mount(
      tester,
      router,
      remote,
      overrides: [contentResourcesRepositoryProvider.overrideWithValue(_Books())],
    );
    final baseline = V3TabBar.bottomOffsetFor(34);
    router.go('/book');
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('book-listen-button')));
    await tester.pumpAndSettle();
    expect(narrator.spoken, ['A first sentence to narrate.']);
    expect(remote.playing, isTrue);
    // A pushed reader: no tab bar, and the dock at the bottom.
    expect(find.text('Today').hitTestable(), findsNothing);
    expect(844 - dockRect(tester).bottom, baseline + 10);

    // The reader's menu → App menu → Plan.
    await tester.tap(find.bySemanticsLabel('Book menu'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('App menu'));
    await tester.pumpAndSettle();
    for (final tab in appShellDestinations) {
      expect(find.text(tab.label), findsWidgets);
    }
    await tester.tap(find.byKey(const ValueKey('listening-nav-item-1')));
    await tester.pumpAndSettle();
    expect(find.text('Screen 1'), findsOneWidget);
    expect(narrator.stops, 0);
    expect(remote.playing, isTrue);
    // On another tab's root, the dock sits above the visible tab bar.
    expect(find.text('Today').hitTestable(), findsOneWidget);
    expect(844 - dockRect(tester).bottom, baseline + 70);

    // The Mentor root has no dock; narration carries on.
    router.go('/tab2');
    await tester.pumpAndSettle();
    expect(find.text('Screen 2'), findsOneWidget);
    expect(find.byKey(BookNarrationDock.dockKey), findsNothing);
    expect(remote.playing, isTrue);

    // Today's tab brings back the same reader, still narrating.
    await tester.tap(find.byKey(const ValueKey('floating-nav-item-0')));
    await tester.pumpAndSettle();
    expect(find.byType(BookReaderScreen), findsOneWidget);
    expect(narrator.spoken, hasLength(1));
    expect(narrator.stops, 0);

    // The full player's More reaches the same menu.
    final dock = dockRect(tester);
    await tester.tapAt(Offset(dock.left + 30, dock.center.dy));
    await tester.pumpAndSettle();
    await tester.tap(find.bySemanticsLabel('More'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('book-narration-app-menu')));
    await tester.pumpAndSettle();
    expect(find.byType(BookNarrationFullPlayer), findsNothing);
    await tester.tap(find.byKey(const ValueKey('listening-nav-item-3')));
    await tester.pumpAndSettle();
    expect(find.text('Screen 3'), findsOneWidget);
    expect(narrator.stops, 0);
    expect(remote.playing, isTrue);
    expect(844 - dockRect(tester).bottom, baseline + 70);
    expect(tester.takeException(), isNull);
  });
}
