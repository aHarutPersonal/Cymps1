import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../app/env.dart';
import '../../../core/network/api_error.dart';
import '../../../core/storage/token_store.dart';
import '../../cmpys/state/cmpys_store.dart';
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
  const SessionReady({required this.user, required this.currentIdolId});
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
        resetLocalAccountData: () =>
            ref.read(cmpysStoreProvider.notifier).reset(),
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
    Future<void> Function()? resetLocalAccountData,
  }) : _tokenStore = tokenStore,
       _meRepository = meRepository,
       _authController = authController,
       _resetLocalAccountData = resetLocalAccountData,
       super(const SessionInitializing());

  final TokenStore _tokenStore;
  final MeRepository _meRepository;
  final AuthController _authController;
  final Future<void> Function()? _resetLocalAccountData;

  SharedPreferences? _prefs;

  bool _isMissingUserError(Object error) {
    if (error is ApiError) {
      return error.isAuthError || error.isNotFoundError;
    }

    final message = error.toString().toLowerCase();
    return message.contains('401') || message.contains('404');
  }

  Future<void> _resetToUnauthenticated() async {
    _prefs ??= await SharedPreferences.getInstance();
    await _tokenStore.clear();
    await _prefs?.remove(SessionKeys.currentIdolId);
    await _prefs?.remove(SessionKeys.onboardingComplete);
    state = const SessionUnauthenticated();
  }

  /// Initialize session on app start.
  Future<void> initialize() async {
    debugPrint('🔑 SessionController.initialize() called');
    state = const SessionInitializing();
    _prefs = await SharedPreferences.getInstance();

    // Drop any token issued by a different API base (e.g. local dev token
    // surviving a switch to production) before it triggers a 401 loop.
    await _tokenStore.ensureTokenBoundTo(Env.apiBaseUrl);

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
      if (_isMissingUserError(e)) {
        await _resetToUnauthenticated();
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

    // Onboarding is complete → the user is ready. The active mentor is hydrated
    // from the backend on the home screen (getLatestSession → syncFromSession),
    // so a missing locally-cached idol id must NOT bounce a returning user back
    // into onboarding — that was the defect that lost their session on relaunch.
    // currentIdolId is informational only (no consumers read it); default to ''.
    final currentIdolId = _prefs?.getString(SessionKeys.currentIdolId) ?? '';
    debugPrint('🔑 currentIdolId: $currentIdolId');
    debugPrint('🔑 Setting SessionReady');
    state = SessionReady(user: user, currentIdolId: currentIdolId);
  }

  /// Check if user needs onboarding.
  ///
  /// The agentic onboarding flow is the source of truth and persists this flag
  /// (and the chosen idol) on completion. We intentionally do NOT gate on the
  /// legacy backend profile fields (fullName/birthDate/interests): the agentic
  /// flow never PATCHes them to `/me`, so requiring them here bounced every
  /// already-onboarded user back into onboarding on every relaunch.
  bool _needsOnboarding(Me user) {
    return !(_prefs?.getBool(SessionKeys.onboardingComplete) ?? false);
  }

  /// Called after successful login/register.
  /// Does NOT reset to SessionInitializing to avoid redirect to splash.
  Future<void> onAuthenticated({bool isNewRegistration = false}) async {
    debugPrint('🔑 SessionController.onAuthenticated() called');
    _prefs ??= await SharedPreferences.getInstance();

    // Registration always creates a distinct account. Device-local state is
    // not user-scoped, so carrying it across would make the new user inherit
    // the previous user's completed-onboarding flag, mentor, name, notes, and
    // progress and would route them directly to Home. Clear it before /me is
    // evaluated so the new account deterministically starts onboarding.
    if (isNewRegistration) {
      await _prefs?.remove(SessionKeys.currentIdolId);
      await _prefs?.remove(SessionKeys.onboardingComplete);
      await _resetLocalAccountData?.call();
    }

    // Fetch user profile without resetting state to Initializing
    try {
      debugPrint('🔑 Fetching user profile after auth...');
      final user = await _meRepository.getMe();
      debugPrint('🔑 Got user: ${user.email}');
      await _determineSessionState(user);
      debugPrint('🔑 Final state after auth: ${state.runtimeType}');
    } on ApiError catch (e) {
      debugPrint('🔑 onAuthenticated ApiError: ${e.message}');
      if (_isMissingUserError(e)) {
        await _resetToUnauthenticated();
      } else {
        // Still authenticated but error fetching profile - go to onboarding
        debugPrint('🔑 Setting SessionNeedsOnboarding with empty user');
        state = SessionNeedsOnboarding(
          user: const Me(id: '', email: ''),
        );
      }
    } catch (e) {
      debugPrint('🔑 onAuthenticated Error: $e');
      // Still authenticated but error - go to onboarding with empty user
      state = SessionNeedsOnboarding(
        user: const Me(id: '', email: ''),
      );
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
    _prefs ??= await SharedPreferences.getInstance();
    await _prefs?.setString(SessionKeys.currentIdolId, idolId);

    // Re-evaluate session state
    final currentState = state;
    if (currentState is SessionNeedsOnboarding) {
      state = SessionReady(user: currentState.user, currentIdolId: idolId);
    } else if (currentState is SessionReady) {
      state = SessionReady(user: currentState.user, currentIdolId: idolId);
    }
  }

  /// Clear stale idol selection and return the user to idol selection.
  Future<void> clearCurrentIdolId() async {
    _prefs ??= await SharedPreferences.getInstance();
    await _prefs?.remove(SessionKeys.currentIdolId);

    final currentState = state;
    if (currentState is SessionReady) {
      state = SessionNeedsOnboarding(user: currentState.user);
    }
  }

  /// Mark onboarding as complete.
  Future<void> completeOnboarding() async {
    _prefs ??= await SharedPreferences.getInstance();
    await _prefs?.setBool(SessionKeys.onboardingComplete, true);
  }

  /// Refresh user profile.
  Future<void> refreshUser() async {
    try {
      final user = await _meRepository.getMe();
      await _determineSessionState(user);
    } catch (e) {
      if (_isMissingUserError(e)) {
        await _resetToUnauthenticated();
      }
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
