import 'package:cmpys/core/ui/app_shell.dart';
import 'package:cmpys/features/cmpys/state/cmpys_backend_sync.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

const _shellPaths = ['/one', '/two', '/three', '/four', '/five'];

GoRouter _buildShellRouter() => GoRouter(
  initialLocation: _shellPaths.first,
  routes: [
    StatefulShellRoute.indexedStack(
      builder: (_, _, navigationShell) =>
          AppShell(navigationShell: navigationShell),
      branches: [
        for (final path in _shellPaths)
          StatefulShellBranch(
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

Widget _shellApp(GoRouter router, {bool disableAnimations = false}) {
  return ProviderScope(
    overrides: [cmpysBackendSyncProvider.overrideWith((ref) async {})],
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

void main() {
  test('app shell uses the canonical five-tab IA', () {
    expect(
      appShellDestinations.map((destination) => destination.label).toList(),
      ['Today', 'Plan', 'Chat', 'Compare', 'You'],
    );
  });

  test('floating navigation collapses before it can overflow', () {
    expect(AppShell.useIconOnlyNavigation(320, 14), isTrue);
    expect(AppShell.useIconOnlyNavigation(390, 18.2), isTrue);
    expect(AppShell.useIconOnlyNavigation(390, 14), isFalse);
  });

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
    final startX = tester.getTopLeft(selector).dx;

    await tester.tap(planTab);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    final midX = tester.getTopLeft(selector).dx;

    await tester.pumpAndSettle();
    final endX = tester.getTopLeft(selector).dx;

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
}
