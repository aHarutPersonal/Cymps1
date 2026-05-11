import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_error.dart';
import '../../achievements/data/achievements_repository.dart';
import '../../auth/controllers/session_controller.dart';
import '../data/comparison_repository.dart';
import '../models/comparison_models.dart';

/// Comparison state.
sealed class ComparisonState {
  const ComparisonState();
}

class ComparisonInitial extends ComparisonState {
  const ComparisonInitial();
}

class ComparisonLoading extends ComparisonState {
  const ComparisonLoading();
}

class ComparisonLoaded extends ComparisonState {
  const ComparisonLoaded({
    required this.comparison,
    required this.userAge,
    required this.idolName,
    this.isRefreshing = false,
  });
  final ComparisonResponse comparison;
  final int userAge;
  final String idolName;
  final bool isRefreshing;

  /// Check if data is incomplete (completeness < 1)
  bool get isIncomplete => comparison.completeness < 1.0;

  /// Get completeness percentage
  int get completenessPercent => (comparison.completeness * 100).round();

  /// Check if this is an AI-enhanced comparison
  bool get isAIEnhanced => comparison.aiEnhanced;

  ComparisonLoaded copyWith({bool? isRefreshing}) {
    return ComparisonLoaded(
      comparison: comparison,
      userAge: userAge,
      idolName: idolName,
      isRefreshing: isRefreshing ?? this.isRefreshing,
    );
  }
}

class ComparisonError extends ComparisonState {
  const ComparisonError({required this.message});
  final String message;
}

/// Comparison controller provider.
final comparisonControllerProvider =
    StateNotifierProvider<ComparisonController, ComparisonState>((ref) {
      return ComparisonController(
        comparisonRepository: ref.watch(comparisonRepositoryProvider),
        achievementsRepository: ref.watch(achievementsRepositoryProvider),
        currentIdolId: ref.watch(currentIdolIdProvider),
        sessionController: ref.watch(sessionControllerProvider.notifier),
      );
    });

/// Controller for comparison screen.
class ComparisonController extends StateNotifier<ComparisonState> {
  ComparisonController({
    required ComparisonRepository comparisonRepository,
    required AchievementsRepository achievementsRepository,
    required String? currentIdolId,
    required SessionController sessionController,
  }) : _comparisonRepository = comparisonRepository,
       _achievementsRepository = achievementsRepository,
       _currentIdolId = currentIdolId,
       _sessionController = sessionController,
       super(const ComparisonInitial());

  final ComparisonRepository _comparisonRepository;
  final AchievementsRepository _achievementsRepository;
  final String? _currentIdolId;
  final SessionController _sessionController;

  bool _isStaleIdolError(ApiError error) {
    return error.isNotFoundError &&
        error.message.toLowerCase().contains('idol');
  }

  /// Track achievement count at the time comparison was last loaded.
  int _lastKnownAchievementCount = -1;

  /// Load comparison data.
  /// First tries AI comparison, falls back to basic if unavailable.
  Future<void> load() async {
    if (_currentIdolId == null) {
      state = const ComparisonError(message: 'No idol selected');
      return;
    }

    final userAge = _sessionController.userAge;
    if (userAge == null) {
      state = const ComparisonError(message: 'User age not available');
      return;
    }

    state = const ComparisonLoading();

    try {
      // Try AI comparison first
      ComparisonResponse? comparison;
      try {
        debugPrint('🧠 Attempting AI comparison...');
        comparison = await _comparisonRepository.getAIComparison(
          _currentIdolId,
          age: userAge,
          mode: 'up_to',
        );
        debugPrint(
          '🧠 AI comparison successful! Score: ${comparison.overallScore}',
        );
      } catch (e) {
        // AI comparison failed, fall back to basic
        debugPrint('⚠️ AI comparison failed, falling back to basic: $e');
        comparison = await _comparisonRepository.getComparison(
          _currentIdolId,
          age: userAge,
          mode: 'up_to',
        );
      }

      // Snapshot current achievement count
      try {
        final achievements = await _achievementsRepository.getAllAchievements();
        _lastKnownAchievementCount = achievements.length;
      } catch (_) {
        // Non-critical: comparison still works without tracking
      }

      // Get idol name from response or use a fallback
      final idolName = comparison.idolName ?? _getIdolName();

      state = ComparisonLoaded(
        comparison: comparison,
        userAge: userAge,
        idolName: idolName,
      );
    } on ApiError catch (e) {
      if (_isStaleIdolError(e)) {
        await _sessionController.clearCurrentIdolId();
        state = const ComparisonError(message: 'Choose an idol to continue');
      } else {
        state = ComparisonError(message: e.message);
      }
    } catch (e) {
      state = ComparisonError(message: e.toString());
    }
  }

  /// Check if achievements changed since last comparison load.
  /// If so, auto-refresh the comparison in the background.
  Future<void> checkAndRefreshIfNeeded() async {
    if (state is! ComparisonLoaded) return;
    if (_lastKnownAchievementCount < 0) return;

    try {
      final achievements = await _achievementsRepository.getAllAchievements();
      final currentCount = achievements.length;

      if (currentCount != _lastKnownAchievementCount) {
        debugPrint(
          '🔄 Achievement count changed '
          '($_lastKnownAchievementCount → $currentCount), refreshing comparison...',
        );

        final loaded = state as ComparisonLoaded;
        state = loaded.copyWith(isRefreshing: true);

        await load();
      }
    } catch (e) {
      debugPrint('⚠️ Failed to check achievement count: $e');
    }
  }

  /// Force basic comparison (non-AI).
  Future<void> loadBasic() async {
    if (_currentIdolId == null) {
      state = const ComparisonError(message: 'No idol selected');
      return;
    }

    final userAge = _sessionController.userAge;
    if (userAge == null) {
      state = const ComparisonError(message: 'User age not available');
      return;
    }

    state = const ComparisonLoading();

    try {
      final comparison = await _comparisonRepository.getComparison(
        _currentIdolId,
        age: userAge,
        mode: 'up_to',
      );

      final idolName = comparison.idolName ?? _getIdolName();

      state = ComparisonLoaded(
        comparison: comparison,
        userAge: userAge,
        idolName: idolName,
      );
    } on ApiError catch (e) {
      if (_isStaleIdolError(e)) {
        await _sessionController.clearCurrentIdolId();
        state = const ComparisonError(message: 'Choose an idol to continue');
      } else {
        state = ComparisonError(message: e.message);
      }
    } catch (e) {
      state = ComparisonError(message: e.toString());
    }
  }

  /// Refresh comparison data.
  Future<void> refresh() async {
    await load();
  }

  String _getIdolName() {
    // Try to get idol name from session state
    final sessionState = _sessionController.state;
    if (sessionState is SessionReady) {
      // Would need idol profile cached - for now use generic
      return 'Idol';
    }
    return 'Idol';
  }
}
