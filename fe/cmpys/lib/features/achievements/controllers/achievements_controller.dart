import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/achievements_repository.dart';
import '../models/achievement_models.dart';

/// Achievements state.
sealed class AchievementsState {
  const AchievementsState();
}

class AchievementsInitial extends AchievementsState {
  const AchievementsInitial();
}

class AchievementsLoading extends AchievementsState {
  const AchievementsLoading();
}

class AchievementsLoaded extends AchievementsState {
  const AchievementsLoaded({
    required this.achievements,
    this.total = 0,
  });
  
  final List<Achievement> achievements;
  final int total;
}

class AchievementsError extends AchievementsState {
  const AchievementsError(this.message);
  final String message;
}

/// Achievements controller provider.
final achievementsControllerProvider =
    StateNotifierProvider<AchievementsController, AchievementsState>((ref) {
  return AchievementsController(
    repository: ref.watch(achievementsRepositoryProvider),
  );
});

/// Controller for managing achievements.
class AchievementsController extends StateNotifier<AchievementsState> {
  AchievementsController({
    required AchievementsRepository repository,
  })  : _repository = repository,
        super(const AchievementsInitial());

  final AchievementsRepository _repository;

  /// Load all achievements.
  Future<void> load({
    AchievementCategory? category,
    String? query,
  }) async {
    state = const AchievementsLoading();

    try {
      final response = await _repository.listAchievements(
        category: category,
        query: query,
      );
      
      state = AchievementsLoaded(
        achievements: response.achievements,
        total: response.total,
      );
    } catch (e) {
      debugPrint('Failed to load achievements: $e');
      state = AchievementsError(e.toString());
    }
  }

  /// Create a new achievement.
  Future<Achievement?> createAchievement({
    required String title,
    required AchievementCategory category,
    DateTime? achievementDate,
    String? notes,
    String? evidenceLink,
  }) async {
    try {
      final achievement = await _repository.createAchievement(
        title: title,
        category: category,
        achievementDate: achievementDate,
        notes: notes,
        evidenceLink: evidenceLink,
      );

      // Add to current list
      if (state is AchievementsLoaded) {
        final current = state as AchievementsLoaded;
        state = AchievementsLoaded(
          achievements: [achievement, ...current.achievements],
          total: current.total + 1,
        );
      }

      return achievement;
    } catch (e) {
      debugPrint('Failed to create achievement: $e');
      return null;
    }
  }

  /// Update an achievement.
  Future<Achievement?> updateAchievement(
    String achievementId, {
    String? title,
    AchievementCategory? category,
    DateTime? achievementDate,
    String? notes,
    String? evidenceLink,
  }) async {
    try {
      final updated = await _repository.updateAchievement(
        achievementId,
        title: title,
        category: category,
        achievementDate: achievementDate,
        notes: notes,
        evidenceLink: evidenceLink,
      );

      // Update in current list
      if (state is AchievementsLoaded) {
        final current = state as AchievementsLoaded;
        state = AchievementsLoaded(
          achievements: current.achievements.map((a) {
            return a.id == achievementId ? updated : a;
          }).toList(),
          total: current.total,
        );
      }

      return updated;
    } catch (e) {
      debugPrint('Failed to update achievement: $e');
      return null;
    }
  }

  /// Delete an achievement.
  Future<bool> deleteAchievement(String achievementId) async {
    try {
      await _repository.deleteAchievement(achievementId);

      // Remove from current list
      if (state is AchievementsLoaded) {
        final current = state as AchievementsLoaded;
        state = AchievementsLoaded(
          achievements: current.achievements.where((a) => a.id != achievementId).toList(),
          total: current.total - 1,
        );
      }

      return true;
    } catch (e) {
      debugPrint('Failed to delete achievement: $e');
      return false;
    }
  }

  /// Refresh achievements list.
  Future<void> refresh() async {
    await load();
  }
}
