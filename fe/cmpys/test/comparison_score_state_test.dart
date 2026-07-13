import 'dart:async';

import 'package:cmpys/features/cmpys/presentation/compare_screen.dart';
import 'package:cmpys/features/cmpys/state/cmpys_backend_sync.dart';
import 'package:cmpys/features/cmpys/state/cmpys_store.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _ComparisonStore extends CmpysStore {
  _ComparisonStore() {
    state = state.copyWith(
      sessionId: 'session-1',
      comparisonMd: 'A generated mentor verdict.',
    );
  }
}

Future<void> _pumpCompare(
  WidgetTester tester,
  Future<ComparisonScoresSyncResult> Function(Ref ref) scoreSync,
) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        cmpysStoreProvider.overrideWith((ref) => _ComparisonStore()),
        cmpysBackendSyncProvider.overrideWith((ref) async {}),
        cmpysComparisonScoresSyncProvider.overrideWith(scoreSync),
      ],
      child: const MaterialApp(home: CmpysCompareScreen()),
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('active score generation is not restartable by tapping',
      (tester) async {
    final pending = Completer<ComparisonScoresSyncResult>();
    var starts = 0;
    await _pumpCompare(tester, (ref) {
      starts++;
      return pending.future;
    });

    expect(find.byKey(const Key('comparison-scores-pending')), findsOneWidget);
    await tester.tap(find.byKey(const Key('comparison-scores-pending')));
    await tester.pump();
    expect(starts, 1);

    pending.complete(ComparisonScoresSyncResult.timedOut);
    await tester.pump();
  });

  testWidgets('timed-out score generation becomes an explicit retry',
      (tester) async {
    await _pumpCompare(
      tester,
      (ref) async => ComparisonScoresSyncResult.timedOut,
    );

    expect(find.byKey(const Key('comparison-scores-retry')), findsOneWidget);
    expect(find.text('Your comparison is still being prepared.'),
        findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);
  });

  testWidgets('unavailable comparison does not show an endless spinner',
      (tester) async {
    await _pumpCompare(
      tester,
      (ref) async => ComparisonScoresSyncResult.unavailable,
    );

    expect(
      find.byKey(const Key('comparison-scores-unavailable')),
      findsOneWidget,
    );
    expect(find.byType(CircularProgressIndicator), findsNothing);
  });
}
