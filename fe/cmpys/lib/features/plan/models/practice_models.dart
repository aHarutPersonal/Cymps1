import 'package:intl/intl.dart';

import '../../../core/ui/v3/lesson_blocks/quick_check.dart'
    show checkNumberReadings;

/// The one number a typed practice answer means, spelled for the server, or
/// null when it is not a number ("", "-", "4.5.6").
///
/// Readings follow the tutorial's quick check ([checkNumberReadings]):
/// "4,5" and "4.5" are 4.5, "1,250.5" and "1.250,5" are 1250.5, and
/// "1,250,000" is 1250000. Only "1,250" (a 1–3 digit lead, one comma, three
/// digits) is ambiguous; the device's [decimalSeparator] settles it: with "."
/// the comma groups thousands (1250), with "," it is the decimal (1.25). The
/// result is a plain decimal with no separator to misread, so the server
/// (`_number_feedback` in `practice/contracts.py`) parses it as shown.
String? practiceNumberWire(String input, {String decimalSeparator = '.'}) {
  final readings = checkNumberReadings(input);
  if (readings.isEmpty) return null;
  // An ambiguous "1,250" reads [1250, 1.25]: thousands first, decimal last.
  final value = decimalSeparator == ',' ? readings.last : readings.first;
  if (value == value.roundToDouble() && value.abs() < 1e15) {
    return value.toInt().toString();
  }
  return value.toString();
}

class PracticeField {
  PracticeField.fromJson(Map<String, dynamic> j)
    : id = j['id'] as String,
      label = j['label'] as String,
      kind = j['kind'] as String,
      unit = j['unit'] as String? ?? '',
      prefix = j['prefix'] as String? ?? '',
      rubricCriterion = _blankToNull(j['rubric_criterion'] as String?),
      choices = (j['choices'] as List? ?? []).cast<Map<String, dynamic>>(),
      criteria = (j['criteria'] as List? ?? []).cast<String>();
  final String id, label, kind, unit;

  /// Shown before a number ("$"); empty when the field has none. Optional on
  /// the wire (A8): a missing key means no prefix.
  final String prefix;

  /// The criterion this field is graded against; null on legacy fields.
  final String? rubricCriterion;
  final List<Map<String, dynamic>> choices;
  final List<String> criteria;

  /// The name of this field's row in the result panel: the rubric criterion,
  /// or the label when the field has none (the server's own fallback).
  String get criterion => rubricCriterion ?? label;

  bool get isNumber => kind == 'number';
  bool get isChoice => kind == 'choice';
  bool get isMultiChoice => kind == 'multi_choice';

  /// Free text, including any kind this build does not know yet.
  bool get isText => !isNumber && !isChoice && !isMultiChoice;

  List<String> get choiceIds => [for (final c in choices) c['id'] as String];

  /// The ids selected in a multi_choice answer (comma-joined on the wire).
  List<String> selectedIds(String raw) => [
    for (final part in raw.split(','))
      if (part.trim().isNotEmpty) part.trim(),
  ];

  /// A multi_choice answer spelled as the server stores it: choice order,
  /// de-duplicated, comma-joined without spaces. Ids naming no choice keep
  /// their relative order after the known ones (`canonical_multi_choice`).
  String canonicalMultiChoice(String raw) {
    final parts = selectedIds(raw);
    final known = [
      for (final id in choiceIds)
        if (parts.contains(id)) id,
    ];
    final unknown = <String>{
      for (final part in parts)
        if (!known.contains(part)) part,
    };
    return [...known, ...unknown].join(',');
  }

  /// Whether [raw] answers this field well enough to be checked: a number
  /// that parses, at least one selected choice, or non-blank text.
  bool isFilled(String raw, {String decimalSeparator = '.'}) {
    if (isNumber) {
      return practiceNumberWire(raw, decimalSeparator: decimalSeparator) !=
          null;
    }
    if (isMultiChoice) return selectedIds(raw).isNotEmpty;
    return raw.trim().isNotEmpty;
  }

  /// [raw] as it is sent and stored: a parsed number in plain decimal form
  /// (an unparseable draft is kept as typed; it cannot be submitted), a
  /// canonical multi_choice list, anything else unchanged.
  String wire(String raw, {String decimalSeparator = '.'}) {
    if (isNumber) {
      return practiceNumberWire(raw, decimalSeparator: decimalSeparator) ?? raw;
    }
    if (isMultiChoice) return canonicalMultiChoice(raw);
    return raw;
  }
}

