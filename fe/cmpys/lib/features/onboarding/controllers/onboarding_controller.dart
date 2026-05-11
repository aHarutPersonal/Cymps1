import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_error.dart';
import '../../auth/controllers/session_controller.dart';
import '../../auth/data/me_repository.dart';
import '../../auth/models/me_models.dart';
import '../../idols/data/idols_repository.dart';
import '../../idols/data/jobs_repository.dart';
import '../../idols/models/idol_models.dart';
import '../../idols/models/job_models.dart';

/// Onboarding state.
sealed class OnboardingState {
  const OnboardingState();
}

class OnboardingInitial extends OnboardingState {
  const OnboardingInitial();
}

class OnboardingProfileStep extends OnboardingState {
  const OnboardingProfileStep({
    this.fullName,
    this.birthDate,
    this.interests = const [],
  });
  final String? fullName;
  final DateTime? birthDate;
  final List<String> interests;
}

class OnboardingSavingProfile extends OnboardingState {
  const OnboardingSavingProfile();
}

class OnboardingIdolSuggestStep extends OnboardingState {
  const OnboardingIdolSuggestStep({
    required this.suggestions,
    this.isLoading = false,
    this.jobId,
    this.jobStatus,
  });
  final List<IdolCandidate> suggestions;
  final bool isLoading;
  final String? jobId;
  final JobStatus? jobStatus;
}

class OnboardingIdolSearchStep extends OnboardingState {
  const OnboardingIdolSearchStep({
    this.query = '',
    this.results = const [],
    this.isLoading = false,
  });
  final String query;
  final List<IdolCandidate> results;
  final bool isLoading;
}

class OnboardingIdolConfirmStep extends OnboardingState {
  const OnboardingIdolConfirmStep({required this.selectedIdol});
  final IdolCandidate selectedIdol;
}

class OnboardingImportingIdol extends OnboardingState {
  const OnboardingImportingIdol({required this.idol, required this.jobStatus});
  final IdolCandidate idol;
  final JobStatus jobStatus;
}

class OnboardingComplete extends OnboardingState {
  const OnboardingComplete({required this.idolId});
  final String idolId;
}

class OnboardingError extends OnboardingState {
  const OnboardingError({required this.message, this.previousState});
  final String message;
  final OnboardingState? previousState;
}

/// Onboarding controller provider.
final onboardingControllerProvider =
    StateNotifierProvider<OnboardingController, OnboardingState>((ref) {
      return OnboardingController(
        meRepository: ref.watch(meRepositoryProvider),
        idolsRepository: ref.watch(idolsRepositoryProvider),
        jobsRepository: ref.watch(jobsRepositoryProvider),
        sessionController: ref.watch(sessionControllerProvider.notifier),
      );
    });

/// Controller for onboarding flow.
class OnboardingController extends StateNotifier<OnboardingState> {
  OnboardingController({
    required MeRepository meRepository,
    required IdolsRepository idolsRepository,
    required JobsRepository jobsRepository,
    required SessionController sessionController,
  }) : _meRepository = meRepository,
       _idolsRepository = idolsRepository,
       _jobsRepository = jobsRepository,
       _sessionController = sessionController,
       super(const OnboardingInitial());

  final MeRepository _meRepository;
  final IdolsRepository _idolsRepository;
  final JobsRepository _jobsRepository;
  final SessionController _sessionController;

  // Store profile data during onboarding
  String? _fullName;
  DateTime? _birthDate;
  List<String> _interests = [];
  IdolCandidate? _selectedIdol;

  /// Start onboarding from profile step.
  void startOnboarding({Me? existingUser}) {
    _fullName = existingUser?.fullName;
    _birthDate = existingUser?.birthDate;
    _interests = existingUser?.interests ?? [];

    state = OnboardingProfileStep(
      fullName: _fullName,
      birthDate: _birthDate,
      interests: _interests,
    );
  }

  /// Update profile step data.
  void updateProfile({
    String? fullName,
    DateTime? birthDate,
    List<String>? interests,
  }) {
    if (fullName != null) _fullName = fullName;
    if (birthDate != null) _birthDate = birthDate;
    if (interests != null) _interests = interests;

    state = OnboardingProfileStep(
      fullName: _fullName,
      birthDate: _birthDate,
      interests: _interests,
    );
  }

