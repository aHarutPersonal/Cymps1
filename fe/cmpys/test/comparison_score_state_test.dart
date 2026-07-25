import 'dart:async';

import 'package:cmpys/features/cmpys/presentation/compare_screen.dart';
import 'package:cmpys/features/cmpys/state/cmpys_backend_sync.dart';
import 'package:cmpys/features/cmpys/state/cmpys_store.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _ComparisonStore extends CmpysStore {
  _ComparisonStore({Map<String, dynamic>? scores}) {
    state = state.copyWith(
      sessionId: 'session-1',
      comparisonMd: 'A generated mentor verdict.',
      liveComparisonScores: scores,
    );
  }
}

Future<void> _pumpCompare(
  WidgetTester tester,
  Future<ComparisonScoresSyncResult> Function(Ref ref) scoreSync, {
  Map<String, dynamic>? scores,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        cmpysStoreProvider.overrideWith(
          (ref) => _ComparisonStore(scores: scores),
        ),
        cmpysBackendSyncProvider.overrideWith((ref) async {}),
        cmpysComparisonScoresSyncProvider.overrideWith(scoreSync),
      ],
      child: const MaterialApp(home: CmpysCompareScreen()),
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
}

Map<String, dynamic> _insufficientScores() => {
  'version': 2,
  'methodology': 'like_for_like_evidence',
  'achievement_baseline_status': 'none_yet',
  'overall': {
    'status': 'insufficient_evidence',
    'you': null,
    'idol': null,
    'gap': null,
    'comparable_dimensions': 0,
    'total_dimensions': 5,
    'reason':
        'No achievements were reported, so an overall comparison would claim evidence that does not exist.',
  },
  'dimensions': [
    {
      'id': 'capital',
      'label': 'Capital at work',
      'you': null,
      'idol': null,
      'status': 'different_basis',
      'comparison_basis': 'personal savings versus business capital raised',
      'you_note': r'Has $50k saved.',
      'idol_note': r'Apple IPO raised over $100m.',
    },
  ],
  'milestones': <Map<String, dynamic>>[],
};

Map<String, dynamic> _estimatedScores() => {
  'version': 2,
  'methodology': 'like_for_like_evidence',
  'achievement_baseline_status': 'self_reported',
  'overall': {
    'status': 'estimated',
    'you': 50,
    'idol': 100,
    'gap': 50,
    'comparable_dimensions': 5,
    'total_dimensions': 5,
  },
  'dimensions': [
    for (final entry in const [
      ('capital', 'Capital at work'),
      ('knowledge', 'Knowledge base'),
      ('habits', 'Daily discipline'),
      ('network', 'Trusted network'),
      ('clarity', 'Strategic clarity'),
    ])
      {
        'id': entry.$1,
        'label': entry.$2,
        'you': 50,
        'idol': 100,
        'status': 'comparable',
        'comparison_basis': 'same demonstrated construct',
        'you_note': 'A user result.',
        'idol_note': 'A mentor result.',
      },
  ],
  'milestones': <Map<String, dynamic>>[],
};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('active score generation is not restartable by tapping', (
    tester,
  ) async {
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

  testWidgets('timed-out score generation becomes an explicit retry', (
    tester,
  ) async {
    await _pumpCompare(
      tester,
      (ref) async => ComparisonScoresSyncResult.timedOut,
    );

    expect(find.byKey(const Key('comparison-scores-retry')), findsOneWidget);
    expect(
      find.text('Your comparison is still being prepared.'),
      findsOneWidget,
    );
    expect(find.byType(CircularProgressIndicator), findsNothing);
  });

  testWidgets('unavailable comparison does not show an endless spinner', (
    tester,
  ) async {
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

  testWidgets('terminal score failure shows an explicit fresh retry', (
    tester,
  ) async {
    await _pumpCompare(
      tester,
      (ref) async => ComparisonScoresSyncResult.failed,
    );

    expect(find.byKey(const Key('comparison-scores-failed')), findsOneWidget);
    expect(find.text('We couldn’t finish your comparison.'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);
  });

  testWidgets('no achievements shows no invented overall percentage', (
    tester,
  ) async {
    await _pumpCompare(
      tester,
      (ref) async => ComparisonScoresSyncResult.ready,
      scores: _insufficientScores(),
    );

    expect(
      find.byKey(const Key('comparison-overall-insufficient')),
      findsOneWidget,
    );
    expect(find.text('No honest overall score yet'), findsOneWidget);
    expect(find.text('Different basis'), findsOneWidget);
    expect(find.textContaining('No numeric score'), findsOneWidget);
    expect(find.textContaining('% of'), findsNothing);
  });

  testWidgets('complete evidence shows a point gap instead of a ratio', (
    tester,
  ) async {
    await _pumpCompare(
      tester,
      (ref) async => ComparisonScoresSyncResult.ready,
      scores: _estimatedScores(),
    );

    expect(find.text('−50'), findsOneWidget);
    expect(find.text('point gap'), findsOneWidget);
    expect(find.textContaining('not a percentage'), findsOneWidget);
    expect(find.textContaining('% of'), findsNothing);
  });
}
