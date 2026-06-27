import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/session_repository.dart';
import '../models/session_models.dart';

// =============================================================================
// State
// =============================================================================

/// Sealed state for the agentic session workflow.
sealed class SessionState {
  const SessionState();
}

/// No active session.
class SessionIdle extends SessionState {
  const SessionIdle();
}

/// Loading (creating session, fetching suggestions, etc.).
class SessionLoading extends SessionState {
  const SessionLoading({this.message});
  final String? message;
}

/// Session is active and in a specific phase.
class SessionActive extends SessionState {
  const SessionActive({
    required this.session,
    this.suggestions,
    this.isStreaming = false,
    this.streamedContent = '',
    this.streamedSection,
    this.error,
  });

  final Session session;
  final List<IdolSuggestion>? suggestions;
  final bool isStreaming;
  final String streamedContent;
  final String? streamedSection; // 'comparison' | 'blueprint'
  final String? error;

  SessionActive copyWith({
    Session? session,
    List<IdolSuggestion>? suggestions,
    bool? isStreaming,
    String? streamedContent,
    String? streamedSection,
    String? error,
  }) {
    return SessionActive(
      session: session ?? this.session,
      suggestions: suggestions ?? this.suggestions,
      isStreaming: isStreaming ?? this.isStreaming,
      streamedContent: streamedContent ?? this.streamedContent,
      streamedSection: streamedSection ?? this.streamedSection,
      error: error,
    );
  }
}

/// Session workflow completed successfully.
class SessionCompleted extends SessionState {
  const SessionCompleted({required this.session});
  final Session session;
}

/// Unrecoverable error.
class SessionError extends SessionState {
  const SessionError(this.message);
  final String message;
}

// =============================================================================
// Provider
// =============================================================================

/// Session controller provider.
final sessionControllerProvider =
    StateNotifierProvider.autoDispose<SessionController, SessionState>((ref) {
      return SessionController(
        repository: ref.watch(sessionRepositoryProvider),
      );
    });

/// Derived provider for current phase (convenience).
final currentPhaseProvider = Provider.autoDispose<SessionPhase?>((ref) {
  final state = ref.watch(sessionControllerProvider);
  if (state is SessionActive) return state.session.phase;
  if (state is SessionCompleted) return SessionPhase.completed;
  return null;
});

// =============================================================================
// Controller
// =============================================================================

/// Controller for the 5-phase agentic session workflow.
///
/// Manages the full lifecycle:
/// 1. Create session with intake data
/// 2. Get idol suggestions + select one
/// 3. Interview via SSE streaming
/// 4. Generate comparison + blueprint via SSE
/// 5. Complete
class SessionController extends StateNotifier<SessionState> {
  SessionController({required SessionRepository repository})
    : _repository = repository,
      super(const SessionIdle());

  final SessionRepository _repository;
  StreamSubscription<Map<String, dynamic>>? _streamSubscription;

  @override
  void dispose() {
    _streamSubscription?.cancel();
    super.dispose();
  }

  // ===========================================================================
  // Phase 1: Create Session
  // ===========================================================================

  /// Create a new session with intake data.
  Future<void> createSession({
    required int age,
    required String financialStatus,
    required List<String> interests,
  }) async {
    state = const SessionLoading(message: 'Setting up your session...');

    try {
      final session = await _repository.createSession(
        SessionCreateRequest(
          age: age,
          financialStatus: financialStatus,
          interests: interests,
        ),
      );

      state = SessionActive(session: session);
    } catch (e) {
      debugPrint('❌ Failed to create session: $e');
      state = SessionError(e.toString());
    }
  }

  // ===========================================================================
  // Phase 2: Idol Suggestions + Selection
  // ===========================================================================

  /// Fetch 3 idol suggestions from the AI.
  Future<void> suggestIdols() async {
    final current = state;
    if (current is! SessionActive) return;

    state = current.copyWith(isStreaming: true, error: null);

    try {
      final suggestions = await _repository.suggestIdols(current.session.id);
      state = current.copyWith(suggestions: suggestions, isStreaming: false);
    } catch (e) {
      debugPrint('❌ Failed to get idol suggestions: $e');
      state = current.copyWith(
        isStreaming: false,
        error: 'Failed to get idol suggestions: $e',
      );
    }
  }

