import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/network/api_error.dart';
import '../../../core/storage/token_store.dart';
import '../data/me_repository.dart';
import '../models/me_models.dart';
import 'auth_controller.dart';

/// Session state representing app initialization and user session.
sealed class SessionState {
  const SessionState();
}

class SessionInitializing extends SessionState {
  const SessionInitializing();
}

class SessionUnauthenticated extends SessionState {
  const SessionUnauthenticated();
}

class SessionNeedsOnboarding extends SessionState {
  const SessionNeedsOnboarding({required this.user});
  final Me user;
}

class SessionReady extends SessionState {
  const SessionReady({
    required this.user,
    required this.currentIdolId,
  });
  final Me user;
  final String currentIdolId;
}

class SessionError extends SessionState {
  const SessionError({required this.message});
  final String message;
}

/// Keys for local storage.
abstract class SessionKeys {
  static const String currentIdolId = 'current_idol_id';
  static const String onboardingComplete = 'onboarding_complete';
}

/// Session controller provider.
final sessionControllerProvider =
    StateNotifierProvider<SessionController, SessionState>((ref) {
  return SessionController(
    tokenStore: ref.watch(tokenStoreProvider),
    meRepository: ref.watch(meRepositoryProvider),
    authController: ref.watch(authControllerProvider.notifier),
  );
});

/// Provider for current user (convenience).
final currentUserProvider = Provider<Me?>((ref) {
  final session = ref.watch(sessionControllerProvider);
  return switch (session) {
    SessionNeedsOnboarding(:final user) => user,
    SessionReady(:final user) => user,
    _ => null,
  };
});

/// Provider for current idol ID.
final currentIdolIdProvider = Provider<String?>((ref) {
  final session = ref.watch(sessionControllerProvider);
  return switch (session) {
    SessionReady(:final currentIdolId) => currentIdolId,
    _ => null,
  };
});

/// Controller for managing user session and app initialization.
class SessionController extends StateNotifier<SessionState> {
  SessionController({
    required TokenStore tokenStore,
    required MeRepository meRepository,
    required AuthController authController,
  })  : _tokenStore = tokenStore,
        _meRepository = meRepository,
        _authController = authController,
        super(const SessionInitializing());

  final TokenStore _tokenStore;
  final MeRepository _meRepository;
  final AuthController _authController;

  SharedPreferences? _prefs;

  /// Initialize session on app start.
  Future<void> initialize() async {
    debugPrint('🔑 SessionController.initialize() called');
    state = const SessionInitializing();
    _prefs = await SharedPreferences.getInstance();

    // Check if we have a valid token
    final hasToken = await _tokenStore.hasValidToken();
    debugPrint('🔑 hasValidToken: $hasToken');
    if (!hasToken) {
      debugPrint('🔑 No token, setting SessionUnauthenticated');
      state = const SessionUnauthenticated();
      return;
    }

    // Fetch user profile
    try {
      debugPrint('🔑 Fetching user profile...');
      final user = await _meRepository.getMe();
      debugPrint('🔑 Got user: ${user.email}');
      await _determineSessionState(user);
      debugPrint('🔑 Final state: ${state.runtimeType}');
    } catch (e) {
      debugPrint('🔑 Error fetching profile: $e');
      if (e is ApiError && e.isAuthError) {
        // Token is invalid, clear and show auth
        await _tokenStore.clear();
        state = const SessionUnauthenticated();
      } else if (e.toString().contains('401')) {
        // Also handle raw 401 strings
        await _tokenStore.clear();
        state = const SessionUnauthenticated();
      } else {
        state = SessionError(message: e.toString());
      }
    }
  }

  /// Determine session state based on user profile.
  Future<void> _determineSessionState(Me user) async {
    debugPrint('🔑 _determineSessionState called');
    
    // Check if onboarding is complete
    final needsOnboarding = _needsOnboarding(user);
    debugPrint('🔑 needsOnboarding: $needsOnboarding');

    if (needsOnboarding) {
      debugPrint('🔑 Setting SessionNeedsOnboarding');
      state = SessionNeedsOnboarding(user: user);
      return;
    }

    // Get current idol ID
    final currentIdolId = _prefs?.getString(SessionKeys.currentIdolId);
    debugPrint('🔑 currentIdolId: $currentIdolId');
    if (currentIdolId == null) {
      // Has profile but no idol selected
      debugPrint('🔑 No idol ID, setting SessionNeedsOnboarding');
      state = SessionNeedsOnboarding(user: user);
      return;
    }

    debugPrint('🔑 Setting SessionReady');
    state = SessionReady(user: user, currentIdolId: currentIdolId);
  }

