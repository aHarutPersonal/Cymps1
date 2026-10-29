import 'dart:async';

import 'package:cmpys/app/design_tokens.dart';
import 'package:cmpys/core/network/api_error.dart';
import 'package:cmpys/core/ui/v3/v3.dart';
import 'package:cmpys/features/cmpys/data/cmpys_record_data.dart';
import 'package:cmpys/features/cmpys/data/cmpys_seed.dart';
import 'package:cmpys/features/cmpys/presentation/compare_screen.dart';
import 'package:cmpys/features/cmpys/presentation/record_screen.dart';
import 'package:cmpys/features/cmpys/state/cmpys_backend_sync.dart';
import 'package:cmpys/features/cmpys/state/cmpys_store.dart';
import 'package:cmpys/features/plan/data/plan_repository.dart';
import 'package:cmpys/features/plan/models/plan_models.dart';
import 'package:cmpys/features/plan/state/current_plan_provider.dart';
import 'package:cmpys/features/session/data/session_repository.dart';
import 'package:cmpys/features/session/models/session_models.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show SemanticsNode;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _RecordStore extends CmpysStore {
  _RecordStore({
    List<CmpysWin> wins = const [],
    Map<String, dynamic>? scores,
    int age = 24,
    Map<String, bool> milestones = const {},
  }) {
    state = state.copyWith(
      sessionId: 'session-1',
      idol: cmpysIdols.first, // Warren Buffett
      user: CmpysUser(name: 'Ana', age: age),
      achievements: wins,
      liveComparisonScores: scores,
      milestones: milestones,
    );
  }
}

class _Plans extends Fake implements PlanRepository {
  final saved = <Map<String, Object?>>[];

  @override
  Future<String?> saveAchievement({
    required String title,
    required String category,
    String? notes,
    String? evidenceLink,
    required String source,
    String? planId,
    String? planItemId,
    int cycleNumber = 1,
  }) async {
    saved.add({
      'title': title,
      'category': category,
      'source': source,
      'planId': planId,
      'cycleNumber': cycleNumber,
    });
    return 'ach-${saved.length}';
  }

  final deleted = <String>[];

  /// Completes each delete; an error fails it.
  Completer<void>? deleteGate;

  @override
  Future<void> deleteAchievement(String id) async {
    deleted.add(id);
    await deleteGate?.future;
  }
}

/// The real [idolTimelineProvider] over a fake repository (timeout and
/// cache tests).
class _Sessions extends Fake implements SessionRepository {
  _Sessions([this.answer]);

  final Future<List<IdolTimelineEntry>> Function()? answer;
  int calls = 0;

  @override
  Future<List<IdolTimelineEntry>> idolTimeline(String idolName) {
    calls++;
    return answer?.call() ?? Future.value(const <IdolTimelineEntry>[]);
  }
}

class _Plan extends CurrentPlanController {
  _Plan(PlanRepository repo) : super(repo: repo, readJobId: () => null) {
    state = CurrentPlanState(
      status: CurrentPlanStatus.ready,
      plan: BackendPlan(
        id: 'plan-7',
        durationWeeks: 12,
        weeklyHours: 4,
        cycleNumber: 2,
        items: const [],
      ),
    );
  }
}

CmpysWin _win(
  String id,
  String title, {
  String dim = 'knowledge',
  int age = 24,
  String source = 'manual',
  bool assessed = true,
  String note = '',
  String? idolNote,
  int impact = 2,
  bool synced = false,
  String? milestoneId,
  String? serverId,
}) => CmpysWin(
  id: id,
  title: title,
  dim: dim,
  age: age,
  impact: impact,
  source: source,
  assessed: assessed,
  note: note,
  idolNote: idolNote,
  synced: synced,
  milestoneId: milestoneId,
  serverId: serverId,
);

Map<String, dynamic> _scores({
  List<Map<String, dynamic>> milestones = const [],
}) => {
  'version': 3,
  'methodology': 'like_for_like_evidence',
  'overall': {'status': 'not_combined', 'you': null, 'idol': null},
  'dimensions': [
    {
      'id': 'knowledge',
      'label': 'Knowledge base',
      'status': 'comparable',
      'you': 34,
      'idol': 78,
      'comparison_basis': '',
      'you_evidence': 'self_reported',
      'idol_evidence': 'documented',
      'you_note': '',
      'idol_note': '',
    },
  ],
  'milestones': milestones,
};

Future<_RecordStore> _pump(
  WidgetTester tester, {
  List<CmpysWin> wins = const [],
  Map<String, dynamic>? scores,
  int age = 24,
  _Plans? plans,
  Size size = const Size(390, 2400),
  double textScale = 1,
  bool reduced = false,
  Map<String, bool> milestones = const {},
  FutureOr<List<IdolTimelineEntry>> Function()? timeline,
  List<String>? timelineCalls,
  _Sessions? sessions,
}) async {
  await tester.binding.setSurfaceSize(size);
  addTearDown(() => tester.binding.setSurfaceSize(null));
  final store = _RecordStore(
    wins: wins,
    scores: scores,
    age: age,
    milestones: milestones,
  );
  final repo = plans ?? _Plans();
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        cmpysStoreProvider.overrideWith((ref) => store),
        planRepositoryProvider.overrideWithValue(repo),
        currentPlanProvider.overrideWith((ref) => _Plan(repo)),
        if (sessions != null)
          // The real provider (its timeout and cache) over a fake repository.
          sessionRepositoryProvider.overrideWithValue(sessions)
        else
          // No catalog timeline by default: the seeded ledger shows.
          idolTimelineProvider.overrideWith((ref, name) {
            timelineCalls?.add(name);
            return timeline?.call() ?? const <IdolTimelineEntry>[];
          }),
      ],
      child: MaterialApp(
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(
            textScaler: TextScaler.linear(textScale),
            disableAnimations: reduced,
          ),
          child: child!,
        ),
        home: const CmpysRecordScreen(),
      ),
    ),
  );
  await _settle(tester);
  return store;
}