  /// Choose the mentor and transition to interview phase.
  Future<void> selectIdol(String idolName, {String? wikidataId}) async {
    final current = state;
    if (current is! SessionActive) return;

    state = const SessionLoading(message: 'Preparing your mentor...');

    try {
      final updatedSession = await _repository.selectIdol(
        current.session.id,
        SelectIdolRequest(idolName: idolName, wikidataId: wikidataId),
      );

      state = SessionActive(session: updatedSession);
    } catch (e) {
      debugPrint('❌ Failed to select idol: $e');
      state = SessionActive(
        session: current.session,
        suggestions: current.suggestions,
        error: 'Failed to select idol: $e',
      );
    }
  }

  // ===========================================================================
  // Phase 3: Interview (SSE)
  // ===========================================================================

  /// Send an interview message and stream the AI's response.
  Future<void> sendInterviewMessage(String content) async {
    final current = state;
    if (current is! SessionActive) return;

    state = current.copyWith(
      isStreaming: true,
      streamedContent: '',
      error: null,
    );

    try {
      final stream = _repository.sendInterviewMessage(
        current.session.id,
        content,
      );

      String accumulated = '';
      bool phaseTransition = false;
      int turn = current.session.interviewTurnCount;

      await for (final event in stream) {
        final type = event['type'] as String? ?? '';

        switch (type) {
          case 'chunk':
            accumulated += (event['content'] as String? ?? '');
            if (mounted) {
              state = (state as SessionActive).copyWith(
                streamedContent: accumulated,
              );
            }
            break;

          case 'done':
            phaseTransition = event['phase_transition'] == true;
            turn = (event['turn'] as int?) ?? turn;
            break;

          case 'error':
            if (mounted) {
              state = (state as SessionActive).copyWith(
                isStreaming: false,
                error: event['message']?.toString() ?? 'Unknown error',
              );
            }
            return;
        }
      }

      // Refresh session state from server
      if (mounted) {
        final refreshed = await _repository.getSession(current.session.id);
        state = SessionActive(
          session: refreshed,
          isStreaming: false,
          streamedContent: accumulated,
        );

        // If phase transitioned to comparison, auto-start results
        if (phaseTransition && refreshed.phase == SessionPhase.comparison) {
          // Don't auto-start — let the UI handle navigation
          debugPrint('📍 Interview complete, phase transitioned to comparison');
        }
      }
    } catch (e) {
      debugPrint('❌ Interview stream error: $e');
      if (mounted) {
        state = (state as SessionActive).copyWith(
          isStreaming: false,
          error: 'Interview error: $e',
        );
      }
    }
  }

  // ===========================================================================
  // Phase 4–5: Generate Results (Comparison + Blueprint)
  // ===========================================================================

  /// Start generating comparison + blueprint via SSE.
  Future<void> generateResults() async {
    final current = state;
    if (current is! SessionActive) return;

    state = current.copyWith(
      isStreaming: true,
      streamedContent: '',
      streamedSection: null,
      error: null,
    );

    try {
      final stream = _repository.generateResults(current.session.id);

      String comparisonContent = '';
      String blueprintContent = '';
      String currentSection = '';

      await for (final event in stream) {
        final type = event['type'] as String? ?? '';

        switch (type) {
          case 'section':
            currentSection = event['section'] as String? ?? '';
            if (mounted) {
              state = (state as SessionActive).copyWith(
                streamedSection: currentSection,
                streamedContent: '',
              );
            }
            break;

          case 'chunk':
            final content = event['content'] as String? ?? '';
            if (currentSection == 'comparison') {
              comparisonContent += content;
            } else if (currentSection == 'blueprint') {
              blueprintContent += content;
            }
            if (mounted) {
              state = (state as SessionActive).copyWith(
                streamedContent: currentSection == 'comparison'
                    ? comparisonContent
                    : blueprintContent,
                streamedSection: currentSection,
              );
            }
            break;

          case 'done':
            debugPrint('✅ Results generation complete');
            break;

          case 'error':
            if (mounted) {
              state = (state as SessionActive).copyWith(
                isStreaming: false,
                error: event['message']?.toString() ?? 'Generation failed',
              );
            }
            return;
        }
      }

      // Refresh final state from server
      if (mounted) {
        final refreshed = await _repository.getSession(current.session.id);
        if (refreshed.phase == SessionPhase.completed) {
          state = SessionCompleted(session: refreshed);
        } else {
          state = SessionActive(session: refreshed, isStreaming: false);
        }
      }
    } catch (e) {
      debugPrint('❌ Results generation error: $e');
      if (mounted) {
        state = (state as SessionActive).copyWith(
          isStreaming: false,
          error: 'Results generation failed: $e',
        );
      }
    }
  }

