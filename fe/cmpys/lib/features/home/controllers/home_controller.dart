import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_error.dart';
import '../../auth/controllers/session_controller.dart';
import '../../idols/data/idols_repository.dart';
import '../../idols/models/idol_models.dart';
import '../../idols/models/timeline_models.dart';

typedef IdolProfileLoader = Future<IdolProfile> Function(String idolId);
typedef IdolTimelineLoader =
    Future<TimelineResponse> Function(String idolId, {int? age, String? mode});
typedef MissingAvatarGenerator =
    Future<String> Function(String idolId, {int? age});

/// Home screen state.
sealed class HomeState {
  const HomeState();
}

class HomeInitial extends HomeState {
  const HomeInitial();
}

class HomeLoading extends HomeState {
  const HomeLoading();
}

class HomeLoaded extends HomeState {
  const HomeLoaded({
    required this.idol,
    required this.timeline,
    required this.userAge,
  });
  final IdolProfile idol;
  final TimelineResponse timeline;
  final int userAge;
}

class HomeError extends HomeState {
  const HomeError({required this.message});
  final String message;
}

/// Home controller provider.
final homeControllerProvider = StateNotifierProvider<HomeController, HomeState>(
  (ref) {
    final idolsRepository = ref.watch(idolsRepositoryProvider);
    final sessionController = ref.watch(sessionControllerProvider.notifier);
    return HomeController(
      currentIdolId: ref.watch(currentIdolIdProvider),
      readUserAge: () => sessionController.userAge,
      clearCurrentIdolId: sessionController.clearCurrentIdolId,
      loadIdolProfile: idolsRepository.getIdolProfile,
      loadIdolTimeline: idolsRepository.getIdolTimeline,
      generateMissingAvatar: idolsRepository.generateAvatar,
    );
  },
);

/// Controller for home screen data.
class HomeController extends StateNotifier<HomeState> {
  HomeController({
    required String? currentIdolId,
    required int? Function() readUserAge,
    required Future<void> Function() clearCurrentIdolId,
    required IdolProfileLoader loadIdolProfile,
    required IdolTimelineLoader loadIdolTimeline,
    required MissingAvatarGenerator generateMissingAvatar,
  }) : _currentIdolId = currentIdolId,
       _readUserAge = readUserAge,
       _clearCurrentIdolId = clearCurrentIdolId,
       _loadIdolProfile = loadIdolProfile,
       _loadIdolTimeline = loadIdolTimeline,
       _generateAvatar = generateMissingAvatar,
       super(const HomeInitial());

  final String? _currentIdolId;
  final int? Function() _readUserAge;
  final Future<void> Function() _clearCurrentIdolId;
  final IdolProfileLoader _loadIdolProfile;
  final IdolTimelineLoader _loadIdolTimeline;
  final MissingAvatarGenerator _generateAvatar;

  /// Load home screen data.
  Future<void> load() async {
    if (state is HomeLoading) return;

    final idolId = _currentIdolId;
    if (idolId == null) {
      state = const HomeError(message: 'No idol selected');
      return;
    }

    state = const HomeLoading();

    try {
      final userAge = _readUserAge();
      if (userAge == null) {
        state = const HomeError(message: 'User age not available');
        return;
      }

      final idol = await _loadIdolProfile(idolId);
      final timeline = await _loadTimelineOrEmpty(idolId, idol, userAge);

      state = HomeLoaded(idol: idol, timeline: timeline, userAge: userAge);

      // Auto-generate avatar in background if missing
      if (idol.avatarUrl == null || (idol.avatarUrl?.isEmpty ?? true)) {
        _generateMissingAvatar(idol.id, userAge);
      }
    } on ApiError catch (e) {
      if (e.isNotFoundError && e.message.toLowerCase().contains('idol')) {
        await _clearCurrentIdolId();
        state = const HomeError(message: 'Choose an idol to continue');
        return;
      }
      state = HomeError(message: e.message);
    } catch (e) {
      state = HomeError(message: e.toString());
    }
  }

  Future<TimelineResponse> _loadTimelineOrEmpty(
    String idolId,
    IdolProfile idol,
    int userAge,
  ) async {
    try {
      return await _loadIdolTimeline(idolId, age: userAge, mode: 'up_to');
    } on ApiError catch (e) {
      if (e.isNotFoundError && e.message.toLowerCase().contains('idol')) {
        rethrow;
      }
      return TimelineResponse(
        idolId: idol.id,
        idolName: idol.name,
        totalEvents: 0,
      );
    } catch (_) {
      return TimelineResponse(
        idolId: idol.id,
        idolName: idol.name,
        totalEvents: 0,
      );
    }
  }

  /// Fire-and-forget background generation of missing avatar.
  Future<void> _generateMissingAvatar(String idolId, int userAge) async {
    try {
      await _generateAvatar(idolId, age: userAge);
      // Wait a moment then seamlessly refresh to display the newly generated image!
      await Future.delayed(const Duration(milliseconds: 500));
      refresh();
    } catch (e) {
      // Background generation failed, no state disruption needed
    }
  }

  /// Refresh home data.
  Future<void> refresh() async {
    await load();
  }

  /// Get milestone count for display.
  int get milestoneCount {
    final currentState = state;
    if (currentState is HomeLoaded) {
      return currentState.timeline.items.length;
    }
    return 0;
  }

  /// Check if timeline is still enriching.
  /// Returns false if we have events - data is ready.
  /// Returns false if no events but totalEvents confirms there's nothing - data is ready (just empty).
  bool get isEnriching {
    final currentState = state;
    if (currentState is HomeLoaded) {
      // If we have events, data is ready
      if (currentState.timeline.items.isNotEmpty) {
        return false;
      }
      // If backend confirms totalEvents is 0, timeline is ready but empty (not enriching)
      // This is the case when the idol simply has no milestones before this age
      return false; // Don't show enriching banner - data loaded successfully
    }
    return false;
  }

  /// Get completeness percentage based on timeline items count.
  double get completeness {
    final currentState = state;
    if (currentState is HomeLoaded) {
      // If we have items, consider it complete
      if (currentState.timeline.items.isNotEmpty) {
        return 1.0;
      }
      return 0.0;
    }
    return 0;
  }
}

/// Provider for idol profile (convenience).
final currentIdolProfileProvider = Provider<IdolProfile?>((ref) {
  final homeState = ref.watch(homeControllerProvider);
  return switch (homeState) {
    HomeLoaded(:final idol) => idol,
    _ => null,
  };
});

/// Provider for idol timeline (convenience).
final currentIdolTimelineProvider = Provider<List<TimelineItem>>((ref) {
  final homeState = ref.watch(homeControllerProvider);
  return switch (homeState) {
    HomeLoaded(:final timeline) => timeline.items,
    _ => [],
  };
});
