import 'package:flutter_test/flutter_test.dart';
import 'package:cmpys/features/cmpys/state/cmpys_store.dart';

void main() {
  test('dimsFromScores maps the raw map to CmpysDimension list', () {
    final dims = dimsFromScores({
      'version': 2,
      'methodology': 'like_for_like_evidence',
      'dimensions': [
        {
          'id': 'capital',
          'label': 'Capital at work',
          'you': 30,
          'idol': 70,
          'status': 'comparable',
          'comparison_basis': 'personal invested assets',
          'you_evidence': 'self_reported',
          'idol_evidence': 'verified',
          'you_note': 'small portfolio',
          'idol_note': 'compounded',
        },
      ],
    });
    expect(dims, isNotNull);
    expect(dims!.first.id, 'capital');
    expect(dims.first.you, 30);
    expect(dims.first.idolNote, 'compounded');
    expect(dims.first.isComparable, isTrue);
  });

  test('dimsFromScores returns null for null/empty', () {
    expect(dimsFromScores(null), isNull);
    expect(dimsFromScores({'dimensions': []}), isNull);
  });

  test('legacy percentage inputs are hidden until v2 regeneration', () {
    expect(
      dimsFromScores({
        'dimensions': [
          {'id': 'capital', 'you': 45, 'idol': 90},
        ],
      }),
      isNull,
    );
  });

  test('different-basis dimensions preserve evidence but have no score', () {
    final dims = dimsFromScores({
      'version': 2,
      'methodology': 'like_for_like_evidence',
      'dimensions': [
        {
          'id': 'capital',
          'label': 'Capital at work',
          'you': null,
          'idol': null,
          'status': 'different_basis',
          'comparison_basis': 'personal savings versus business capital raised',
          'you_note': r'$50k saved',
          'idol_note': r'$100m IPO proceeds',
        },
      ],
    });

    expect(dims, isNotNull);
    expect(dims!.single.isComparable, isFalse);
    expect(dims.single.comparisonBasis, contains('business capital'));
  });

  test('milestonesFromScores maps to CmpysMilestone with stable ids', () {
    final ms = milestonesFromScores({
      'version': 2,
      'methodology': 'like_for_like_evidence',
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
