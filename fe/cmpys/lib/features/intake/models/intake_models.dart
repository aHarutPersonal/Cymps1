import 'package:freezed_annotation/freezed_annotation.dart';

part 'intake_models.freezed.dart';

/// Question types for intake questions.
enum IntakeQuestionType {
  @JsonValue('text')
  text,
  @JsonValue('number')
  number,
  @JsonValue('date')
  date,
  @JsonValue('select')
  select,
  @JsonValue('multiselect')
  multiselect,
  @JsonValue('boolean')
  boolean,
  @JsonValue('scale')
  scale,
}

/// Validation rules for intake questions.
@freezed
class IntakeValidation with _$IntakeValidation {
  const IntakeValidation._();

  const factory IntakeValidation({
    int? minLength,
    int? maxLength,
    int? min,
    int? max,
    String? pattern,
    String? errorMessage,
  }) = _IntakeValidation;

  factory IntakeValidation.fromJson(Map<String, dynamic> json) {
    return IntakeValidation(
      minLength: _parseInt(json['minLength'] ?? json['min_length']),
      maxLength: _parseInt(json['maxLength'] ?? json['max_length']),
      min: _parseInt(json['min']),
      max: _parseInt(json['max']),
      pattern: json['pattern']?.toString(),
      errorMessage: (json['errorMessage'] ?? json['error_message'])?.toString(),
    );
  }

  Map<String, dynamic> toJson() => {
    if (minLength != null) 'minLength': minLength,
    if (maxLength != null) 'maxLength': maxLength,
    if (min != null) 'min': min,
    if (max != null) 'max': max,
    if (pattern != null) 'pattern': pattern,
    if (errorMessage != null) 'errorMessage': errorMessage,
  };

  static int? _parseInt(dynamic value) {
    if (value == null) return null;
    if (value is int) return value;
    if (value is num) return value.toInt();
    if (value is String) return int.tryParse(value);
    return null;
  }
}

/// Option for select/multiselect questions.
@freezed
class IntakeOption with _$IntakeOption {
  const IntakeOption._();

  const factory IntakeOption({
    required String value,
    required String label,
    String? description,
    String? icon,
  }) = _IntakeOption;

  factory IntakeOption.fromJson(Map<String, dynamic> json) {
    return IntakeOption(
      value: json['value']?.toString() ?? '',
      label: json['label']?.toString() ?? '',
      description: json['description']?.toString(),
      icon: json['icon']?.toString(),
    );
  }

  Map<String, dynamic> toJson() => {
    'value': value,
    'label': label,
    if (description != null) 'description': description,
    if (icon != null) 'icon': icon,
  };
}

/// A single intake question.
@freezed
class IntakeQuestion with _$IntakeQuestion {
  const IntakeQuestion._();

  const factory IntakeQuestion({
    /// Unique question identifier.
    required String id,

    /// Short title for the question.
    required String title,

    /// The full prompt/question text to display.
    required String prompt,

    /// Question type (text, number, select, etc.).
    required String type,

    /// Whether an answer is required.
    @Default(true) bool isRequired,

    /// Options for select/multiselect questions.
    @Default([]) List<IntakeOption> options,

    /// Placeholder text for input fields.
    String? placeholder,

    /// Validation rules.
    IntakeValidation? validation,

    /// Category for grouping questions.
    String? category,

    /// Hint for mapping answer to profile field.
    String? mappingHint,
  }) = _IntakeQuestion;