  // ===========================================================================
  // Session Resume
  // ===========================================================================

  /// Check for and resume an active session.
  Future<bool> checkForActiveSession() async {
    try {
      final session = await _repository.getCurrentSession();
      if (session != null) {
        if (session.phase == SessionPhase.completed) {
          state = SessionCompleted(session: session);
        } else {
          state = SessionActive(session: session);
        }
        return true;
      }
      return false;
    } catch (e) {
      debugPrint('⚠️ Failed to check for active session: $e');
      return false;
    }
  }

  /// Refresh the current session state from the server.
  Future<void> refreshSession() async {
    final current = state;
    if (current is! SessionActive) return;

    try {
      final refreshed = await _repository.getSession(current.session.id);
      state = current.copyWith(session: refreshed);
    } catch (e) {
      debugPrint('⚠️ Failed to refresh session: $e');
    }
  }

  // ===========================================================================
  // Guided Learning (Phase 6)
  // ===========================================================================

  /// Fetch learning materials for a specific blueprint topic.
  Future<List<LearningMaterial>> fetchLearningMaterials(String topic) async {
    final current = state;
    if (current is! SessionActive && current is! SessionCompleted) return [];

    final sessionId = current is SessionActive
        ? current.session.id
        : (current as SessionCompleted).session.id;

    try {
      final materials = await _repository.fetchLearningMaterials(
        sessionId,
        topic,
      );
      return materials;
    } catch (e) {
      debugPrint('❌ Failed to fetch learning materials: $e');
      return [];
    }
  }

  /// Send a guided learning message and stream the tutor's response.
  Future<void> sendGuidedLearningMessage(String content) async {
    final current = state;
    if (current is! SessionActive && current is! SessionCompleted) return;

    final sessionId = current is SessionActive
        ? current.session.id
        : (current as SessionCompleted).session.id;

    if (current is SessionActive) {
      state = current.copyWith(
        isStreaming: true,
        streamedContent: '',
        error: null,
      );
    } else {
      // Revert to active state to show streaming UI if it was completed
      state = SessionActive(
        session: (current as SessionCompleted).session,
        isStreaming: true,
        streamedContent: '',
        error: null,
      );
    }

    try {
      final stream = _repository.sendGuidedLearningMessage(sessionId, content);

      String accumulated = '';

      await for (final event in stream) {
        final type = event['type'] as String? ?? '';

        switch (type) {
          case 'chunk':
            accumulated += (event['content'] as String? ?? '');
            if (mounted) {
              state = (state as SessionActive).copyWith(
                streamedContent: accumulated,
              );
            }
            break;

          case 'error':
            if (mounted) {
              state = (state as SessionActive).copyWith(
                isStreaming: false,
                error: event['message']?.toString() ?? 'Learning tutor error',
              );
            }
            return;

          case 'done':
            if (mounted) {
              state = (state as SessionActive).copyWith(
                isStreaming: false,
                streamedContent: accumulated,
              );
            }
            break;
        }
      }

      // Refresh final state from server
      if (mounted) {
        final refreshed = await _repository.getSession(sessionId);
        state = SessionActive(
          session: refreshed,
          isStreaming: false,
          streamedContent: accumulated,
        );
      }
    } catch (e) {
      debugPrint('❌ Guided learning stream error: $e');
      if (mounted && state is SessionActive) {
        state = (state as SessionActive).copyWith(
          isStreaming: false,
          error: 'Guided learning tutor failed: $e',
        );
      }
    }
  }

  /// Clear any displayed error.
  void clearError() {
    final current = state;
    if (current is! SessionActive) return;
    state = current.copyWith(error: null);
  }

  /// Reset to idle state (abandon current session).
  void reset() {
    _streamSubscription?.cancel();
    state = const SessionIdle();
  }
}
