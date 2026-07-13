import 'package:flutter_test/flutter_test.dart';
import 'package:cmpys/features/session/models/session_models.dart';

void main() {
  test('Session.fromJson reads comparisonScores map', () {
    final s = Session.fromJson({
      'id': 's1',
      'phase': 'completed',
      'user_age': 24,
      'user_interests': <String>[],
      'comparisonScores': {
        'dimensions': [
          {'id': 'capital', 'label': 'Capital at work', 'you': 30, 'idol': 70,
           'you_note': 'a', 'idol_note': 'b'}
        ],
        'milestones': [{'id': 'm1', 'label': 'Did a thing', 'hit_by_age': 22}],
      },
    });
    expect(s.comparisonScores?['dimensions'], isA<List>());
    expect((s.comparisonScores!['dimensions'] as List).first['id'], 'capital');
  });

  test('Session.fromJson tolerates missing comparisonScores', () {
    final s = Session.fromJson({
      'id': 's1', 'phase': 'intake', 'user_age': 0, 'user_interests': <String>[],
    });
    expect(s.comparisonScores, isNull);
  });

  test('Session.fromJson accepts snake-case comparison scores for compatibility',
      () {
    final s = Session.fromJson({
      'id': 's1',
      'phase': 'completed',
      'user_age': 24,
      'user_interests': <String>[],
      'comparison_scores': {
        'dimensions': [
          {'id': 'clarity', 'you': 40, 'idol': 80},
        ],
      },
    });

    expect((s.comparisonScores!['dimensions'] as List).first['id'], 'clarity');
    expect(s.toJson()['comparisonScores'], s.comparisonScores);
  });
}