  factory IntakeQuestion.fromJson(Map<String, dynamic> json) {
    return IntakeQuestion(
      id: json['id']?.toString() ?? '',
      title: json['title']?.toString() ?? '',
      prompt: json['prompt']?.toString() ?? '',
      type: json['type']?.toString() ?? 'text',
      isRequired: _parseBool(json['required'] ?? json['isRequired']) ?? true,
      options: _parseOptions(json['options']),
      placeholder: json['placeholder']?.toString(),
      validation: json['validation'] != null
          ? IntakeValidation.fromJson(
              json['validation'] as Map<String, dynamic>,
            )
          : null,
      category: json['category']?.toString(),
      mappingHint: (json['mappingHint'] ?? json['mapping_hint'])?.toString(),
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    'prompt': prompt,
    'type': type,
    'required': isRequired,
    'options': options.map((o) => o.toJson()).toList(),
    if (placeholder != null) 'placeholder': placeholder,
    if (validation != null) 'validation': validation!.toJson(),
    if (category != null) 'category': category,
    if (mappingHint != null) 'mappingHint': mappingHint,
  };

  /// Get the question type enum.
  IntakeQuestionType get questionType {
    switch (type.toLowerCase()) {
      case 'number':
        return IntakeQuestionType.number;
      case 'date':
        return IntakeQuestionType.date;
      case 'select':
        return IntakeQuestionType.select;
      case 'multiselect':
        return IntakeQuestionType.multiselect;
      case 'boolean':
        return IntakeQuestionType.boolean;
      case 'scale':
        return IntakeQuestionType.scale;
      default:
        return IntakeQuestionType.text;
    }
  }

  String get chatEyebrow {
    final value = category?.trim();
    if (value == null || value.isEmpty) return 'ACHIEVEMENT CHECK';
    return value.toUpperCase().replaceAll('_', ' ');
  }

  String get chatPrompt {
    final value = prompt.trim();
    return value.isNotEmpty ? value : title.trim();
  }

  String get answerHint {
    final value = placeholder?.trim();
    if (value != null && value.isNotEmpty) return value;
    if (type.toLowerCase() == 'multiline') {
      return 'Share the situation, action, and result...';
    }
    return 'Type your answer...';
  }

  static bool? _parseBool(dynamic value) {
    if (value == null) return null;
    if (value is bool) return value;
    if (value is String) return value.toLowerCase() == 'true';
    if (value is num) return value != 0;
    return null;
  }

  static List<IntakeOption> _parseOptions(dynamic value) {
    if (value == null) return [];
    if (value is! List) return [];
    return value
        .whereType<Map<String, dynamic>>()
        .map((e) => IntakeOption.fromJson(e))
        .toList();
  }
}

/// An answer to an intake question.
@freezed
class IntakeAnswer with _$IntakeAnswer {
  const IntakeAnswer._();

  const factory IntakeAnswer({
    /// Question ID this answer is for.
    required String questionId,

    /// The answer value (can be string, number, list, etc.).
    required dynamic answer,

    /// When the answer was submitted.
    DateTime? answeredAt,
  }) = _IntakeAnswer;

  factory IntakeAnswer.fromJson(Map<String, dynamic> json) {
    return IntakeAnswer(
      questionId: (json['questionId'] ?? json['question_id'])?.toString() ?? '',
      answer: json['answer'],
      answeredAt: _parseDate(json['answeredAt'] ?? json['answered_at']),
    );
  }

  Map<String, dynamic> toJson() => {
    'questionId': questionId,
    'answer': answer,
    if (answeredAt != null) 'answeredAt': answeredAt!.toIso8601String(),
  };

  static DateTime? _parseDate(dynamic value) {
    if (value == null) return null;
    if (value is DateTime) return value;
    if (value is String) return DateTime.tryParse(value);
    return null;
  }
}

/// Response from starting an intake session.
@freezed
class IntakeStartResponse with _$IntakeStartResponse {
  const IntakeStartResponse._();

  const factory IntakeStartResponse({
    /// Session ID for this intake flow.
    required String sessionId,

    /// List of questions to answer.
    required List<IntakeQuestion> questions,
  }) = _IntakeStartResponse;

  factory IntakeStartResponse.fromJson(Map<String, dynamic> json) {
    return IntakeStartResponse(
      sessionId: (json['sessionId'] ?? json['session_id'])?.toString() ?? '',
      questions: _parseQuestions(json['questions']),
    );
  }

  Map<String, dynamic> toJson() => {
    'sessionId': sessionId,
    'questions': questions.map((q) => q.toJson()).toList(),
  };

