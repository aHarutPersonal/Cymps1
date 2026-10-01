class PracticeField {
  PracticeField.fromJson(Map<String, dynamic> j)
    : id = j['id'] as String,
      label = j['label'] as String,
      kind = j['kind'] as String,
      unit = j['unit'] as String? ?? '',
      choices = (j['choices'] as List? ?? []).cast<Map<String, dynamic>>(),
      criteria = (j['criteria'] as List? ?? []).cast<String>();
  final String id, label, kind, unit;
  final List<Map<String, dynamic>> choices;
  final List<String> criteria;
}

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
}

class LessonPracticeState {
  LessonPracticeState.fromJson(Map<String, dynamic> j)
    : state = j['state'] as String,
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
  final int revision, retryAfterSeconds;
  final List<PracticeActivity> activities;
  final Map<String, String> answers;
  final List<Map<String, dynamic>> attempts, hints;
  final List<String> passed;
  final bool complete, canRetry, preparedAvailable;
}
