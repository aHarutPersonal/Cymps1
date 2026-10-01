import 'package:cmpys/core/ui/app_shell.dart';
import 'package:cmpys/features/cmpys/state/cmpys_backend_sync.dart';
import 'package:cmpys/features/plan/presentation/book_narration.dart';
import 'package:cmpys/features/plan/state/book_narration_remote_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

GoRouter _router({bool scrollable = false}) => GoRouter(
  routes: [
    StatefulShellRoute.indexedStack(
      builder: (_, _, shell) => AppShell(navigationShell: shell),
      branches: [
        for (var i = 0; i < 5; i++)
          StatefulShellBranch(
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
                  GoRoute(
                    path: 'reader',
                    builder: (_, _) => const Text('Open reader'),
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
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        cmpysBackendSyncProvider.overrideWith((ref) async {}),
        bookNarrationRemoteControllerProvider.overrideWith((ref) => remote),
      ],
      child: MaterialApp.router(
        routerConfig: router,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(
            padding: const EdgeInsets.only(bottom: 34),
            textScaler: TextScaler.linear(textScale),
            accessibleNavigation: accessibleNavigation,
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
);

void main() {
  testWidgets('scroll hides dock; reverse scroll, swipe and tap restore it', (
    tester,
  ) async {
    final router = _router(scrollable: true);
    addTearDown(router.dispose);
    final remote = BookNarrationRemoteController();
    await _mount(tester, router, remote);
    final scroll = find.byKey(const ValueKey('scroll-tab-0'));
    await tester.drag(scroll, const Offset(0, -250));
    await tester.pumpAndSettle();
    expect(find.text('Today').hitTestable(), findsNothing);
    expect(
      find.byTooltip('Show bottom controls').hitTestable(),
      findsOneWidget,
    );
    await tester.drag(scroll, const Offset(0, 120));
    await tester.pumpAndSettle();
    expect(find.text('Today').hitTestable(), findsOneWidget);
    await tester.drag(scroll, const Offset(0, -180));
    await tester.pumpAndSettle();
    await tester.drag(
      find.byKey(const Key('reveal-bottom-menu')),
      const Offset(0, -60),
    );
    await tester.pumpAndSettle();
    expect(find.text('Today').hitTestable(), findsOneWidget);

    _listen(remote, Object());
    await tester.pumpAndSettle();
    await tester.drag(scroll, const Offset(0, -180));
    await tester.pumpAndSettle();
    expect(find.byTooltip('Pause narration').hitTestable(), findsNothing);
    expect(remote.playing, isTrue);
    await tester.tap(find.byTooltip('Show bottom controls'));
    await tester.pumpAndSettle();
    expect(find.byTooltip('Pause narration').hitTestable(), findsOneWidget);
    expect(remote.playing, isTrue);
    final position = tester
        .state<ScrollableState>(
          find.descendant(of: scroll, matching: find.byType(Scrollable)).first,
        )
        .position;
    position.jumpTo(position.pixels + 200);
    await tester.pumpAndSettle();
    expect(find.byTooltip('Pause narration').hitTestable(), findsOneWidget);
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
    expect(find.byTooltip('Show bottom controls'), findsNothing);
  });

  testWidgets('one bottom bar during listening, pause, and preparation', (
    tester,
  ) async {
    final router = _router();
    addTearDown(router.dispose);
    final remote = BookNarrationRemoteController();
    final owner = Object();
    await _mount(tester, router, remote);
    final oldClearance = tester
        .getSize(find.byKey(const Key('content-clearance')))
        .height;
    expect(find.text('Today'), findsOneWidget);
    _listen(remote, owner);
    await tester.pumpAndSettle();
    expect(find.text('Today'), findsNothing);
    expect(find.byKey(const Key('book-narration-player')), findsOneWidget);
    final clearance = tester
        .getSize(find.byKey(const Key('content-clearance')))
        .height;
    expect(clearance, 72 + 40 + 22);
    expect((clearance - oldClearance).abs(), lessThan(20));

    await tester.tap(find.byTooltip('Pause narration'));
    await tester.pumpAndSettle();
    expect(find.byTooltip('Play narration'), findsOneWidget);
    expect(find.text('Today'), findsNothing);
    remote.update(ownerToken: owner, preparing: true);
    await tester.pump();
    expect(find.byTooltip('Cancel narration loading'), findsOneWidget);
    expect(find.byTooltip('Open app menu'), findsOneWidget);
    expect(find.text('Today'), findsNothing);
    remote.update(ownerToken: owner, preparing: false);
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Narration options'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Warm'));
    await tester.pumpAndSettle();
    expect(remote.style, BookNarrationStyle.warm);
    await tester.tap(find.byTooltip('Narration options'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Stop listening'));
    await tester.pumpAndSettle();
    expect(find.text('Today'), findsOneWidget);
    expect(find.byKey(const Key('book-narration-player')), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'app menu switches tabs without stopping or resetting the reader',
    (tester) async {
      final router = _router();
      addTearDown(router.dispose);
      final remote = BookNarrationRemoteController();
      await _mount(tester, router, remote);
      router.go('/reader');
      await tester.pumpAndSettle();
      _listen(remote, Object());
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Open app menu'));
      await tester.pumpAndSettle();
      for (final tab in appShellDestinations) {
        expect(find.text(tab.label), findsOneWidget);
      }
      await tester.tap(find.byKey(const ValueKey('listening-nav-item-0')));
      await tester.pumpAndSettle();
      expect(find.text('Open reader'), findsOneWidget);
      expect(remote.playing, isTrue);

      await tester.tap(find.byTooltip('Open app menu'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('listening-nav-item-1')));
      await tester.pumpAndSettle();
      expect(find.text('Screen 1'), findsOneWidget);
      expect(remote.playing, isTrue);
      expect(find.text('App menu'), findsNothing);

      await tester.tap(find.byTooltip('Open app menu'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('listening-nav-item-0')));
      await tester.pumpAndSettle();
      expect(find.text('Open reader'), findsOneWidget);
      await tester.tap(find.byTooltip('Open app menu'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Close app menu'));
      await tester.pumpAndSettle();
      expect(find.text('Open reader'), findsOneWidget);
      expect(remote.playing, isTrue);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'listening menu fits narrow screens and large text, and hides for keyboard',
    (tester) async {
      tester.view.physicalSize = const Size(320, 568);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetViewInsets);
      final router = _router();
      addTearDown(router.dispose);
      final remote = BookNarrationRemoteController();
      await _mount(tester, router, remote, textScale: 2);
      _listen(remote, Object());
      await tester.pumpAndSettle();
      final menuSize = tester.getSize(
        find.byKey(const Key('book-narration-app-menu')),
      );
      expect(menuSize.width, greaterThanOrEqualTo(44));
      expect(menuSize.height, greaterThanOrEqualTo(44));
      await tester.tap(find.byTooltip('Open app menu'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('You'));
      await tester.tap(find.text('You'));
      await tester.pumpAndSettle();
      expect(find.text('Screen 4'), findsOneWidget);
      tester.view.viewInsets = const FakeViewPadding(bottom: 300);
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('book-narration-player')), findsNothing);
      expect(find.text('Today'), findsNothing);
      tester.view.resetViewInsets();
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('book-narration-player')), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}
