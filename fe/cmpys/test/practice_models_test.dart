import 'package:cmpys/features/plan/models/practice_models.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, dynamic> _activity(List<Map<String, dynamic>> fields) => {
  'id': 'guided',
  'title': 'Owner earnings',
  'kind': 'practice',
  'instructions': 'Work out what the owners really earned this year.',
  'minutes_min': 4,
  'minutes_max': 8,
  'fields': fields,
};

const _multi = {
  'id': 'lines',
  'label': 'Which lines keep the business as it is?',
  'kind': 'multi_choice',
  'unit': '',
  'choices': [
    {'id': 'warehouse', 'label': 'New warehouse'},
    {'id': 'line', 'label': 'Production line'},
    {'id': 'stores', 'label': 'Store refits'},
  ],
  'rubric_criterion': null,
};

void main() {
  group('A8 public field wire', () {
    test('number field with prefix, unit and rubric criterion', () {
      final f = PracticeField.fromJson({
        'id': 'oe',
        'label': 'Owner earnings',
        'kind': 'number',
        'unit': 'm',
        'prefix': r'$',
        'choices': <Map<String, dynamic>>[],
        'rubric_criterion': 'Owner earnings computed from the figures',
      });
      expect(f.isNumber, isTrue);
      expect(f.prefix, r'$');
      expect(f.unit, 'm');
      expect(f.rubricCriterion, 'Owner earnings computed from the figures');
      expect(f.criterion, 'Owner earnings computed from the figures');
    });

    test('a missing prefix means none; a null criterion falls back to the '
        'label', () {
      final f = PracticeField.fromJson({
        'id': 'oe',
        'label': 'Owner earnings',
        'kind': 'number',
        'unit': '',
        'choices': <Map<String, dynamic>>[],
        'rubric_criterion': null,
      });
      expect(f.prefix, '');
      expect(f.rubricCriterion, isNull);
      expect(f.criterion, 'Owner earnings');
    });

    test('legacy field without the v3 keys still parses', () {
      final f = PracticeField.fromJson({
        'id': 'why',
        'label': 'Why?',
        'kind': 'text',
      });
      expect(f.prefix, '');
      expect(f.criterion, 'Why?');
      expect(f.isText, isTrue);
    });

    test('an unknown kind is treated as free text', () {
      final f = PracticeField.fromJson({
        'id': 'x',
        'label': 'Draw it',
        'kind': 'sketch',
      });
      expect(f.isText, isTrue);
    });

    test('multi_choice answers use the canonical spelling', () {
      final f = PracticeField.fromJson(_multi);
      expect(f.isMultiChoice, isTrue);
      expect(
        f.canonicalMultiChoice('stores, warehouse,stores'),
        'warehouse,stores',
      );
      // Unknown ids keep their relative order after the known ones.
      expect(f.canonicalMultiChoice('zeta,line,alpha,zeta'), 'line,zeta,alpha');
      expect(f.canonicalMultiChoice(' , ,'), '');
      expect(f.isFilled(' , ,'), isFalse);
      expect(f.isFilled('line'), isTrue);
      expect(f.selectedIds('line, stores'), ['line', 'stores']);
    });

    test('field hints are read from hints[] by field_id', () {
      final state = LessonPracticeState.fromJson({
        'state': 'ready',
        'workbook': {
          'title': 'Owner earnings',
          'activities': [
            _activity([_multi]),
          ],
        },
        'hints': [
          {'activity_id': 'guided', 'kind': 'hint', 'content': 'Activity.'},
          {
            'activity_id': 'guided',
            'kind': 'field_hint',
            'field_id': 'guided.lines',
            'content': 'Maintenance keeps the business as it is.',
          },
        ],
      });
      expect(
        state.fieldHint('guided.lines'),
        'Maintenance keeps the business as it is.',
      );
      expect(state.fieldHint('guided.other'), isNull);
    });
  });

  group('typed numbers (Review Focus 2)', () {
    test('comma decimal parses', () {
      expect(practiceNumberWire('4,5'), '4.5');
      expect(practiceNumberWire(' 4.5 '), '4.5');
      expect(practiceNumberWire('−3'), '-3');
      expect(practiceNumberWire('100'), '100');
      expect(practiceNumberWire('0,500'), '0.5');
    });

    test('grouped thousands lose their separators', () {
      expect(practiceNumberWire('1,250.5'), '1250.5');
      expect(practiceNumberWire('1.250,5'), '1250.5');
      expect(practiceNumberWire('1,250,000'), '1250000');
    });

    test('an ambiguous "1,250" follows the device decimal separator', () {
      // A "." locale groups thousands with the comma; a "," locale doesn't.
      expect(practiceNumberWire('1,250'), '1250');
      expect(practiceNumberWire('1,250', decimalSeparator: '.'), '1250');
      expect(practiceNumberWire('1,250', decimalSeparator: ','), '1.25');
      // Unambiguous input reads the same everywhere.
      expect(practiceNumberWire('4,5', decimalSeparator: '.'), '4.5');
      expect(practiceNumberWire('1.250,5', decimalSeparator: '.'), '1250.5');
      expect(practiceNumberWire('1,250.5', decimalSeparator: ','), '1250.5');
    });

    test('decimal separators come from intl number symbols', () {
      expect(decimalSeparatorFor('en_US'), '.');
      expect(decimalSeparatorFor('en_GB'), '.');
      expect(decimalSeparatorFor('de_DE'), ',');
      expect(decimalSeparatorFor('fr'), ',');
      expect(decimalSeparatorFor('zz_ZZ'), '.');
      expect(decimalSeparatorFor(null), '.');
    });

    test('blank and non-numbers are never sent as numbers', () {
      for (final bad in ['', ' ', '-', '4.5.6', 'abc', ',']) {
        expect(practiceNumberWire(bad), isNull, reason: bad);
      }
    });

    test('a number field is filled only when it parses', () {
      final f = PracticeField.fromJson({
        'id': 'oe',
        'label': 'Owner earnings',
        'kind': 'number',
      });
      expect(f.isFilled('-'), isFalse);
      expect(f.isFilled('4,5'), isTrue);
      expect(f.wire('4,5'), '4.5');
      // An unparseable draft is kept as typed; it cannot be submitted.
      expect(f.wire('-'), '-');
    });

    test('wire answers normalise numbers and multi selections only', () {
      final activity = PracticeActivity.fromJson(
        _activity([
          {'id': 'oe', 'label': 'Owner earnings', 'kind': 'number'},
          _multi,
          {'id': 'why', 'label': 'Why?', 'kind': 'text'},
        ]),
      );
      expect(
        practiceWireAnswers(
          [activity],
          {
            'guided.oe': '4,5',
            'guided.lines': 'stores,warehouse',
            'guided.why': ' Because 4,5 ',
            'other.key': 'kept',
          },
        ),
        {
          'guided.oe': '4.5',
          'guided.lines': 'warehouse,stores',
          'guided.why': ' Because 4,5 ',
          'other.key': 'kept',
        },
      );
    });
  });
}