  /// Save profile and move to idol suggestions.
  Future<void> saveProfile() async {
    debugPrint('🎯 OnboardingController.saveProfile() called');
    debugPrint(
      '🎯 fullName=$_fullName, birthDate=$_birthDate, interests=$_interests',
    );

    if (_fullName == null || _birthDate == null || _interests.isEmpty) {
      debugPrint('🎯 Validation failed');
      state = const OnboardingError(message: 'Please complete all fields');
      return;
    }

    state = const OnboardingSavingProfile();
    debugPrint('🎯 State set to OnboardingSavingProfile');

    try {
      debugPrint('🎯 Calling meRepository.completeOnboarding...');
      final user = await _meRepository.completeOnboarding(
        fullName: _fullName!,
        birthDate: _birthDate!,
        interests: _interests,
      );
      debugPrint('🎯 Profile saved successfully');

      // Update session with new user data
      debugPrint('🎯 Calling sessionController.updateUser...');
      await _sessionController.updateUser(user);
      debugPrint('🎯 Session updated');

      // Move to idol suggestions
      debugPrint('🎯 Calling loadIdolSuggestions...');
      await loadIdolSuggestions();
      debugPrint('🎯 loadIdolSuggestions completed');
    } on ApiError catch (e) {
      debugPrint('🎯 ApiError: ${e.message}');
      state = OnboardingError(
        message: e.message,
        previousState: OnboardingProfileStep(
          fullName: _fullName,
          birthDate: _birthDate,
          interests: _interests,
        ),
      );
    } catch (e) {
      debugPrint('🎯 Error: $e');
      state = OnboardingError(
        message: e.toString(),
        previousState: OnboardingProfileStep(
          fullName: _fullName,
          birthDate: _birthDate,
          interests: _interests,
        ),
      );
    }
  }

  /// Load idol suggestions based on interests.
  Future<void> loadIdolSuggestions() async {
    debugPrint('🎯 loadIdolSuggestions called with interests: $_interests');
    state = const OnboardingIdolSuggestStep(suggestions: [], isLoading: true);

    try {
      final response = await _idolsRepository.suggest(_interests);

      if (response.jobId != null) {
        debugPrint('🎯 Got jobId for suggestions: ${response.jobId}');
        await _pollSuggestionJob(response.jobId!);
      } else {
        // Fallback for immediate response (if backend supports it)
        // Note: Our updated backend always returns a job for LLM suggestions
        debugPrint('🎯 No jobId, using immediate suggestions');
        state = OnboardingIdolSuggestStep(
          suggestions: [],
        ); // Needs to be filled if ever used
      }
    } on ApiError catch (e) {
      state = OnboardingError(
        message: e.message,
        previousState: const OnboardingIdolSuggestStep(suggestions: []),
      );
    } catch (e) {
      state = OnboardingError(
        message: e.toString(),
        previousState: const OnboardingIdolSuggestStep(suggestions: []),
      );
    }
  }

  /// Poll suggestion job status until complete.
  Future<void> _pollSuggestionJob(String jobId) async {
    try {
      await for (final status in _jobsRepository.watchJob(jobId)) {
        if (!mounted) return;

        // Extract suggestions if job is completed
        List<IdolCandidate> finalSuggestions = [];
        if (status.isCompleted && status.results != null) {
          final suggestionsData = status.results?['suggestions'];
          if (suggestionsData is List) {
            finalSuggestions = suggestionsData
                .map((e) => IdolCandidate.fromJson(e as Map<String, dynamic>))
                .toList();
          }
        }

        state = OnboardingIdolSuggestStep(
          suggestions: finalSuggestions,
          isLoading: !status.isTerminal,
          jobId: jobId,
          jobStatus: status,
        );

        if (status.isFailed) {
          state = OnboardingError(
            message: status.errorMessage ?? 'Failed to get suggestions',
            previousState: const OnboardingIdolSuggestStep(suggestions: []),
          );
          return;
        }

        if (status.isCompleted) {
          return;
        }
      }
    } catch (e) {
      state = OnboardingError(
        message: e.toString(),
        previousState: const OnboardingIdolSuggestStep(suggestions: []),
      );
    }
  }

  /// Switch to search mode.
  void goToSearch() {
    state = const OnboardingIdolSearchStep();
  }

  /// Go back to suggestions.
  void goToSuggestions() {
    loadIdolSuggestions();
  }

