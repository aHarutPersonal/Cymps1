import 'package:flutter_test/flutter_test.dart';
import 'package:cmpys/features/cmpys/state/cmpys_store.dart';

void main() {
  test('dimsFromScores maps the raw map to CmpysDimension list', () {
    final dims = dimsFromScores({
      'dimensions': [
        {'id': 'capital', 'label': 'Capital at work', 'you': 30, 'idol': 70,
         'you_note': 'small savings', 'idol_note': 'compounded'},
      ],
    });
    expect(dims, isNotNull);
    expect(dims!.first.id, 'capital');
    expect(dims.first.you, 30);
    expect(dims.first.idolNote, 'compounded');
  });

  test('dimsFromScores returns null for null/empty', () {
    expect(dimsFromScores(null), isNull);
    expect(dimsFromScores({'dimensions': []}), isNull);
  });

  test('milestonesFromScores maps to CmpysMilestone with stable ids', () {
    final ms = milestonesFromScores({
      'milestones': [
        {'id': 'm1', 'label': 'Wrote a philosophy'},
        {'label': 'Saved a base'},
      ],
    });
    expect(ms, isNotNull);
    expect(ms!.first.id, 'm1');
    expect(ms.first.label, 'Wrote a philosophy');
    expect(ms[1].id, 'm2'); // positional fallback
  });
}