  /// Check if user needs onboarding.
  bool _needsOnboarding(Me user) {
    // Check if onboarding was completed
    final onboardingComplete =
        _prefs?.getBool(SessionKeys.onboardingComplete) ?? false;
    if (!onboardingComplete) return true;

    // Check required profile fields
    if (user.fullName == null || user.fullName!.isEmpty) return true;
    if (user.birthDate == null) return true;
    if (user.interests.isEmpty) return true;

    return false;
  }

  /// Called after successful login/register.
  /// Does NOT reset to SessionInitializing to avoid redirect to splash.
  Future<void> onAuthenticated() async {
    debugPrint('🔑 SessionController.onAuthenticated() called');
    _prefs ??= await SharedPreferences.getInstance();

    // Fetch user profile without resetting state to Initializing
    try {
      debugPrint('🔑 Fetching user profile after auth...');
      final user = await _meRepository.getMe();
      debugPrint('🔑 Got user: ${user.email}');
      await _determineSessionState(user);
      debugPrint('🔑 Final state after auth: ${state.runtimeType}');
    } on ApiError catch (e) {
      debugPrint('🔑 onAuthenticated ApiError: ${e.message}');
      if (e.isAuthError) {
        await _tokenStore.clear();
        state = const SessionUnauthenticated();
      } else {
        // Still authenticated but error fetching profile - go to onboarding
        debugPrint('🔑 Setting SessionNeedsOnboarding with empty user');
        state = SessionNeedsOnboarding(user: const Me(id: '', email: ''));
      }
    } catch (e) {
      debugPrint('🔑 onAuthenticated Error: $e');
      // Still authenticated but error - go to onboarding with empty user
      state = SessionNeedsOnboarding(user: const Me(id: '', email: ''));
    }
  }

  /// Called after logout.
  void onLogout() {
    _prefs?.remove(SessionKeys.currentIdolId);
    _prefs?.remove(SessionKeys.onboardingComplete);
    state = const SessionUnauthenticated();
  }

  /// Update user profile in session.
  /// Called after profile changes - keeps user in onboarding flow.
  Future<void> updateUser(Me user) async {
    debugPrint('🔑 SessionController.updateUser called');
    debugPrint('🔑 Current state: ${state.runtimeType}');
    
    // Ensure prefs is initialized
    _prefs ??= await SharedPreferences.getInstance();
    
    // During onboarding, keep user in SessionNeedsOnboarding
    // Don't call _determineSessionState which would check for idol
    final currentState = state;
    if (currentState is SessionNeedsOnboarding) {
      // Stay in onboarding with updated user
      debugPrint('🔑 Keeping SessionNeedsOnboarding state');
      state = SessionNeedsOnboarding(user: user);
    } else {
      debugPrint('🔑 Calling _determineSessionState');
      await _determineSessionState(user);
    }
    debugPrint('🔑 New state: ${state.runtimeType}');
  }

  /// Set current idol ID (after onboarding).
  Future<void> setCurrentIdolId(String idolId) async {
    await _prefs?.setString(SessionKeys.currentIdolId, idolId);

    // Re-evaluate session state
    final currentState = state;
    if (currentState is SessionNeedsOnboarding) {
      state = SessionReady(user: currentState.user, currentIdolId: idolId);
    } else if (currentState is SessionReady) {
      state = SessionReady(user: currentState.user, currentIdolId: idolId);
    }
  }

  /// Mark onboarding as complete.
  Future<void> completeOnboarding() async {
    await _prefs?.setBool(SessionKeys.onboardingComplete, true);
  }

  /// Refresh user profile.
  Future<void> refreshUser() async {
    try {
      final user = await _meRepository.getMe();
      await _determineSessionState(user);
    } catch (e) {
      // Keep current state on error
    }
  }

  /// Handle auth error (e.g., token expired).
  Future<void> handleAuthError() async {
    await _authController.logout();
    onLogout();
  }

  /// Calculate user's current age.
  int? get userAge {
    final user = switch (state) {
      SessionNeedsOnboarding(:final user) => user,
      SessionReady(:final user) => user,
      _ => null,
    };

    if (user?.birthDate == null) return null;
    final today = DateTime.now();
    final birthDate = user!.birthDate!;
    int age = today.year - birthDate.year;
    if (today.month < birthDate.month ||
        (today.month == birthDate.month && today.day < birthDate.day)) {
      age--;
    }
    return age;
  }
}
