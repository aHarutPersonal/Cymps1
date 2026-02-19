import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/intake_repository.dart';
import '../models/intake_models.dart';

/// Intake wizard state.
sealed class IntakeState {
  const IntakeState();
}

class IntakeInitial extends IntakeState {
  const IntakeInitial();
}

class IntakeLoading extends IntakeState {
  const IntakeLoading();
}

class IntakeReady extends IntakeState {
  const IntakeReady({
    required this.sessionId,
    required this.questions,
    required this.answers,
    required this.currentIndex,
    this.isSubmitting = false,
    this.error,
  });

  final String sessionId;
  final List<IntakeQuestion> questions;
  final Map<String, dynamic> answers; // questionId -> answer value
  final int currentIndex;
  final bool isSubmitting;
  final String? error;

  IntakeQuestion get currentQuestion => questions[currentIndex];
  bool get isFirstQuestion => currentIndex == 0;
  bool get isLastQuestion => currentIndex == questions.length - 1;
  double get progress => questions.isEmpty ? 0 : (currentIndex + 1) / questions.length;
  int get answeredCount => answers.length;

  IntakeReady copyWith({
    String? sessionId,
    List<IntakeQuestion>? questions,
    Map<String, dynamic>? answers,
    int? currentIndex,
    bool? isSubmitting,
    String? error,
  }) {
    return IntakeReady(
      sessionId: sessionId ?? this.sessionId,
      questions: questions ?? this.questions,
      answers: answers ?? this.answers,
      currentIndex: currentIndex ?? this.currentIndex,
      isSubmitting: isSubmitting ?? this.isSubmitting,
      error: error,
    );
  }
}

class IntakeCompleted extends IntakeState {
  const IntakeCompleted({
    required this.jobId,
    this.idolId,
  });

  final String jobId;
  final String? idolId;
}

class IntakeError extends IntakeState {
  const IntakeError(this.message);
  final String message;
}

/// Intake controller provider.
final intakeControllerProvider =
    StateNotifierProvider.autoDispose<IntakeController, IntakeState>((ref) {
  return IntakeController(
    repository: ref.watch(intakeRepositoryProvider),
  );
});

/// Controller for the intake wizard flow.
class IntakeController extends StateNotifier<IntakeState> {
  IntakeController({required IntakeRepository repository})
      : _repository = repository,
        super(const IntakeInitial());

  final IntakeRepository _repository;

  /// Start a new intake session.
  Future<void> startIntake({String? idolId, int? targetAge}) async {
    state = const IntakeLoading();

    try {
      final response = await _repository.startIntake(
        idolId: idolId,
        targetAge: targetAge,
      );

      state = IntakeReady(
        sessionId: response.sessionId,
        questions: response.questions,
        answers: {},
        currentIndex: 0,
      );
    } catch (e) {
      debugPrint('❌ Failed to start intake: $e');
      state = IntakeError(e.toString());
    }
  }

  /// Load an existing intake session.
  Future<void> loadSession(String sessionId) async {
    state = const IntakeLoading();

    try {
      final response = await _repository.getIntakeSession(sessionId);

      // Build answers map from existing answers
      final answers = <String, dynamic>{};
      for (final answer in response.answers) {
        answers[answer.questionId] = answer.answer;
      }

      // Find the first unanswered question
      int currentIndex = 0;
      for (int i = 0; i < response.questions.length; i++) {
        if (!answers.containsKey(response.questions[i].id)) {
          currentIndex = i;
          break;
        }
        // If all answered, stay at last question
        if (i == response.questions.length - 1) {
          currentIndex = i;
        }
      }

      state = IntakeReady(
        sessionId: response.sessionId,
        questions: response.questions,
        answers: answers,
        currentIndex: currentIndex,
      );
    } catch (e) {
      debugPrint('❌ Failed to load session: $e');
      state = IntakeError(e.toString());
    }
  }

  /// Initialize with provided questions (no API call).
  void initWithQuestions({
    required String sessionId,
    required List<IntakeQuestion> questions,
  }) {
    state = IntakeReady(
      sessionId: sessionId,
      questions: questions,
      answers: {},
      currentIndex: 0,
    );
  }

