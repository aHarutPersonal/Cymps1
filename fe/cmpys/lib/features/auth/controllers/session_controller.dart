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
  static const String accountId = 'session_account_id';
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
        openLocalAccount: (accountId, unkeyedOwner) => ref
            .read(cmpysStoreProvider.notifier)
            .openAccount(accountId, unkeyedOwner: unkeyedOwner),
        closeLocalAccount: () =>
            ref.read(cmpysStoreProvider.notifier).closeAccount(),
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
    Future<void> Function(String accountId, String? unkeyedOwner)?
    openLocalAccount,
    Future<void> Function()? closeLocalAccount,
  }) : _tokenStore = tokenStore,
       _meRepository = meRepository,
       _authController = authController,
       _resetLocalAccountData = resetLocalAccountData,
       _openLocalAccount = openLocalAccount,
       _closeLocalAccount = closeLocalAccount,
       super(const SessionInitializing());

  final TokenStore _tokenStore;
  final MeRepository _meRepository;
  final AuthController _authController;

  /// Clears the signed-in account's data on this device (deliberate logout).
  final Future<void> Function()? _resetLocalAccountData;

  /// Opens an account's data on this device (the store is kept per account,
  /// owner decision 2). `unkeyedOwner` is the account an older build's
  /// unkeyed store belongs to (null: no one's, so it isn't adopted).
  final Future<void> Function(String accountId, String? unkeyedOwner)?
  _openLocalAccount;

  /// Closes the account's data without deleting it (involuntary sign-out).
  final Future<void> Function()? _closeLocalAccount;

  SharedPreferences? _prefs;

  bool _isMissingUserError(Object error) {
    if (error is ApiError) {
      return error.isAuthError || error.isNotFoundError;
    }

    final message = error.toString().toLowerCase();
    return message.contains('401') || message.contains('404');
  }

  /// Signs out. A [deliberate] logout clears the account's data on this
  /// device. An involuntary sign-out (no token, or a 401/404 for the
  /// profile) keeps it, with the account's device flags, so the same
  /// account signing back in gets its data; another account never sees it
  /// (the store is per account, and the flags are dropped on a switch).
  Future<void> _resetToUnauthenticated({bool deliberate = false}) async {
    _prefs ??= await SharedPreferences.getInstance();
    await _tokenStore.clear();
    if (deliberate) {
      await _prefs?.remove(SessionKeys.currentIdolId);
      await _prefs?.remove(SessionKeys.onboardingComplete);
      await _prefs?.remove(SessionKeys.accountId);
      await _resetLocalAccountData?.call();
    } else {
      await _closeLocalAccount?.call();
    }
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
    // /me and the shared interceptor validate/refresh stored credentials.
    // An expired access token alone does not mean the session has expired.
    final hasToken = await _tokenStore.isAuthenticated();
    debugPrint('🔑 hasValidToken: $hasToken');
    if (!hasToken) {
      debugPrint('🔑 No token, setting SessionUnauthenticated');
      await _resetToUnauthenticated();
      return;
    }

    // Fetch user profile
    try {
      debugPrint('🔑 Fetching user profile...');
      final user = await _meRepository.getMe();
      debugPrint('🔑 User profile loaded');
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
  ///
  /// The account's data on this device is opened before any state that
  /// shows a screen. A previous account's device flags never carry over;
  /// its data stays in its own store. An unkeyed store from an older build
  /// belongs to the account that was signed in, else to the first account
  /// that signs in, but never to a [newRegistration].
  Future<void> _determineSessionState(
    Me user, {
    bool resetUnowned = false,
    bool newRegistration = false,
  }) async {
    debugPrint('🔑 _determineSessionState called');

    final previousAccount = _prefs?.getString(SessionKeys.accountId);
    if ((previousAccount != null && previousAccount != user.id) ||
        (previousAccount == null && resetUnowned)) {
      await _prefs?.remove(SessionKeys.currentIdolId);
      await _prefs?.remove(SessionKeys.onboardingComplete);
    }
    await _openLocalAccount?.call(
      user.id,
      previousAccount ?? (newRegistration ? null : user.id),
    );
    await _prefs?.setString(SessionKeys.accountId, user.id);

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

    // Registration always creates a distinct account. The device flags are
    // not user-scoped, so carrying them across would route the new user
    // straight to Home with the previous user's onboarding. Clear them
    // before /me is evaluated so the new account deterministically starts
    // onboarding. Its data opens in its own, empty store
    // ([_determineSessionState]); the previous account's stays its own.
    if (isNewRegistration) {
      await _prefs?.remove(SessionKeys.currentIdolId);
      await _prefs?.remove(SessionKeys.onboardingComplete);
    }

    // Fetch user profile without resetting state to Initializing
    try {
      debugPrint('🔑 Fetching user profile after auth...');
      final user = await _meRepository.getMe();
      debugPrint('🔑 User profile loaded');
      await _determineSessionState(
        user,
        resetUnowned: !isNewRegistration,
        newRegistration: isNewRegistration,
      );
      debugPrint('🔑 Final state after auth: ${state.runtimeType}');
    } on ApiError catch (e) {
      debugPrint('🔑 onAuthenticated ApiError: ${e.message}');
      if (_isMissingUserError(e)) {
        await _resetToUnauthenticated();
      } else {
        state = SessionError(message: e.message);
      }
    } catch (e) {
      state = SessionError(message: e.toString());
    }
  }

  /// Called after a deliberate logout: the account's data on this device
  /// is cleared too.
  Future<void> onLogout() async {
    await _resetToUnauthenticated(deliberate: true);
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

  /// Handle auth error (e.g., token expired): an involuntary sign-out, so
  /// the account's data stays on this device.
  Future<void> handleAuthError() async {
    await _authController.logout();
    await _resetToUnauthenticated();
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