/// [answers] (keyed "activity.field") as they go on the wire; see
/// [PracticeField.wire]. Keys naming no known field pass through unchanged.
Map<String, String> practiceWireAnswers(
  List<PracticeActivity> activities,
  Map<String, String> answers, {
  String decimalSeparator = '.',
}) {
  final fields = _fieldsByKey(activities);
  return {
    for (final e in answers.entries)
      e.key:
          fields[e.key]?.wire(e.value, decimalSeparator: decimalSeparator) ??
          e.value,
  };
}

/// [answers] with every multi_choice answer in the server's canonical
/// spelling; everything else, numbers included, exactly as given.
Map<String, String> canonicalMultiChoiceAnswers(
  List<PracticeActivity> activities,
  Map<String, String> answers,
) {
  final fields = _fieldsByKey(activities);
  return {
    for (final e in answers.entries)
      e.key: switch (fields[e.key]) {
        final f? when f.isMultiChoice => f.canonicalMultiChoice(e.value),
        _ => e.value,
      },
  };
}

Map<String, PracticeField> _fieldsByKey(List<PracticeActivity> activities) => {
  for (final a in activities)
    for (final f in a.fields) '${a.id}.${f.id}': f,
};

/// The decimal separator of [locale] ("en_US" → ".", "de_DE" → ","), from
/// intl's number symbols; "." when the locale is unknown. Any separator other
/// than a comma counts as ".".
String decimalSeparatorFor(String? locale) {
  try {
    final known = Intl.verifiedLocale(
      locale,
      NumberFormat.localeExists,
      onFailure: (_) => null,
    );
    if (known == null) return '.';
    return NumberFormat.decimalPattern(known).symbols.DECIMAL_SEP == ','
        ? ','
        : '.';
  } catch (_) {
    return '.';
  }
}

String? _blankToNull(String? value) =>
    value == null || value.trim().isEmpty ? null : value;

class PracticeActivity {
  PracticeActivity.fromJson(Map<String, dynamic> j)
    : id = j['id'] as String,
      title = j['title'] as String,
      kind = j['kind'] as String,
      instructions = j['instructions'] as String,
      fields = (j['fields'] as List)
          .map((f) => PracticeField.fromJson(f))
          .toList(),
      data = (j['data'] as List? ?? []).cast<Map<String, dynamic>>(),
      diagram = j['diagram'] as Map<String, dynamic>?,
      minutesMin = (j['minutes_min'] as num).toInt(),
      minutesMax = (j['minutes_max'] as num).toInt();
  final String id, title, kind, instructions;
  final List<PracticeField> fields;
  final List<Map<String, dynamic>> data;
  final Map<String, dynamic>? diagram;
  final int minutesMin, minutesMax;

  /// The new case the learner solves alone ("Independent" in the design).
  bool get isTransfer => kind == 'transfer';
}

class LessonPracticeState {
  LessonPracticeState.fromJson(Map<String, dynamic> j)
    : state = j['state'] as String,
      lessonVersion = j['lesson_version'] as String?,
      revision = (j['revision'] as num?)?.toInt() ?? 0,
      retryAfterSeconds = (j['retry_after_seconds'] as num?)?.toInt() ?? 0,
      title = (j['workbook'] as Map?)?['title'] as String? ?? 'Lesson practice',
      activities = ((j['workbook'] as Map?)?['activities'] as List? ?? [])
          .map((a) => PracticeActivity.fromJson(a))
          .toList(),
      answers = (j['answers'] as Map? ?? {}).cast<String, String>(),
      attempts = (j['attempts'] as List? ?? []).cast<Map<String, dynamic>>(),
      hints = (j['hints'] as List? ?? []).cast<Map<String, dynamic>>(),
      passed = (j['passed_activity_ids'] as List? ?? []).cast<String>(),
      evidenceStatus = (j['learning_evidence'] as Map?)?['status'] as String?,
      complete = j['complete'] == true,
      canRetry = j['can_retry_preparation'] != false,
      preparedAvailable = j['prepared_available'] == true;
  final String state, title;
  final String? evidenceStatus;
  final String? lessonVersion;
  final int revision, retryAfterSeconds;
  final List<PracticeActivity> activities;
  final Map<String, String> answers;
  final List<Map<String, dynamic>> attempts, hints;
  final List<String> passed;
  final bool complete, canRetry, preparedAvailable;

  /// The hint the server revealed for one field ([key] is "activity.field"),
  /// or null when it has not been asked for. The server records it, so
  /// "Hint used" survives a reload.
  String? fieldHint(String key) {
    for (final h in hints) {
      if (h['field_id'] == key) return h['content'] as String? ?? '';
    }
    return null;
  }

  /// This activity's attempts, oldest first.
  List<Map<String, dynamic>> attemptsFor(String activityId) => [
    for (final a in attempts)
      if (a['activity_id'] == activityId) a,
  ];
}