  /// Set answer for current question locally (without submitting).
  void setAnswer(dynamic value) {
    final current = state;
    if (current is! IntakeReady) return;

    final newAnswers = Map<String, dynamic>.from(current.answers);
    newAnswers[current.currentQuestion.id] = value;

    state = current.copyWith(answers: newAnswers, error: null);
  }

  /// Get current answer for a question.
  dynamic getAnswer(String questionId) {
    final current = state;
    if (current is! IntakeReady) return null;
    return current.answers[questionId];
  }

  /// Submit current answer and move to next question.
  Future<bool> submitAndNext() async {
    final current = state;
    if (current is! IntakeReady) return false;

    final answer = current.answers[current.currentQuestion.id];

    // Validate required questions
    if (current.currentQuestion.isRequired && (answer == null || answer == '')) {
      state = current.copyWith(error: 'This question is required');
      return false;
    }

    state = current.copyWith(isSubmitting: true, error: null);

    try {
      // Submit answer to backend
      if (answer != null) {
        await _repository.submitAnswer(
          sessionId: current.sessionId,
          questionId: current.currentQuestion.id,
          answer: answer,
        );
      }

      // Move to next question
      if (!current.isLastQuestion) {
        state = current.copyWith(
          currentIndex: current.currentIndex + 1,
          isSubmitting: false,
        );
        return true;
      }

      // Already at last question, stay there
      state = current.copyWith(isSubmitting: false);
      return true;
    } catch (e) {
      debugPrint('❌ Failed to submit answer: $e');
      state = current.copyWith(
        isSubmitting: false,
        error: 'Failed to save answer. Please try again.',
      );
      return false;
    }
  }

  /// Go to previous question.
  void goBack() {
    final current = state;
    if (current is! IntakeReady) return;
    if (current.isFirstQuestion) return;

    state = current.copyWith(
      currentIndex: current.currentIndex - 1,
      error: null,
    );
  }

  /// Go to a specific question index.
  void goToQuestion(int index) {
    final current = state;
    if (current is! IntakeReady) return;
    if (index < 0 || index >= current.questions.length) return;

    state = current.copyWith(currentIndex: index, error: null);
  }

  /// Finish the intake and start processing.
  Future<void> finishIntake() async {
    final current = state;
    if (current is! IntakeReady) return;

    // Submit last answer if not submitted
    final lastAnswer = current.answers[current.currentQuestion.id];
    if (current.currentQuestion.isRequired && (lastAnswer == null || lastAnswer == '')) {
      state = current.copyWith(error: 'This question is required');
      return;
    }

    state = current.copyWith(isSubmitting: true, error: null);

    try {
      // Submit last answer if exists
      if (lastAnswer != null) {
        await _repository.submitAnswer(
          sessionId: current.sessionId,
          questionId: current.currentQuestion.id,
          answer: lastAnswer,
        );
      }

      // Finish intake
      final response = await _repository.finishIntake(current.sessionId);

      state = IntakeCompleted(
        jobId: response.jobId,
        idolId: response.idolId,
      );
    } catch (e) {
      debugPrint('❌ Failed to finish intake: $e');
      state = current.copyWith(
        isSubmitting: false,
        error: 'Failed to complete intake. Please try again.',
      );
    }
  }

  /// Skip current optional question.
  Future<void> skipQuestion() async {
    final current = state;
    if (current is! IntakeReady) return;

    // Can't skip required questions
    if (current.currentQuestion.isRequired) {
      state = current.copyWith(error: 'This question is required');
      return;
    }

    state = current.copyWith(isSubmitting: true, error: null);

    try {
      await _repository.skipQuestion(
        sessionId: current.sessionId,
        questionId: current.currentQuestion.id,
      );

      // Move to next question
      if (!current.isLastQuestion) {
        state = current.copyWith(
          currentIndex: current.currentIndex + 1,
          isSubmitting: false,
        );
      } else {
        state = current.copyWith(isSubmitting: false);
      }
    } catch (e) {
      debugPrint('❌ Failed to skip question: $e');
      // Still move forward locally even if API fails
      if (!current.isLastQuestion) {
        state = current.copyWith(
          currentIndex: current.currentIndex + 1,
          isSubmitting: false,
        );
      } else {
        state = current.copyWith(isSubmitting: false);
      }
    }
  }

  /// Clear any error.
  void clearError() {
    final current = state;
    if (current is! IntakeReady) return;
    state = current.copyWith(error: null);
  }
}
