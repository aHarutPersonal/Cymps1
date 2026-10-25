import 'package:flutter/services.dart';
import 'package:cmpys/core/ui/motion/page_transition.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

Future<void> mount(
  WidgetTester tester, {
  bool reduced = false,
  bool rtl = false,
  bool canPop = true,
  bool sheet = false,
  TargetPlatform platform = TargetPlatform.iOS,
  Widget? detail,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: ThemeData(platform: platform),
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(disableAnimations: reduced),
        child: Directionality(
          textDirection: rtl ? TextDirection.rtl : TextDirection.ltr,
          child: child!,
        ),
      ),
      home: Scaffold(
        body: Builder(
          builder: (context) => TextButton(
            onPressed: () {
              Widget screen(BuildContext context) => PopScope(
                canPop: canPop,
                child: Scaffold(
                  body: detail ?? const Center(child: Text('Detail')),
                ),
              );
              Navigator.of(context).push(
                sheet
                    ? CmpysSheetRoute<void>(builder: screen)
                    : CmpysPageRoute<void>(builder: screen),
              );
            },
            child: const Text('Open'),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('Open'));
  await tester.pumpAndSettle();
}

void main() {
  for (final reduced in [false, true]) {
    for (final rtl in [false, true]) {
      testWidgets('edge swipe returns, reduced=$reduced rtl=$rtl', (
        tester,
      ) async {
        await mount(tester, reduced: reduced, rtl: rtl);
        final size = tester.view.physicalSize / tester.view.devicePixelRatio;
        await tester.dragFrom(
          Offset(rtl ? size.width - 1 : 1, 200),
          Offset((rtl ? -1 : 1) * size.width * .8, 0),
        );
        await tester.pumpAndSettle();
        expect(find.text('Detail'), findsNothing);
        expect(find.text('Open'), findsOneWidget);
        expect(tester.takeException(), isNull);
      });
    }
  }

  testWidgets('cancelled edge swipe retains the route', (tester) async {
    await mount(tester);
    final gesture = await tester.startGesture(const Offset(1, 200));
    await gesture.moveBy(const Offset(100, 0));
    await tester.pump(const Duration(milliseconds: 400));
    await gesture.up();
    await tester.pumpAndSettle();
    expect(find.text('Detail'), findsOneWidget);
    expect(
      tester.state<NavigatorState>(find.byType(Navigator)).canPop(),
      isTrue,
    );
  });

  testWidgets('dirty PopScope is never bypassed by a swipe', (tester) async {
    await mount(tester, canPop: false);
    await tester.dragFrom(const Offset(1, 200), const Offset(700, 0));
    await tester.pumpAndSettle();
    expect(find.text('Detail'), findsOneWidget);
  });

  testWidgets('interior page swipe changes chapter without leaving', (
    tester,
  ) async {
    await mount(
      tester,
      detail: PageView(
        children: const [
          Center(child: Text('Chapter one')),
          Center(child: Text('Chapter two')),
        ],
      ),
    );
    await tester.drag(find.byType(PageView), const Offset(-650, 0));
    await tester.pumpAndSettle();
    expect(find.text('Chapter two'), findsOneWidget);
    expect(find.text('Open'), findsNothing);
  });

  testWidgets('record entry route also supports native back', (tester) async {
    await mount(tester, sheet: true);
    await tester.dragFrom(const Offset(1, 200), const Offset(700, 0));
    await tester.pumpAndSettle();
    expect(find.text('Open'), findsOneWidget);
  });

  testWidgets('Android system back pops the detail', (tester) async {
    await mount(tester, platform: TargetPlatform.android);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.text('Open'), findsOneWidget);
  });

  testWidgets('declarative pages retain native back and updated child data', (
    tester,
  ) async {
    final router = GoRouter(
      routes: [
        GoRoute(
          path: '/',
          pageBuilder: (_, state) => CmpysPageTransition.page(
            key: state.pageKey,
            child: const Scaffold(body: Text('Home')),
          ),
          routes: [
            GoRoute(
              path: 'detail',
              pageBuilder: (_, state) => CmpysPageTransition.page(
                key: state.pageKey,
                child: Scaffold(
                  body: Center(
                    child: Text(state.uri.queryParameters['title'] ?? 'First'),
                  ),
                ),
              ),
            ),
          ],
        ),
      ],
    );
    addTearDown(router.dispose);
    await tester.pumpWidget(
      MaterialApp.router(
        theme: ThemeData(platform: TargetPlatform.iOS),
        routerConfig: router,
      ),
    );
    router.go('/detail');
    await tester.pumpAndSettle();
    expect(find.text('First'), findsOneWidget);
    router.go('/detail?title=Updated');
    await tester.pumpAndSettle();
    expect(find.text('Updated'), findsOneWidget);
    await tester.dragFrom(const Offset(1, 200), const Offset(700, 0));
    await tester.pumpAndSettle();
    expect(find.text('Home'), findsOneWidget);
    expect(router.routeInformationProvider.value.uri.path, '/');
  });
  for (final reduced in [false, true]) {
    testWidgets(
      'Android predictive back cancels and commits; reduced=$reduced',
      (tester) async {
        await mount(tester, platform: TargetPlatform.android, reduced: reduced);
        Future<void> sendBack(
          String method, [
          Map<String, dynamic>? args,
        ]) async {
          await tester.binding.defaultBinaryMessenger.handlePlatformMessage(
            'flutter/backgesture',
            const StandardMethodCodec().encodeMethodCall(
              MethodCall(method, args),
            ),
            (_) {},
          );
          await tester.pump();
        }

        Future<void> start() async {
          await sendBack('startBackGesture', {
            'touchOffset': <double>[5, 300],
            'progress': 0.0,
            'swipeEdge': 0,
          });
          await sendBack('updateBackGestureProgress', {
            'touchOffset': <double>[100, 300],
            'progress': 0.35,
            'swipeEdge': 0,
          });
        }

        await start();
        await sendBack('cancelBackGesture');
        await tester.pumpAndSettle();
        expect(find.text('Detail'), findsOneWidget);
        await start();
        await sendBack('commitBackGesture');
        await tester.pumpAndSettle();
        expect(find.text('Open'), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets('edge swipe on a root page does not navigate away', (
    tester,
  ) async {
    await mount(tester);
    tester.state<NavigatorState>(find.byType(Navigator)).pop();
    await tester.pumpAndSettle();
    await tester.dragFrom(const Offset(1, 200), const Offset(700, 0));
    await tester.pumpAndSettle();
    expect(find.text('Open'), findsOneWidget);
    expect(
      tester.state<NavigatorState>(find.byType(Navigator)).canPop(),
      isFalse,
    );
  });
}
