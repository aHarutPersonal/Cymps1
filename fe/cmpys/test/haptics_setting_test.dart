// R3-M6: every haptic goes through one helper that honours the "Sound &
// haptics" setting.

import 'package:cmpys/core/ui/app_shell.dart';
import 'package:cmpys/core/ui/haptics.dart';
import 'package:cmpys/features/cmpys/data/cmpys_seed.dart';
import 'package:cmpys/features/cmpys/state/cmpys_backend_sync.dart';
import 'package:cmpys/features/cmpys/state/cmpys_store.dart';
import 'package:cmpys/features/plan/state/current_plan_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

class _Store extends CmpysStore {
  _Store({required bool haptics}) {
    state = state.copyWith(
      idol: cmpysPlaceholderIdol,
      settings: CmpysSettings(haptics: haptics),
    );
  }
}

/// Records every `HapticFeedback.vibrate` the platform channel receives.
List<String?> _recordHaptics(WidgetTester tester) {
  final calls = <String?>[];
  tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
    SystemChannels.platform,
    (call) async {
      if (call.method == 'HapticFeedback.vibrate') {
        calls.add(call.arguments as String?);
      }
      return null;
    },
  );
  addTearDown(
    () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      null,
    ),
  );
  return calls;
}

Widget _helperApp(CmpysStore? store, ValueChanged<BuildContext> onTap) {
  final app = MaterialApp(
    home: Builder(
      builder: (context) => TextButton(
        onPressed: () => onTap(context),
        child: const Text('tap'),
      ),
    ),
  );
  return store == null
      ? app
      : ProviderScope(
          overrides: [cmpysStoreProvider.overrideWith((ref) => store)],
          child: app,
        );
}

GoRouter _shellRouter() => GoRouter(
  initialLocation: '/one',
  routes: [
    StatefulShellRoute.indexedStack(
      builder: (_, _, shell) => AppShell(navigationShell: shell),
      branches: [
        for (final path in ['/one', '/two', '/three', '/four', '/five'])
          StatefulShellBranch(
            observers: [ShellPushObserver()],
            routes: [GoRoute(path: path, builder: (_, _) => Text(path))],
          ),
      ],
    ),
  ],
);

void main() {
  testWidgets('the helper plays each kind only while haptics are on', (
    tester,
  ) async {
    final calls = _recordHaptics(tester);
    var store = _Store(haptics: true);
    await tester.pumpWidget(
      _helperApp(store, (context) {
        playHaptic(context, AppHaptic.selection);
        playHaptic(context, AppHaptic.light);
      }),
    );
    await tester.tap(find.text('tap'));
    await tester.pump();
    expect(calls, [
      'HapticFeedbackType.selectionClick',
      'HapticFeedbackType.lightImpact',
    ]);

    calls.clear();
    store = _Store(haptics: false);
    await tester.pumpWidget(const SizedBox());
    await tester.pumpWidget(
      _helperApp(store, (context) {
        playHaptic(context, AppHaptic.selection);
        playHaptic(context, AppHaptic.light);
      }),
    );
    await tester.tap(find.text('tap'));
    await tester.pump();
    expect(calls, isEmpty);
  });

  testWidgets('outside a ProviderScope the helper keeps the default (on)', (
    tester,
  ) async {
    final calls = _recordHaptics(tester);
    await tester.pumpWidget(
      _helperApp(null, (context) => playHaptic(context, AppHaptic.selection)),
    );
    await tester.tap(find.text('tap'));
    await tester.pump();
    expect(calls, ['HapticFeedbackType.selectionClick']);
  });

  for (final on in [true, false]) {
    testWidgets('a tab tap clicks only with haptics ${on ? 'on' : 'off'}', (
      tester,
    ) async {
      final calls = _recordHaptics(tester);
      final router = _shellRouter();
      addTearDown(router.dispose);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            cmpysBackendSyncProvider.overrideWith((ref) async {}),
            todayViewProvider.overrideWith((ref) async => null),
            cmpysStoreProvider.overrideWith((ref) => _Store(haptics: on)),
          ],
          child: MaterialApp.router(routerConfig: router),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('floating-nav-item-1')));
      await tester.pumpAndSettle();
      expect(find.text('/two'), findsOneWidget);
      expect(calls, on ? ['HapticFeedbackType.selectionClick'] : isEmpty);
    });
  }
}