Future<void> _settle(WidgetTester tester, [int ms = 1500]) async {
  for (var i = 0; i < ms ~/ 100; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

Finder _card(String id) => find.byKey(ValueKey('record-entry-$id'));

Finder _inCard(String id, Finder matching) =>
    find.descendant(of: _card(id), matching: matching);

final _sheet = find.byKey(V3Sheet.panelKey);

Finder _inSheet(Finder matching) =>
    find.descendant(of: _sheet, matching: matching);

Future<void> _open(WidgetTester tester, String id) async {
  await tester.ensureVisible(_card(id));
  await tester.pump();
  await tester.tap(_card(id));
  await _settle(tester, 800);
}

Future<void> _closeSheet(WidgetTester tester) async {
  Navigator.of(tester.element(_sheet)).pop();
  await _settle(tester, 800);
}

Future<void> _filter(WidgetTester tester, String label) async {
  await tester.ensureVisible(find.widgetWithText(V3Chip, label));
  await tester.pump();
  await tester.tap(find.widgetWithText(V3Chip, label));
  await _settle(tester, 1200);
}

V3Button _button(WidgetTester tester, String label) =>
    tester.widget<V3Button>(find.widgetWithText(V3Button, label));

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('claim_requires_10_chars', (tester) async {
    final store = await _pump(
      tester,
      scores: _scores(
        milestones: [
          {'id': 'm1', 'label': 'Read 100 annual reports', 'hit_by_age': 22},
        ],
      ),
    );

    await _open(tester, 'milestone-m1');
    expect(_inSheet(find.text('Buffett’s milestone · Age 22')), findsOneWidget);
    await tester.tap(find.text('Claim a similar milestone'));
    await _settle(tester, 1200);

    expect(_inSheet(find.text('Claim milestone')), findsOneWidget);
    expect(
      _inSheet(
        find.text(
          '“Read 100 annual reports” at 22. Explain what you did that’s '
          'comparable.',
        ),
      ),
      findsOneWidget,
    );

    // Nine characters once trimmed: Claim stays disabled and does nothing.
    await tester.enterText(_inSheet(find.byType(TextField)), '   Read 9 ar   ');
    await tester.pump();
    expect(_button(tester, 'Claim').disabled, isTrue);
    await tester.tap(find.widgetWithText(V3Button, 'Claim'));
    await _settle(tester, 600);
    expect(store.state.milestones['m1'], isNot(true));
    expect(store.state.achievements, isEmpty);

    // Ten characters: Claim saves through the store's claim.
    await tester.enterText(_inSheet(find.byType(TextField)), ' Read ten a ');
    await tester.pump();
    expect(_button(tester, 'Claim').disabled, isFalse);
    await tester.tap(find.widgetWithText(V3Button, 'Claim'));
    await _settle(tester, 1000);

    expect(store.state.milestones['m1'], isTrue);
    final claim = store.state.achievements.single;
    expect(claim.source, 'milestone');
    expect(claim.title, 'Read 100 annual reports');
    expect(claim.note, 'Read ten a');
    expect(claim.age, 24);
    expect(claim.milestoneId, 'm1');
    expect(claim.synced, isFalse);
    expect(find.text('Milestone claimed'), findsOneWidget);
    expect(_sheet, findsNothing);

    // The milestone is marked claimed and can't be claimed again; the claim
    // shows on your side.
    expect(_inCard('milestone-m1', find.text('Claimed')), findsOneWidget);
    expect(
      _inCard(claim.id, find.text('Claimed: Read 100 annual reports')),
      findsOneWidget,
    );
    await _open(tester, 'milestone-m1');
    expect(find.text('Claim a similar milestone'), findsNothing);
    await _closeSheet(tester);

    // Deleting the claim (a local entry) clears the milestone's claim.
    await _open(tester, claim.id);
    await tester.tap(_inSheet(find.text('Delete entry')));
    await _settle(tester, 800);
    expect(store.state.achievements, isEmpty);
    expect(store.state.milestones['m1'], isNot(true));
    expect(_inCard('milestone-m1', find.text('Claimed')), findsNothing);
    await _open(tester, 'milestone-m1');
    expect(find.text('Claim a similar milestone'), findsOneWidget);
  });

  testWidgets('the undated milestone’s claim drops “at N”', (tester) async {
    await _pump(
      tester,
      scores: _scores(
        milestones: [
          {'id': 'm2', 'label': 'Ran a partnership', 'hit_by_age': 0},
        ],
      ),
    );
    await _open(tester, 'milestone-m2');
    expect(_inSheet(find.text('Buffett’s milestone')), findsOneWidget);
    await tester.tap(find.text('Claim a similar milestone'));
    await _settle(tester, 1200);
    expect(
      _inSheet(
        find.text(
          '“Ran a partnership”. Explain what you did that’s comparable.',
        ),
      ),
      findsOneWidget,
    );
  });

  testWidgets('delete_only_for_local', (tester) async {
    final store = await _pump(
      tester,
      wins: [
        _win(
          'w-manual',
          'Bought my first index fund',
          dim: 'capital',
          note: 'Vanguard, 0.03% fees.',
          idolNote: 'Money you keep is worth more than money you make.',
        ),
        _win(
          'w-chat',
          'Asked an expert a question',
          source: 'chat',
          synced: true,
        ),
        _win(
          'w-logged',
          'Wrote my own analysis',
          dim: 'judgment',
          synced: true,
        ),
        _win(
          'w-claim',
          'Read 100 annual reports',
          source: 'milestone',
          milestoneId: 'm9',
        ),
        _win(
          'w-auto',
          'Passed “Depreciation: the cost you don’t see” with 4/4',
          dim: 'practice',
          source: 'auto',
          synced: true,
        ),
      ],
      scores: _scores(
        milestones: [
          {'id': 'm1', 'label': 'Read 100 annual reports', 'hit_by_age': 22},
        ],
      ),
    );

    // A v2 win kept only on this device: source copy, note, mentor note,
    // delete.
    await _open(tester, 'w-manual');
    expect(_inSheet(find.text('Your win · Age 24')), findsOneWidget);
    expect(
      _inSheet(find.text('Saved on this device · not verified')),
      findsOneWidget,
    );
    expect(_inSheet(find.text('Vanguard, 0.03% fees.')), findsOneWidget);
    expect(
      _inSheet(find.text('Money you keep is worth more than money you make.')),
      findsOneWidget,
    );
    expect(_inSheet(find.byType(V3Avatar)), findsOneWidget);
    expect(_inSheet(find.text('Delete entry')), findsOneWidget);
    expect(_inSheet(find.text('Claim a similar milestone')), findsNothing);
    await _closeSheet(tester);

    // Wins reported to the mentor or logged here have a server copy: they
    // keep the design's source line but can't be deleted.
    for (final id in ['w-chat', 'w-logged']) {
      await _open(tester, id);
      expect(
        _inSheet(find.text('Saved on this device · not verified')),
        findsOneWidget,
      );
      expect(_inSheet(find.text('Delete entry')), findsNothing, reason: id);
      await _closeSheet(tester);
    }

    // A claim is device-only: deletable.
    await _open(tester, 'w-claim');
    expect(_inSheet(find.text('Delete entry')), findsOneWidget);
    await _closeSheet(tester);

    // A plan-completion win mirrors a server achievement: no delete.
    await _open(tester, 'w-auto');
    expect(
      _inSheet(find.text('Recorded from plan completion')),
      findsOneWidget,
    );
    expect(_inSheet(find.text('Delete entry')), findsNothing);
    await _closeSheet(tester);

    // The mentor's milestone: biography source, claimable, no delete.
    await _open(tester, 'milestone-m1');
    expect(_inSheet(find.text('Source: documented biography')), findsOneWidget);
    expect(_inSheet(find.text('Delete entry')), findsNothing);
    await _closeSheet(tester);

    // Deleting the local entry removes it from the record.
    await _open(tester, 'w-manual');
    await tester.tap(_inSheet(find.text('Delete entry')));
    await _settle(tester, 800);
    expect(store.state.achievements.map((w) => w.id), [
      'w-chat',
      'w-logged',
      'w-claim',
      'w-auto',
    ]);
    expect(find.text('Entry removed'), findsOneWidget);
    expect(_card('w-manual'), findsNothing);

    // The rule itself.
    expect(recordWinIsLocal(_win('a', 'a', source: 'manual')), isTrue);
    expect(recordWinIsLocal(_win('a', 'a', source: 'chat')), isTrue);
    expect(recordWinIsLocal(_win('a', 'a', source: 'milestone')), isTrue);
    expect(recordWinIsLocal(_win('a', 'a', source: 'auto')), isFalse);
    expect(recordWinIsLocal(_win('a', 'a', source: 'intake')), isFalse);
    expect(recordWinIsLocal(_win('a', 'a', source: 'something')), isFalse);
    for (final source in ['manual', 'chat', 'milestone', 'auto']) {
      expect(
        recordWinIsLocal(_win('a', 'a', source: source, synced: true)),
        isFalse,
        reason: source,
      );
    }
  });

  testWidgets('a synced win stays undeletable after the reassess', (
    tester,
  ) async {
    final store = await _pump(
      tester,
      wins: [
        _win('w1', 'Wrote my own analysis', assessed: false, synced: true),
      ],
    );
    store.reassess();
    await _settle(tester, 300);
    final win = store.state.achievements.single;
    expect(win.assessed, isTrue);
    expect(win.synced, isTrue);
    store.setWinIdolNote('w1', 'Good. Keep going.');
    expect(store.state.achievements.single.synced, isTrue);
    // And through a save and reload.
    final reloaded = CmpysState.fromJson(store.state.toJson());
    expect(reloaded.achievements.single.synced, isTrue);
    expect(recordWinIsLocal(reloaded.achievements.single), isFalse);

    await _open(tester, 'w1');
    expect(_inSheet(find.text('Delete entry')), findsNothing);
  });

  group('deleting a synced win (R3-I2)', () {
    testWidgets('a synced win with its server id deletes the server copy, '
        'then the entry', (tester) async {
      final plans = _Plans();
      final store = await _pump(
        tester,
        plans: plans,
        wins: [
          _win(
            'w-synced',
            'Wrote my own analysis',
            synced: true,
            serverId: 'ach-7',
          ),
          _win('w-older', 'Read a filing', synced: true),
        ],
      );
      // An older synced win has no server id: it stays non-deletable.
      await _open(tester, 'w-older');
      expect(_inSheet(find.text('Delete entry')), findsNothing);
      await _closeSheet(tester);

      await _open(tester, 'w-synced');
      expect(_inSheet(find.text('Delete entry')), findsOneWidget);
      await tester.tap(_inSheet(find.text('Delete entry')));
      await _settle(tester, 800);
      expect(plans.deleted, ['ach-7']);
      expect(store.state.achievements.map((w) => w.id), ['w-older']);
      expect(find.text('Entry removed'), findsOneWidget);
      expect(_card('w-synced'), findsNothing);
    });

    testWidgets('a failed server delete keeps the entry and says so', (
      tester,
    ) async {
      final plans = _Plans()..deleteGate = Completer<void>();
      final store = await _pump(
        tester,
        plans: plans,
        wins: [
          _win(
            'w-synced',
            'Wrote my own analysis',
            synced: true,
            serverId: 'ach-7',
          ),
        ],
      );
      await _open(tester, 'w-synced');
      await tester.tap(_inSheet(find.text('Delete entry')));
      await tester.pump();
      plans.deleteGate!.completeError(Exception('offline'));
      await _settle(tester, 800);
      expect(plans.deleted, ['ach-7']);
      expect(store.state.achievements.single.id, 'w-synced');
      expect(find.text('Couldn’t delete this entry. Try again.'), findsOne);
      expect(find.text('Entry removed'), findsNothing);
      await _settle(tester, 3000);
    });

    testWidgets('a 404 from the server delete means it is already gone, so '
        'the entry is removed', (tester) async {
      final plans = _Plans()..deleteGate = Completer<void>();
      final store = await _pump(
        tester,
        plans: plans,
        wins: [
          _win(
            'w-synced',
            'Wrote my own analysis',
            synced: true,
            serverId: 'ach-7',
          ),
        ],
      );
      await _open(tester, 'w-synced');
      await tester.tap(_inSheet(find.text('Delete entry')));
      await tester.pump();
      plans.deleteGate!.completeError(
        const ApiError(message: 'Not found', statusCode: 404),
      );
      await _settle(tester, 800);
      expect(plans.deleted, ['ach-7']);
      expect(store.state.achievements, isEmpty);
      expect(find.text('Entry removed'), findsOneWidget);
      expect(find.text('Couldn’t delete this entry. Try again.'), findsNothing);
      await _settle(tester, 3000);
    });

    testWidgets('another API error (a 500) still keeps the entry', (
      tester,
    ) async {
      final plans = _Plans()..deleteGate = Completer<void>();
      final store = await _pump(
        tester,
        plans: plans,
        wins: [
          _win(
            'w-synced',
            'Wrote my own analysis',
            synced: true,
            serverId: 'ach-7',
          ),
        ],
      );
      await _open(tester, 'w-synced');
      await tester.tap(_inSheet(find.text('Delete entry')));
      await tester.pump();
      plans.deleteGate!.completeError(
        const ApiError(message: 'Boom', statusCode: 500),
      );
      await _settle(tester, 800);
      expect(store.state.achievements.single.id, 'w-synced');
      expect(find.text('Couldn’t delete this entry. Try again.'), findsOne);
      await _settle(tester, 3000);
    });
  });

  test('an old v2 manual win (no synced field) is still deletable', () {
    final win = CmpysWin.fromJson({
      'id': 'w-old',
      'title': 'Opened a brokerage account',
      'dim': 'capital',
      'age': 22,
      'impact': 2,
      'source': 'manual',
      'assessed': true,
    });
    expect(win.synced, isFalse);
    expect(win.milestoneId, isNull);
    expect(recordWinIsLocal(win), isTrue);
  });

  test('an old payload with dimShift loads cleanly', () {
    final json = CmpysState.initial().toJson()
      ..['dimShift'] = {'knowledge': 6, 'habits': 3}
      ..['achievements'] = [
        {'id': 'w1', 'title': 'Read a filing', 'dim': 'habits', 'age': 23},
      ]
      ..['liveComparisonScores'] = _scores();
    final state = CmpysState.fromJson(json);
    expect(state.achievements.single.dim, 'habits');
    expect(state.liveDims().single.you, 34);
    expect(state.toJson().containsKey('dimShift'), isFalse);
  });

  test('old dimension ids map to the v3 ids', () {
    // v2 record ids.
    expect(recordDimId('capital'), 'capital');
    expect(recordDimId('knowledge'), 'knowledge');
    expect(recordDimId('network'), 'network');
    expect(recordDimId('habits'), 'practice');
    expect(recordDimId('clarity'), 'judgment');
    // v3 ids are kept.
    expect(recordDimId('practice'), 'practice');
    expect(recordDimId('judgment'), 'judgment');
    // The design prototype's short ids.
    expect(recordDimId('know'), 'knowledge');
    expect(recordDimId('prac'), 'practice');
    expect(recordDimId('cap'), 'capital');
    expect(recordDimId('net'), 'network');
    expect(recordDimId('judg'), 'judgment');
    // Case and whitespace don't matter; anything else is Knowledge.
    expect(recordDimId(' Habits '), 'practice');
    expect(recordDimId('mystery'), 'knowledge');
    expect(recordDimId(''), 'knowledge');
    // A claimed milestone files under a v3 id.
    expect(cmpysMilestoneDim.values.toSet(), {
      'knowledge',
      'practice',
      'capital',
      'network',
      'judgment',
    });
  });

  testWidgets('the dimension filter shows each v3 dimension, old ids too', (
    tester,
  ) async {
    await _pump(
      tester,
      wins: [
        _win('w-know', 'Read a full filing', dim: 'knowledge', age: 23),
        _win('w-habit', 'Woke at six for 30 days', dim: 'habits', age: 22),
        _win('w-prac', 'Built a DCF from scratch', dim: 'practice', age: 24),
        _win('w-judg', 'Wrote down my sell rule', dim: 'judgment', age: 24),
        _win('w-clar', 'Decided on a direction', dim: 'clarity', age: 21),
      ],
    );

    // All: every win and the mentor's timeline.
    for (final id in ['w-know', 'w-habit', 'w-prac', 'w-judg', 'w-clar']) {
      expect(_card(id), findsOneWidget, reason: id);
    }
    expect(find.textContaining('Read The Intelligent Investor'), findsOne);
    // Old ids carry their v3 label, never Knowledge by fallback.
    expect(_inCard('w-habit', find.text('Practice')), findsOneWidget);
    expect(_inCard('w-clar', find.text('Judgment')), findsOneWidget);

    await _filter(tester, 'Practice');
    expect(_card('w-habit'), findsOneWidget);
    expect(_card('w-prac'), findsOneWidget);
    expect(_card('w-know'), findsNothing);
    expect(_card('w-judg'), findsNothing);
    expect(_card('w-clar'), findsNothing);
    // Mentor events have no dimension: they show only under All.
    expect(find.textContaining('Read The Intelligent Investor'), findsNothing);
    expect(
      tester.widget<V3Chip>(find.widgetWithText(V3Chip, 'Practice')).on,
      isTrue,
    );

    await _filter(tester, 'Judgment');
    expect(_card('w-judg'), findsOneWidget);
    expect(_card('w-clar'), findsOneWidget);
    expect(_card('w-habit'), findsNothing);

    await _filter(tester, 'Network');
    expect(find.text('Nothing here yet'), findsOneWidget);

    await _filter(tester, 'All');
    expect(_card('w-know'), findsOneWidget);
    expect(find.textContaining('Read The Intelligent Investor'), findsOne);
  });

  testWidgets('the dual timeline places both sides by age, now highlighted', (
    tester,
  ) async {
    await _pump(
      tester,
      wins: [
        _win('w-now', 'Built a DCF from scratch', dim: 'practice'),
        _win('w-old', 'Read a full filing', age: 19),
        // Legacy data at age 0 has no place by age: it goes under Undated.
        _win('w-zero', 'Opened a brokerage account', dim: 'capital', age: 0),
      ],
      scores: _scores(
        milestones: [
          {'id': 'm1', 'label': 'Read 100 annual reports', 'hit_by_age': 22},
          {'id': 'm2', 'label': 'Ran a partnership', 'hit_by_age': 0},
        ],
      ),
    );

    // The legend.
    expect(find.text('You'), findsOneWidget);
    expect(find.text('Buffett'), findsOneWidget);
    expect(find.text('YOUR RECORD'), findsOneWidget);

    Color pill(String key) {
      final box = tester.widget<Container>(
        find.byKey(ValueKey('record-age-$key')),
      );
      return (box.decoration! as BoxDecoration).color!;
    }

    expect(pill('24'), AppColors.ink);
    expect(pill('19'), AppColors.paper2);
    expect(pill('22'), AppColors.paper2);
    expect(find.text('Age 0'), findsNothing);
    expect(find.text('Undated'), findsOneWidget);

    // Undated is last; the 0-age win and the undated milestone sit in it.
    final undatedY = tester.getTopLeft(find.text('Undated')).dy;
    expect(tester.getTopLeft(find.text('Age 24')).dy, lessThan(undatedY));
    expect(tester.getTopLeft(_card('w-zero')).dy, greaterThan(undatedY));
    expect(tester.getTopLeft(_card('milestone-m2')).dy, greaterThan(undatedY));

    // Your wins on the left, the mentor's on the right.
    final mid = tester.getSize(find.byType(CmpysRecordScreen)).width / 2;
    expect(tester.getTopRight(_card('w-now')).dx, lessThan(mid));
    expect(tester.getTopLeft(_card('milestone-m1')).dx, greaterThan(mid));
    // The mentor's documented timeline (up to your age) is on the right too.
    final ledger = find.ancestor(
      of: find.textContaining('Read The Intelligent Investor'),
      matching: find.byWidgetPredicate(
        (w) =>
            w.key is ValueKey<String> &&
            (w.key! as ValueKey<String>).value.startsWith('record-entry-'),
      ),
    );
    expect(tester.getTopLeft(ledger).dx, greaterThan(mid));
    expect(find.textContaining('Buffett Partnership'), findsNothing); // age 25

    // The undated win's sheet has no age.
    await _open(tester, 'w-zero');
    expect(_inSheet(find.text('Your win')), findsOneWidget);
  });

  testWidgets('the reassess banner reviews new entries on this device', (
    tester,
  ) async {
    final store = await _pump(
      tester,
      wins: [
        _win('w1', 'Read a full filing', assessed: false),
        _win('w2', 'Built a DCF', dim: 'practice', assessed: false),
        _win('w3', 'Old entry'),
      ],
    );

    const banner = '2 new entries waiting. Reassess on this device';
    expect(find.text(banner), findsOneWidget);
    await tester.tap(find.text(banner));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.text('Reviewing your new entries'), findsOneWidget);
    expect(store.state.pendingWins(), hasLength(2));

    await tester.pump(const Duration(milliseconds: 2300));
    await tester.pump(const Duration(milliseconds: 600));
    expect(find.text('Entries reviewed'), findsOneWidget);
    expect(
      find.text(
        'Updated on this device only. This isn’t a new assessment of your '
        'comparison scores.',
      ),
      findsOneWidget,
    );
    expect(store.state.pendingWins(), isEmpty);

    await tester.tap(find.widgetWithText(V3Button, 'Done'));
    await _settle(tester, 800);
    expect(find.text('Entries reviewed'), findsNothing);
    expect(find.text(banner), findsNothing);
  });

  testWidgets('one pending entry reads “entry”', (tester) async {
    await _pump(tester, wins: [_win('w1', 'Read a filing', assessed: false)]);
    expect(
      find.text('1 new entry waiting. Reassess on this device'),
      findsOneWidget,
    );
  });

  testWidgets('Log a win opens the WinSheet in record mode and saves manual', (
    tester,
  ) async {
    final plans = _Plans();
    final store = await _pump(tester, plans: plans, size: const Size(800, 900));

    await tester.tap(find.widgetWithText(V3Button, 'Log a win'));
    await _settle(tester, 800);

    final sheet = tester.widget<WinSheet>(find.byType(WinSheet));
    expect(sheet.mode, WinSheetMode.record);
    expect(sheet.mentorShort, 'Buffett');
    expect(sheet.age, 24);

    Finder inWin(Finder f) =>
        find.descendant(of: find.byType(WinSheet), matching: f);
    await tester.enterText(
      find.byKey(WinSheet.textFieldKey),
      'Wrote my own analysis',
    );
    await tester.pump();
    await tester.tap(inWin(find.text('Continue')));
    await _settle(tester, 600);
    await tester.tap(inWin(find.text('Judgment')));
    await _settle(tester, 900);
    await tester.tap(inWin(find.text('Solid step')));
    await tester.pump();
    await tester.tap(inWin(find.text('Continue')));
    await _settle(tester, 600);
    await tester.tap(inWin(find.text('Send to Buffett')));
    await _settle(tester, 1600);
    expect(inWin(find.text('Saved to your record.')), findsOne);
    await tester.tap(inWin(find.text('Done')));
    await _settle(tester, 800);

    expect(find.byType(WinSheet), findsNothing);
    expect(plans.saved.single['source'], 'manual');
    expect(plans.saved.single['category'], 'mindset');
    expect(plans.saved.single['planId'], 'plan-7');
    final win = store.state.achievements.single;
    expect(win.source, 'manual');
    expect(win.dim, 'judgment');
    expect(win.age, 24);
    expect(win.assessed, isFalse);
    expect(win.synced, isTrue); // saved to the server too
    expect(win.serverId, 'ach-1'); // so it can be deleted there too
    expect(win.idolNote, isNull); // no canned mentor line (R3-M7)
    expect(find.text('Added to your record'), findsOneWidget); // the toast
    expect(_inCard(win.id, find.text('Judgment')), findsOneWidget);
    expect(
      find.text('1 new entry waiting. Reassess on this device'),
      findsOneWidget,
    );
  });

  test('the on-device reassess leaves the comparison scores alone', () async {
    final store = _RecordStore(
      scores: _scores(),
      wins: [
        _win('w1', 'Read a full filing', impact: 3, assessed: false),
        _win('w2', 'Read another', impact: 2, assessed: false),
      ],
    );
    await store.ready;
    expect(store.state.liveDims().single.you, 34);
    store.reassess();
    expect(store.state.pendingWins(), isEmpty);
    expect(store.state.liveDims().single.you, 34);
    // Nothing device-side survives a round trip to shift the scores either.
    final reloaded = CmpysState.fromJson(store.state.toJson());
    expect(reloaded.liveDims().single.you, 34);
    store.dispose();
  });

  testWidgets('Compare shows the server score after an on-device reassess', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(390, 2400));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final store = _RecordStore(
      scores: _scores(),
      wins: [_win('w1', 'Read a full filing', impact: 3, assessed: false)],
    )..reassess();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          cmpysStoreProvider.overrideWith((ref) => store),
          cmpysBackendSyncProvider.overrideWith((ref) async {}),
          cmpysComparisonScoresSyncProvider.overrideWith(
            (ref) async => ComparisonScoresSyncResult.ready,
          ),
        ],
        child: const MaterialApp(home: CmpysCompareScreen()),
      ),
    );
    await _settle(tester, 3000);
    final row = find.ancestor(
      of: find.text('Knowledge base'),
      matching: find.byKey(const ValueKey('compare-dim-row')),
    );
    await tester.ensureVisible(row.first);
    await tester.tap(row.first);
    await _settle(tester, 1500);
    expect(_inSheet(find.text('34')), findsOneWidget);
    expect(_inSheet(find.text('37')), findsNothing);
  });

  group('mentor timeline', () {
    const events = [
      IdolTimelineEntry(
        age: 19,
        text: 'Reads The Intelligent Investor',
        id: 'e1',
        category: 'learning',
      ),
      IdolTimelineEntry(
        age: 21,
        text: 'Buys a Texaco station with a friend',
        id: 'e2',
        category: 'finance',
      ),
      IdolTimelineEntry(
        age: 22,
        text: 'Teaches a night class on investing',
        id: 'e3',
        category: 'impact',
      ),
      IdolTimelineEntry(
        age: 23,
        text: 'Writes his decision rules down',
        id: 'e4',
        category: 'mindset',
      ),
      IdolTimelineEntry(
        age: 24,
        text: 'Joins Graham-Newman as an analyst',
        id: 'e5',
        category: 'career',
      ),
      IdolTimelineEntry(
        age: 24,
        text: 'Marries Susan Thompson',
        id: 'e6',
        category: 'other',
      ),
      IdolTimelineEntry(age: 25, text: 'Starts the Buffett Partnership'),
    ];

    test('categories map to v3 dimensions, other to none', () {
      expect(recordDimForCategory('learning'), 'knowledge');
      expect(recordDimForCategory('impact'), 'practice');
      expect(recordDimForCategory('finance'), 'capital');
      expect(recordDimForCategory('career'), 'network');
      expect(recordDimForCategory(' Mindset '), 'judgment');
      expect(recordDimForCategory('other'), isNull);
      expect(recordDimForCategory('unknown'), isNull);
      expect(recordDimForCategory(null), isNull);

      final st = _RecordStore().state;
      final mentor = recordTimeline(
        st,
        mentorTimeline: events,
      ).where((e) => !e.mine).toList();
      // Capped at your age (24): the age-25 event is left out; the ledger
      // isn't used.
      expect(mentor.map((e) => e.id), [
        'timeline-e1',
        'timeline-e2',
        'timeline-e3',
        'timeline-e4',
        'timeline-e5',
        'timeline-e6',
      ]);
      expect(mentor.map((e) => e.dim), [
        'knowledge',
        'capital',
        'practice',
        'judgment',
        'network',
        null,
      ]);
      expect(mentor.first.title, 'Reads The Intelligent Investor');
      expect(recordSourceCopy(mentor.first), 'Source: documented biography');
    });

    test('a win kept on the account never claims to be device-only', () {
      // A win restored from the server (or synced from this device) carries
      // a server id; "Saved on this device · not verified" would be untrue.
      const synced = RecordEntry(
        id: 'srv-7',
        mine: true,
        title: 'Valued a car wash',
        source: 'manual',
        serverId: '7',
      );
      const deviceOnly = RecordEntry(
        id: 'w1',
        mine: true,
        title: 'Valued a car wash',
        source: 'manual',
      );
      expect(recordSourceCopy(synced), 'Saved to your record');
      expect(recordSourceCopy(deviceOnly), 'Saved on this device · not verified');
    });

    test('a comparison milestone replaces the matching event', () {
      expect(
        recordSameEvent(
          'Joined Graham-Newman as an analyst',
          24,
          'Joins Graham-Newman as an analyst',
          24,
        ),
        isTrue,
      );
      // A different age, or different words, is a different event.
      expect(
        recordSameEvent(
          'Joined Graham-Newman as an analyst',
          23,
          'Joins Graham-Newman as an analyst',
          24,
        ),
        isFalse,
      );
      expect(
        recordSameEvent(
          'Married Susan Thompson',
          24,
          'Joins Graham-Newman as an analyst',
          24,
        ),
        isFalse,
      );
      expect(recordSameEvent('Joined', null, 'Joined', null), isFalse);

      final st = _RecordStore(
        scores: _scores(
          milestones: [
            {
              'id': 'm1',
              'label': 'Joined Graham-Newman as an analyst',
              'hit_by_age': 24,
            },
          ],
        ),
      ).state;
      final mentor = recordTimeline(
        st,
        mentorTimeline: events,
      ).where((e) => !e.mine).toList();
      expect(mentor.map((e) => e.id), isNot(contains('timeline-e5')));
      final milestone = mentor.singleWhere((e) => e.id == 'milestone-m1');
      expect(milestone.dim, 'network'); // the event's category
      expect(milestone.claimable, isTrue);
      expect(mentor.map((e) => e.id), contains('timeline-e6'));
    });

    testWidgets('a matched milestone files its claim under the event’s '
        'dimension', (tester) async {
      final store = await _pump(
        tester,
        timeline: () => events,
        scores: _scores(
          milestones: [
            {
              'id': 'm1', // position mapping would say Judgment
              'label': 'Joined Graham-Newman as an analyst',
              'hit_by_age': 24,
            },
          ],
        ),
      );
      expect(find.text('Joins Graham-Newman as an analyst'), findsNothing);
      expect(_inCard('milestone-m1', find.text('Network')), findsOneWidget);
      await _open(tester, 'milestone-m1');
      await tester.tap(find.text('Claim a similar milestone'));
      await _settle(tester, 1200);
      await tester.enterText(
        _inSheet(find.byType(TextField)),
        'I joined a fund as a junior analyst',
      );
      await tester.pump();
      await tester.tap(find.widgetWithText(V3Button, 'Claim'));
      await _settle(tester, 1000);
      expect(store.state.achievements.single.dim, 'network');
    });

    testWidgets('mentor events are filterable by dimension', (tester) async {
      await _pump(tester, timeline: () => events);
      expect(_card('timeline-e1'), findsOneWidget);
      expect(_inCard('timeline-e1', find.text('Knowledge')), findsOneWidget);
      // The catalog replaces the seeded ledger.
      expect(
        find.textContaining('Called it the best book on investing'),
        findsNothing,
      );

      await _filter(tester, 'Capital');
      expect(_card('timeline-e2'), findsOneWidget);
      expect(_card('timeline-e1'), findsNothing);
      expect(_card('timeline-e6'), findsNothing); // "other": All only

      await _filter(tester, 'Judgment');
      expect(_card('timeline-e4'), findsOneWidget);
      expect(_card('timeline-e2'), findsNothing);

      await _filter(tester, 'All');
      expect(_card('timeline-e6'), findsOneWidget);
    });

    testWidgets('a failed or empty fetch falls back to the seeded ledger', (
      tester,
    ) async {
      final calls = <String>[];
      await _pump(
        tester,
        timelineCalls: calls,
        timeline: () => throw Exception('offline'),
      );
      expect(calls, ['Warren Buffett']);
      expect(find.textContaining('Read The Intelligent Investor'), findsOne);

      await tester.pumpWidget(const SizedBox());
      await _pump(tester); // empty
      expect(find.textContaining('Read The Intelligent Investor'), findsOne);
    });

    testWidgets('your side shows at once; the mentor’s when the fetch lands', (
      tester,
    ) async {
      final fetch = Completer<List<IdolTimelineEntry>>();
      await _pump(
        tester,
        wins: [_win('w1', 'Read a full filing')],
        scores: _scores(
          milestones: [
            {'id': 'm1', 'label': 'Read 100 annual reports', 'hit_by_age': 22},
            {
              'id': 'm5',
              'label': 'Joined Graham-Newman as an analyst',
              'hit_by_age': 24,
            },
          ],
        ),
        timeline: () => fetch.future,
      );
      // Your wins and the comparison milestones (both on the device) show
      // at once; only the documented events wait, behind a loading card.
      expect(_card('w1'), findsOneWidget);
      expect(_card('milestone-m1'), findsOneWidget);
      expect(_card('milestone-m5'), findsOneWidget);
      expect(_inCard('milestone-m5', find.byType(V3Tag)), findsNothing);
      expect(find.byKey(const ValueKey('record-events-loading')), findsOne);
      expect(_card('timeline-e1'), findsNothing);
      expect(
        find.textContaining('Read The Intelligent Investor'),
        findsNothing,
      );
      final milestoneCard = tester.element(_card('milestone-m5'));

      fetch.complete(events);
      await _settle(tester, 1200);
      expect(_card('timeline-e1'), findsOneWidget);
      expect(find.byKey(const ValueKey('record-events-loading')), findsNothing);
      // The matching event is dropped; the milestone stays where it was (the
      // same element) and only gains the event's dimension.
      expect(_card('timeline-e5'), findsNothing);
      expect(tester.element(_card('milestone-m5')), same(milestoneCard));
      expect(_inCard('milestone-m5', find.text('Network')), findsOneWidget);
    });

    testWidgets('an empty record shows the milestones while events load', (
      tester,
    ) async {
      final fetch = Completer<List<IdolTimelineEntry>>();
      await _pump(
        tester,
        scores: _scores(
          milestones: [
            {'id': 'm1', 'label': 'Read 100 annual reports', 'hit_by_age': 22},
          ],
        ),
        timeline: () => fetch.future,
      );
      expect(_card('milestone-m1'), findsOneWidget);
      expect(find.byKey(const ValueKey('record-events-loading')), findsOne);
      expect(find.text('Nothing here yet'), findsNothing);
      fetch.complete(const []);
      await _settle(tester, 1200);
      expect(find.textContaining('Read The Intelligent Investor'), findsOne);
    });

    testWidgets('nothing at all while loading shows only the loading card', (
      tester,
    ) async {
      final fetch = Completer<List<IdolTimelineEntry>>();
      await _pump(tester, timeline: () => fetch.future);
      expect(find.byKey(const ValueKey('record-events-loading')), findsOne);
      expect(find.text('Nothing here yet'), findsNothing);
      fetch.complete(const []);
      await _settle(tester, 1200);
      expect(find.byKey(const ValueKey('record-events-loading')), findsNothing);
    });

    testWidgets('a fetch that takes too long falls back to the ledger', (
      tester,
    ) async {
      final never = Completer<List<IdolTimelineEntry>>();
      final sessions = _Sessions(() => never.future);
      await _pump(tester, sessions: sessions);
      expect(sessions.calls, 1);
      expect(find.byKey(const ValueKey('record-events-loading')), findsOne);
      expect(
        find.textContaining('Read The Intelligent Investor'),
        findsNothing,
      );

      await tester.pump(idolTimelineTimeout);
      await _settle(tester, 1200);
      expect(find.byKey(const ValueKey('record-events-loading')), findsNothing);
      expect(find.textContaining('Read The Intelligent Investor'), findsOne);
    });

    testWidgets('a refresh keeps the mentor’s side until the new result', (
      tester,
    ) async {
      final answers = [
        Completer<List<IdolTimelineEntry>>(),
        Completer<List<IdolTimelineEntry>>(),
      ];
      var call = 0;
      await _pump(tester, timeline: () => answers[call++].future);
      answers[0].complete(events);
      await _settle(tester, 1200);
      expect(_card('timeline-e1'), findsOneWidget);

      // The Mentor screen's "Try again" invalidates the shared provider.
      ProviderScope.containerOf(
        tester.element(find.byType(CmpysRecordScreen)),
      ).invalidate(idolTimelineProvider('Warren Buffett'));
      await _settle(tester, 600);
      expect(call, 2);
      expect(_card('timeline-e1'), findsOneWidget);
      expect(find.byKey(const ValueKey('record-events-loading')), findsNothing);

      answers[1].complete(const [
        IdolTimelineEntry(age: 20, text: 'Studies under Graham', id: 'n1'),
      ]);
      await _settle(tester, 1200);
      expect(_card('timeline-e1'), findsNothing);
      expect(_card('timeline-n1'), findsOneWidget);
    });

    testWidgets(
      'a loaded timeline is kept for a while; an invalidate refetches',
      (tester) async {
        final sessions = _Sessions(() async => events);
        final container = ProviderContainer(
          overrides: [sessionRepositoryProvider.overrideWithValue(sessions)],
        );
        final provider = idolTimelineProvider('Warren Buffett');
        Future<List<IdolTimelineEntry>?> open() async {
          final sub = container.listen(provider, (_, _) {});
          await tester.pump();
          final value = sub.read().valueOrNull;
          sub.close();
          await tester.pump();
          return value;
        }

        expect(await open(), hasLength(events.length));
        expect(sessions.calls, 1);
        // Reopened with no listener in between: served from the cache.
        expect(await open(), hasLength(events.length));
        expect(sessions.calls, 1);
        // "Try again" (an invalidate) always fetches.
        container.invalidate(provider);
        await open();
        expect(sessions.calls, 2);
        // After the cache window, the next open fetches again.
        await tester.pump(idolTimelineCacheFor + const Duration(seconds: 1));
        await tester.pump();
        await open();
        expect(sessions.calls, 3);
        container.dispose();
      },
    );
  });

  testWidgets('the full ledger shows when your age is unknown', (tester) async {
    await _pump(tester, age: 0);
    expect(find.textContaining('Buffett Partnership'), findsOneWidget); // 25
    expect(find.textContaining('Net worth'), findsOneWidget); // 26
    // No age pill is "now".
    final pill = tester.widget<Container>(
      find.byKey(const ValueKey('record-age-24')),
    );
    expect((pill.decoration! as BoxDecoration).color, AppColors.paper2);
  });

  testWidgets('timeline semantics: groups, headers and card labels', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    await _pump(
      tester,
      wins: [
        _win('w-now', 'Built a DCF from scratch', dim: 'practice'),
        _win('w-zero', 'Opened a brokerage account', age: 0),
      ],
      milestones: const {'m1': true},
      scores: _scores(
        milestones: [
          {'id': 'm1', 'label': 'Read 100 annual reports', 'hit_by_age': 22},
        ],
      ),
    );

    expect(
      tester.getSemantics(_card('w-now')),
      matchesSemantics(
        label: 'Your win, age 24: Built a DCF from scratch. Practice.',
        isButton: true,
        hasEnabledState: true,
        isEnabled: true,
        isFocusable: true,
        hasTapAction: true,
        hasFocusAction: true,
      ),
    );
    expect(
      tester.getSemantics(_card('milestone-m1')).label,
      'Buffett’s milestone, age 22: Read 100 annual reports. Claimed.',
    );
    expect(
      tester.getSemantics(_card('w-zero')).label,
      'Your win, undated: Opened a brokerage account. Knowledge.',
    );

    // Each age is its own container, headed by its pill.
    final now = find.bySemanticsLabel('Age 24, your age now');
    expect(now, findsOneWidget);
    expect(tester.getSemantics(now).flagsCollection.isHeader, isTrue);
    expect(find.bySemanticsLabel('Age 22'), findsOneWidget);
    expect(find.bySemanticsLabel('Undated'), findsOneWidget);

    List<String> labels(String key) {
      final out = <String>[];
      void visit(SemanticsNode node) {
        if (node.label.isNotEmpty) out.add(node.label);
        node.visitChildren((child) {
          visit(child);
          return true;
        });
      }

      visit(tester.getSemantics(find.byKey(ValueKey('record-group-$key'))));
      return out;
    }

    expect(labels('24'), [
      'Age 24, your age now',
      'Your win, age 24: Built a DCF from scratch. Practice.',
      'Buffett’s milestone, age 24: Hired by Graham-Newman in New York — '
          'the only job he ever wanted.',
    ]);
    expect(labels('22'), contains('Age 22'));
    expect(labels('22'), isNot(contains('Age 24, your age now')));
    handle.dispose();
  });

  testWidgets('a narrow screen uses one column that still names each side', (
    tester,
  ) async {
    await _pump(
      tester,
      size: const Size(320, 2400),
      wins: [_win('w-now', 'Built a DCF', dim: 'practice')],
    );
    // 320 − 40 gutter − 24 offset, instead of 126 in two columns.
    expect(tester.getSize(_card('w-now')).width, 256);
    expect(_inCard('w-now', find.text('You')), findsOneWidget);
    final ledger = _card('ledger-buffett-0');
    expect(tester.getSize(ledger).width, 256);
    expect(_inCard('ledger-buffett-0', find.text('Buffett')), findsOneWidget);
    expect(
      tester.getTopLeft(ledger).dx,
      greaterThan(tester.getTopLeft(_card('w-now')).dx),
    );
  });

  testWidgets('large text uses one column too', (tester) async {
    await _pump(
      tester,
      textScale: 1.5,
      wins: [_win('w-now', 'Built a DCF', dim: 'practice')],
    );
    expect(tester.getSize(_card('w-now')).width, 390 - 40 - 24);
    expect(_inCard('w-now', find.text('You')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('backing out of the reassess before it ends commits nothing', (
    tester,
  ) async {
    final store = await _pump(
      tester,
      wins: [_win('w1', 'Read a full filing', assessed: false)],
    );
    const banner = '1 new entry waiting. Reassess on this device';
    await tester.tap(find.text(banner));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('Reviewing your new entries'), findsOneWidget);

    await tester.binding.handlePopRoute();
    await tester.pump();
    await tester.pump(const Duration(seconds: 3));
    expect(find.byType(ReassessOverlay), findsNothing);
    expect(store.state.pendingWins(), hasLength(1));
    expect(find.text(banner), findsOneWidget);
  });

  testWidgets('a double tap on the banner opens one overlay', (tester) async {
    final store = await _pump(
      tester,
      wins: [_win('w1', 'Read a full filing', assessed: false)],
    );
    final banner = find.byKey(CmpysRecordScreen.bannerKey);
    // Two activations before a frame (a fast double tap, or a screen
    // reader's) push a single overlay.
    final onTap = tester.widget<V3Pressable>(banner).onTap!;
    onTap();
    onTap();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.byType(ReassessOverlay), findsOneWidget);

    await tester.pump(const Duration(milliseconds: 2300));
    await tester.pump();
    // "Entries reviewed" is announced.
    final done = find.ancestor(
      of: find.text('Entries reviewed'),
      matching: find.byWidgetPredicate(
        (w) => w is Semantics && w.properties.liveRegion == true,
      ),
    );
    expect(done, findsOneWidget);
    await tester.tap(find.widgetWithText(V3Button, 'Done'));
    await _settle(tester, 800);
    expect(store.state.pendingWins(), isEmpty);

    // Closed, the banner can open it again for a new entry.
    store.addWin(title: 'Another', dim: 'knowledge', age: 24);
    await _settle(tester, 300);
    await tester.tap(banner);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.byType(ReassessOverlay), findsOneWidget);
  });

  testWidgets('reduced motion: everything shows at once', (tester) async {
    final store = await _pump(
      tester,
      reduced: true,
      wins: [_win('w1', 'Read a full filing', assessed: false)],
    );
    expect(_card('w1'), findsOneWidget);
    await tester.tap(find.text('1 new entry waiting. Reassess on this device'));
    await tester.pump();
    // No fade: the overlay is there on the first frame.
    expect(find.text('Reviewing your new entries'), findsOneWidget);
    await tester.pump(ReassessOverlay.reviewDuration);
    await tester.pump();
    expect(find.text('Entries reviewed'), findsOneWidget);
    expect(store.state.pendingWins(), isEmpty);
    await tester.tap(find.widgetWithText(V3Button, 'Done'));
    await tester.pump();
    expect(find.byType(ReassessOverlay), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
