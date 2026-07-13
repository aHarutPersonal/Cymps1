import 'package:cmpys/features/cmpys/state/cmpys_store.dart';
import 'package:cmpys/features/session/models/session_models.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

Session _session(String id, {Map<String, dynamic>? scores}) => Session(
      id: id,
      phase: SessionPhase.completed,
      userAge: 24,
      userFinancialStatus: '',
      userInterests: const [],
      selectedIdol: const SelectedIdolInfo(id: 'idol-1', name: 'Great'),
      comparisonOutput: 'Generated verdict',
      blueprintOutput: 'Generated blueprint',
      comparisonScores: scores,
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('missing generated scores never fall back to demo comparison data', () {
    final state = CmpysState.initial();

    expect(state.liveDims(), isEmpty);
    expect(state.liveMilestones(), isEmpty);
  });

  test('switching sessions clears prior structured comparison scores', () async {
    final store = CmpysStore();
    await Future<void>.delayed(Duration.zero);
    store.syncFromSession(_session('first', scores: {
      'dimensions': [
        {
          'id': 'clarity',
          'label': 'Clarity',
          'you': 60,
          'idol': 70,
          'you_note': 'Generated user note',
          'idol_note': 'Generated mentor note',
        },
      ],
    }));
    expect(store.state.liveDims(), hasLength(1));

    store.syncFromSession(_session('second'));

    expect(store.state.liveDims(), isEmpty);
    store.dispose();
  });

  test('generated comparison scores survive a local store restart', () async {
    final store = CmpysStore();
    await store.ready;
    store.syncFromSession(_session('persisted', scores: {
      'dimensions': [
        {
          'id': 'clarity',
          'label': 'Clarity',
          'you': 55,
          'idol': 75,
        },
      ],
      'milestones': <Map<String, dynamic>>[],
    }));
    await Future<void>.delayed(const Duration(milliseconds: 350));
    store.dispose();

    final reloaded = CmpysStore();
    await reloaded.ready;
    expect(reloaded.state.sessionId, 'persisted');
    expect(reloaded.state.liveDims(), hasLength(1));
    expect(reloaded.state.liveDims().single.you, 55);
    reloaded.dispose();
  });
}
