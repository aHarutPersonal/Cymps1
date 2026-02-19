import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_error.dart';
import '../../auth/controllers/session_controller.dart';
import '../../idols/data/idols_repository.dart';
import '../../idols/models/idol_models.dart';
import '../../idols/models/timeline_models.dart';

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
final homeControllerProvider =
    StateNotifierProvider<HomeController, HomeState>((ref) {
  return HomeController(
    idolsRepository: ref.watch(idolsRepositoryProvider),
    sessionController: ref.watch(sessionControllerProvider.notifier),
    currentIdolId: ref.watch(currentIdolIdProvider),
  );
});

/// Controller for home screen data.
class HomeController extends StateNotifier<HomeState> {
  HomeController({
    required IdolsRepository idolsRepository,
    required SessionController sessionController,
    required String? currentIdolId,
  })  : _idolsRepository = idolsRepository,
        _sessionController = sessionController,
        _currentIdolId = currentIdolId,
        super(const HomeInitial());

  final IdolsRepository _idolsRepository;
  final SessionController _sessionController;
  final String? _currentIdolId;

  /// Load home screen data.
  Future<void> load() async {
    if (_currentIdolId == null) {
      state = const HomeError(message: 'No idol selected');
      return;
    }

    state = const HomeLoading();

    try {
      final userAge = _sessionController.userAge;
      if (userAge == null) {
        state = const HomeError(message: 'User age not available');
        return;
      }

      // Fetch idol profile and timeline in parallel
      // GET /idols/{idolId}/profile
      // GET /idols/{idolId}/timeline?age={age}&mode=up_to
      final results = await Future.wait([
        _idolsRepository.getIdolProfile(_currentIdolId),
        _idolsRepository.getIdolTimeline(
          _currentIdolId,
          age: userAge,
          mode: 'up_to',
        ),
      ]);

      final idol = results[0] as IdolProfile;
      final timeline = results[1] as TimelineResponse;

      state = HomeLoaded(
        idol: idol,
        timeline: timeline,
        userAge: userAge,
      );
    } on ApiError catch (e) {
      state = HomeError(message: e.message);
    } catch (e) {
      state = HomeError(message: e.toString());
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
