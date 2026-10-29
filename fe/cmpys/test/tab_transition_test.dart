import 'package:cmpys/core/ui/app_shell.dart';
import 'package:cmpys/features/cmpys/data/cmpys_seed.dart';
import 'package:cmpys/features/cmpys/data/record_restore.dart';
import 'package:cmpys/features/cmpys/state/cmpys_backend_sync.dart';
import 'package:cmpys/features/cmpys/state/cmpys_store.dart';
import 'package:cmpys/features/plan/state/current_plan_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

// SPEC §5: the incoming tab slides in from 46 px on the side it lies in the
// tab order (Today, Plan, Mentor, Compare, You) and fades in, `.5s
// var(--out)`; the first show rises (`tabIn`). Reduced motion: a fade.

const _paths = ['/today', '/plan', '/mentor', '/compare', '/you'];

class _Store extends CmpysStore {
  _Store() {
    state = state.copyWith(idol: cmpysPlaceholderIdol);
  }
}

GoRouter _router() => GoRouter(
  initialLocation: _paths.first,
  routes: [
    StatefulShellRoute.indexedStack(
      builder: (_, _, shell) => AppShell(navigationShell: shell),
      branches: [
        for (final path in _paths)
          StatefulShellBranch(
            observers: [ShellPushObserver()],
            routes: [
              GoRoute(
                path: path,
                builder: (_, _) =>
                    ColoredBox(color: Colors.white, child: Text(path)),
              ),
            ],
          ),
      ],
    ),
  ],
);

Future<GoRouter> _mount(WidgetTester tester, {bool reduced = false}) async {
  SharedPreferences.setMockInitialValues({});
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final router = _router();
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        cmpysBackendSyncProvider.overrideWith((ref) async {}),
        cmpysRecordRestoreProvider.overrideWith((ref) async {}),
        todayViewProvider.overrideWith((ref) async => null),
        cmpysStoreProvider.overrideWith((ref) => _Store()),
      ],
      child: MaterialApp.router(
        routerConfig: router,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(disableAnimations: reduced),
          child: child!,
        ),
      ),
    ),
  );
  return router;
}

Matrix4 _transform(WidgetTester tester) =>
    tester.widget<Transform>(find.byKey(AppShell.tabTransitionKey)).transform;

double _opacity(WidgetTester tester) => tester
    .widget<Opacity>(
      find
          .ancestor(
            of: find.byKey(AppShell.tabTransitionKey),
            matching: find.byType(Opacity),
          )
          .first,
    )
    .opacity;

StatefulNavigationShell _shell(WidgetTester tester) =>
    tester.widget<AppShell>(find.byType(AppShell)).navigationShell;

Future<void> _goTo(WidgetTester tester, String label) async {
  await tester.tap(find.text(label).last);
  await tester.pump();
}

void main() {
  testWidgets('the first show rises 10 px from 99% and fades in', (
    tester,
  ) async {
    await _mount(tester);
    await tester.pump();
    final start = _transform(tester);
    expect(start.getTranslation().y, closeTo(10, .5));
    expect(start.getTranslation().x, 0);
    expect(start.entry(0, 0), closeTo(.99, .001));
    expect(_opacity(tester), lessThan(.1));

    await tester.pump(const Duration(milliseconds: 520));
    expect(_transform(tester), Matrix4.identity());
    expect(_opacity(tester), 1);
  });

  testWidgets('a tab to the right enters from +46 px, one to the left from '
      '−46 px, over .5 s', (tester) async {
    await _mount(tester);
    await tester.pump(const Duration(milliseconds: 600));

    // Today → Compare: further right.
    await _goTo(tester, 'Compare');
    expect(_shell(tester).currentIndex, 3);
    expect(find.text('/compare'), findsOneWidget);
    expect(_transform(tester).getTranslation().x, closeTo(46, 1));
    expect(_transform(tester).getTranslation().y, 0);
    expect(_opacity(tester), lessThan(.1));
    await tester.pump(const Duration(milliseconds: 250));
    final mid = _transform(tester).getTranslation().x;
    expect(mid, inExclusiveRange(0, 46));
    await tester.pump(const Duration(milliseconds: 300));
    expect(_transform(tester), Matrix4.identity());
    expect(_opacity(tester), 1);

    // Compare → Plan: further left.
    await _goTo(tester, 'Plan');
    expect(_shell(tester).currentIndex, 1);
    expect(_transform(tester).getTranslation().x, closeTo(-46, 1));
    await tester.pump(const Duration(milliseconds: 600));
    expect(_transform(tester), Matrix4.identity());

    // Plan → You: right again.
    await _goTo(tester, 'You');
    expect(_shell(tester).currentIndex, 4);
    expect(_transform(tester).getTranslation().x, closeTo(46, 1));
    await tester.pump(const Duration(milliseconds: 600));

    // You → Today: left.
    await _goTo(tester, 'Today');
    expect(_shell(tester).currentIndex, 0);
    expect(_transform(tester).getTranslation().x, closeTo(-46, 1));
    await tester.pump(const Duration(milliseconds: 600));
    expect(_transform(tester), Matrix4.identity());
  });

  testWidgets('the branches keep their state through the transition', (
    tester,
  ) async {
    await _mount(tester);
    await tester.pump(const Duration(milliseconds: 600));
    final today = tester.element(find.text('/today', skipOffstage: false));
    await _goTo(tester, 'Plan');
    await tester.pump(const Duration(milliseconds: 600));
    await _goTo(tester, 'Today');
    await tester.pump(const Duration(milliseconds: 600));
    expect(tester.element(find.text('/today')), same(today));
  });

  testWidgets('reduced motion: a short fade, no movement', (tester) async {
    await _mount(tester, reduced: true);
    await tester.pump();
    expect(_transform(tester), Matrix4.identity());
    await tester.pump(const Duration(milliseconds: 220));
    expect(_opacity(tester), 1);

    await _goTo(tester, 'Compare');
    expect(_transform(tester), Matrix4.identity());
    expect(_opacity(tester), lessThan(.1));
    await tester.pump(const Duration(milliseconds: 100));
    expect(_transform(tester), Matrix4.identity());
    expect(_opacity(tester), inExclusiveRange(0, 1));
    await tester.pump(const Duration(milliseconds: 120));
    expect(_opacity(tester), 1);
  });
}