  static List<IntakeQuestion> _parseQuestions(dynamic value) {
    if (value == null) return [];
    if (value is! List) return [];
    return value
        .whereType<Map<String, dynamic>>()
        .map((e) => IntakeQuestion.fromJson(e))
        .toList();
  }
}

/// Request body for submitting an answer.
@freezed
class IntakeAnswerRequest with _$IntakeAnswerRequest {
  const IntakeAnswerRequest._();

  const factory IntakeAnswerRequest({
    /// Question ID being answered.
    required String questionId,

    /// The answer value.
    required dynamic answer,
  }) = _IntakeAnswerRequest;

  factory IntakeAnswerRequest.fromJson(Map<String, dynamic> json) {
    return IntakeAnswerRequest(
      questionId: (json['questionId'] ?? json['question_id'])?.toString() ?? '',
      answer: json['answer'],
    );
  }

  Map<String, dynamic> toJson() => {'questionId': questionId, 'answer': answer};
}

/// Status of an intake session.
enum IntakeSessionStatus {
  @JsonValue('in_progress')
  inProgress,
  @JsonValue('completed')
  completed,
  @JsonValue('abandoned')
  abandoned,
}

/// Response containing the full intake session state.
@freezed
class IntakeSessionResponse with _$IntakeSessionResponse {
  const IntakeSessionResponse._();

  const factory IntakeSessionResponse({
    /// Session ID.
    required String sessionId,

    /// Current status of the session.
    required String status,

    /// All questions in this intake.
    required List<IntakeQuestion> questions,

    /// Answers submitted so far.
    required List<IntakeAnswer> answers,

    /// Idol ID if associated.
    String? idolId,

    /// Target age if set.
    int? targetAge,

    /// When the session was created.
    DateTime? createdAt,

    /// When the session was last updated.
    DateTime? updatedAt,
  }) = _IntakeSessionResponse;

  factory IntakeSessionResponse.fromJson(Map<String, dynamic> json) {
    return IntakeSessionResponse(
      sessionId: (json['sessionId'] ?? json['session_id'])?.toString() ?? '',
      status: json['status']?.toString() ?? 'in_progress',
      questions: _parseQuestions(json['questions']),
      answers: _parseAnswers(json['answers']),
      idolId: (json['idolId'] ?? json['idol_id'])?.toString(),
      targetAge: _parseInt(json['targetAge'] ?? json['target_age']),
      createdAt: _parseDate(json['createdAt'] ?? json['created_at']),
      updatedAt: _parseDate(json['updatedAt'] ?? json['updated_at']),
    );
  }

  Map<String, dynamic> toJson() => {
    'sessionId': sessionId,
    'status': status,
    'questions': questions.map((q) => q.toJson()).toList(),
    'answers': answers.map((a) => a.toJson()).toList(),
    if (idolId != null) 'idolId': idolId,
    if (targetAge != null) 'targetAge': targetAge,
    if (createdAt != null) 'createdAt': createdAt!.toIso8601String(),
    if (updatedAt != null) 'updatedAt': updatedAt!.toIso8601String(),
  };

  /// Get session status enum.
  IntakeSessionStatus get sessionStatus {
    switch (status.toLowerCase()) {
      case 'completed':
        return IntakeSessionStatus.completed;
      case 'abandoned':
        return IntakeSessionStatus.abandoned;
      default:
        return IntakeSessionStatus.inProgress;
    }
  }

  /// Check if session is still in progress.
  bool get isInProgress => sessionStatus == IntakeSessionStatus.inProgress;

  /// Check if session is completed.
  bool get isCompleted => sessionStatus == IntakeSessionStatus.completed;

  /// Get unanswered questions.
  List<IntakeQuestion> get unansweredQuestions {
    final answeredIds = answers.map((a) => a.questionId).toSet();
    return questions.where((q) => !answeredIds.contains(q.id)).toList();
  }