  /// Search for idols.
  Future<void> searchIdols(String query) async {
    if (query.trim().isEmpty) {
      state = const OnboardingIdolSearchStep();
      return;
    }

    state = OnboardingIdolSearchStep(query: query, isLoading: true);

    try {
      final response = await _idolsRepository.discover(query);

      // Only update state if this query is still the current one
      // This prevents race conditions where old results overwrite newer ones
      final currentState = state;
      if (currentState is OnboardingIdolSearchStep &&
          currentState.query == query) {
        state = OnboardingIdolSearchStep(
          query: query,
          results: response.candidates,
        );
      } else {
        debugPrint('🔍 Ignoring stale results for query: $query');
      }
    } on ApiError catch (e) {
      // Only show error if still on this query
      final currentState = state;
      if (currentState is OnboardingIdolSearchStep &&
          currentState.query == query) {
        state = OnboardingError(
          message: e.message,
          previousState: OnboardingIdolSearchStep(query: query),
        );
      }
    } catch (e) {
      final currentState = state;
      if (currentState is OnboardingIdolSearchStep &&
          currentState.query == query) {
        state = OnboardingError(
          message: e.toString(),
          previousState: OnboardingIdolSearchStep(query: query),
        );
      }
    }
  }

  /// Select an idol for confirmation.
  void selectIdol(IdolCandidate idol) {
    _selectedIdol = idol;
    state = OnboardingIdolConfirmStep(selectedIdol: idol);
  }

  /// Go back from confirmation to previous step.
  void cancelSelection() {
    _selectedIdol = null;
    // Go back to suggestions by default
    loadIdolSuggestions();
  }

  /// Confirm and import the selected idol.
  Future<void> confirmIdol() async {
    if (_selectedIdol == null) return;

    final idol = _selectedIdol!;

    // ignore: avoid_print
    print(
      '🎯 Confirming idol: ${idol.name} (provider: ${idol.provider}, id: ${idol.externalId})',
    );

    state = OnboardingImportingIdol(
      idol: idol,
      jobStatus: const JobStatus(status: 'pending', progressPercent: 0),
    );

    try {
      // For local suggestions, use the existing id
      // For web suggestions, import from provider
      if (idol.isLocal && idol.id != null) {
        // Local idol already exists in DB, just select it
        await _completeOnboarding(idol.id!);
        return;
      }

      // Start import with all available metadata
      final importResponse = await _idolsRepository.importIdol(
        provider: idol.provider,
        externalId: idol.externalId,
        name: idol.name,
        description: idol.description,
        birthDate: idol.birthDate?.toIso8601String().split(
          'T',
        )[0], // YYYY-MM-DD
        wikipediaUrl: idol.wikipediaUrl,
        occupations: idol.occupations.isNotEmpty ? idol.occupations : null,
      );

      if (importResponse.jobId == null || importResponse.idolId == null) {
        throw Exception(
          importResponse.detail ?? 'Failed to start import: missing ID',
        );
      }

      // Poll for job completion
      await _pollJobStatus(importResponse.jobId!, importResponse.idolId!, idol);
    } on ApiError catch (e) {
      state = OnboardingError(
        message: e.message,
        previousState: OnboardingIdolConfirmStep(selectedIdol: idol),
      );
    } catch (e) {
      state = OnboardingError(
        message: e.toString(),
        previousState: OnboardingIdolConfirmStep(selectedIdol: idol),
      );
    }
  }

  /// Poll job status until complete.
  Future<void> _pollJobStatus(
    String jobId,
    String idolId,
    IdolCandidate idol,
  ) async {
    try {
      await for (final status in _jobsRepository.watchJob(jobId)) {
        if (!mounted) return;

        state = OnboardingImportingIdol(idol: idol, jobStatus: status);

        if (status.isCompleted) {
          await _completeOnboarding(idolId);
          return;
        }

        if (status.isFailed) {
          state = OnboardingError(
            message: status.errorMessage ?? 'Import failed',
            previousState: OnboardingIdolConfirmStep(selectedIdol: idol),
          );
          return;
        }
      }
    } catch (e) {
      state = OnboardingError(
        message: e.toString(),
        previousState: OnboardingIdolConfirmStep(selectedIdol: idol),
      );
    }
  }

  /// Complete onboarding and save idol ID.
  Future<void> _completeOnboarding(String idolId) async {
    // Save idol ID to session
    await _sessionController.setCurrentIdolId(idolId);
    await _sessionController.completeOnboarding();

    state = OnboardingComplete(idolId: idolId);
  }

  /// Retry from error state.
  void retry() {
    final currentState = state;
    if (currentState is OnboardingError && currentState.previousState != null) {
      state = currentState.previousState!;
    } else {
      startOnboarding();
    }
  }

  /// Reset to initial state.
  void reset() {
    _fullName = null;
    _birthDate = null;
    _interests = [];
    _selectedIdol = null;
    state = const OnboardingInitial();
  }
}