  /// Get the next unanswered question.
  IntakeQuestion? get nextQuestion {
    final unanswered = unansweredQuestions;
    return unanswered.isNotEmpty ? unanswered.first : null;
  }

  /// Progress percentage (0.0 - 1.0).
  double get progress {
    if (questions.isEmpty) return 0.0;
    return answers.length / questions.length;
  }

  static List<IntakeQuestion> _parseQuestions(dynamic value) {
    if (value == null) return [];
    if (value is! List) return [];
    return value
        .whereType<Map<String, dynamic>>()
        .map((e) => IntakeQuestion.fromJson(e))
        .toList();
  }

  static List<IntakeAnswer> _parseAnswers(dynamic value) {
    if (value == null) return [];
    if (value is! List) return [];
    return value
        .whereType<Map<String, dynamic>>()
        .map((e) => IntakeAnswer.fromJson(e))
        .toList();
  }

  static int? _parseInt(dynamic value) {
    if (value == null) return null;
    if (value is int) return value;
    if (value is num) return value.toInt();
    if (value is String) return int.tryParse(value);
    return null;
  }

  static DateTime? _parseDate(dynamic value) {
    if (value == null) return null;
    if (value is DateTime) return value;
    if (value is String) return DateTime.tryParse(value);
    return null;
  }
}

/// Response from finishing an intake session.
@freezed
class FinishIntakeResponse with _$FinishIntakeResponse {
  const FinishIntakeResponse._();

  const factory FinishIntakeResponse({
    /// Job ID for background processing.
    required String jobId,

    /// Optional idol ID if one was created.
    String? idolId,

    /// Status message.
    String? message,
  }) = _FinishIntakeResponse;

  factory FinishIntakeResponse.fromJson(Map<String, dynamic> json) {
    return FinishIntakeResponse(
      jobId: (json['jobId'] ?? json['job_id'])?.toString() ?? '',
      idolId: (json['idolId'] ?? json['idol_id'])?.toString(),
      message: json['message']?.toString(),
    );
  }

  Map<String, dynamic> toJson() => {
    'jobId': jobId,
    if (idolId != null) 'idolId': idolId,
    if (message != null) 'message': message,
  };
}

/// Response from submitting an answer.
@freezed
class SubmitAnswerResponse with _$SubmitAnswerResponse {
  const SubmitAnswerResponse._();

  const factory SubmitAnswerResponse({
    /// Whether the submission was successful.
    @Default(true) bool success,

    /// The submitted answer.
    IntakeAnswer? answer,

    /// Next question if available.
    IntakeQuestion? nextQuestion,

    /// Updated session status.
    String? status,

    /// Progress percentage.
    double? progress,

    /// Error message if failed.
    String? error,
  }) = _SubmitAnswerResponse;

  factory SubmitAnswerResponse.fromJson(Map<String, dynamic> json) {
    return SubmitAnswerResponse(
      success: json['success'] != false,
      answer: json['answer'] != null
          ? IntakeAnswer.fromJson(json['answer'] as Map<String, dynamic>)
          : null,
      nextQuestion: json['nextQuestion'] != null
          ? IntakeQuestion.fromJson(
              json['nextQuestion'] as Map<String, dynamic>,
            )
          : (json['next_question'] != null
                ? IntakeQuestion.fromJson(
                    json['next_question'] as Map<String, dynamic>,
                  )
                : null),
      status: json['status']?.toString(),
      progress: _parseDouble(json['progress']),
      error: json['error']?.toString(),
    );
  }

  Map<String, dynamic> toJson() => {
    'success': success,
    if (answer != null) 'answer': answer!.toJson(),
    if (nextQuestion != null) 'nextQuestion': nextQuestion!.toJson(),
    if (status != null) 'status': status,
    if (progress != null) 'progress': progress,
    if (error != null) 'error': error,
  };

  static double? _parseDouble(dynamic value) {
    if (value == null) return null;
    if (value is double) return value;
    if (value is num) return value.toDouble();
    if (value is String) return double.tryParse(value);
    return null;
  }
}
