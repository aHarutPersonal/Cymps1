import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_error.dart';
import '../../../core/storage/token_store.dart';
import '../data/auth_repository.dart';
import '../models/auth_models.dart';

/// Auth state.
sealed class AuthState {
  const AuthState();
}

class AuthInitial extends AuthState {
  const AuthInitial();
}

class AuthLoading extends AuthState {
  const AuthLoading();
}

class AuthAuthenticated extends AuthState {
  const AuthAuthenticated({required this.accessToken});
  final String accessToken;
}

class AuthUnauthenticated extends AuthState {
  const AuthUnauthenticated();
}

class AuthError extends AuthState {
  const AuthError({required this.message});
  final String message;
}

/// Auth controller provider.
final authControllerProvider = StateNotifierProvider<AuthController, AuthState>(
  (ref) {
    return AuthController(
      authRepository: ref.watch(authRepositoryProvider),
      tokenStore: ref.watch(tokenStoreProvider),
    );
  },
);

/// Controller for authentication state and actions.
class AuthController extends StateNotifier<AuthState> {
  AuthController({
    required AuthRepository authRepository,
    required TokenStore tokenStore,
  }) : _authRepository = authRepository,
       _tokenStore = tokenStore,
       super(const AuthInitial());

  final AuthRepository _authRepository;
  final TokenStore _tokenStore;

  /// Check if user is authenticated on app start.
  Future<bool> checkAuth() async {
    final hasToken = await _tokenStore.hasValidToken();
    if (hasToken) {
      final token = await _tokenStore.readAccessToken();
      state = AuthAuthenticated(accessToken: token!);
      return true;
    }
    state = const AuthUnauthenticated();
    return false;
  }

  /// Login with email and password.
  Future<AuthResponse?> login({
    required String email,
    required String password,
  }) async {
    state = const AuthLoading();

    try {
      final response = await _authRepository.login(
        email: email,
        password: password,
      );
      state = AuthAuthenticated(accessToken: response.accessToken);
      return response;
    } on ApiError catch (e) {
      state = AuthError(message: e.message);
      return null;
    } catch (e) {
      state = AuthError(message: e.toString());
      return null;
    }
  }

  /// Register with email and password.
  Future<AuthResponse?> register({
    required String email,
    required String password,
    String? fullName,
  }) async {
    state = const AuthLoading();

    try {
      final response = await _authRepository.register(
        email: email,
        password: password,
        fullName: fullName,
      );
      state = AuthAuthenticated(accessToken: response.accessToken);
      return response;
    } on ApiError catch (e) {
      state = AuthError(message: e.message);
      return null;
    } catch (e) {
      state = AuthError(message: e.toString());
      return null;
    }
  }

  /// Login with OAuth (Google, Apple).
  Future<AuthResponse?> loginWithOAuth({
    required String provider,
    required String idToken,
  }) async {
    state = const AuthLoading();

    try {
      final response = await _authRepository.loginWithOAuth(
        provider: provider,
        idToken: idToken,
      );
      state = AuthAuthenticated(accessToken: response.accessToken);
      return response;
    } on ApiError catch (e) {
      state = AuthError(message: e.message);
      return null;
    } catch (e) {
      state = AuthError(message: e.toString());
      return null;
    }
  }

  /// Logout and clear tokens.
  Future<void> logout() async {
    await _authRepository.logout();
    state = const AuthUnauthenticated();
  }

  /// Clear error state.
  void clearError() {
    if (state is AuthError) {
      state = const AuthUnauthenticated();
    }
  }

  /// Check if currently authenticated.
  bool get isAuthenticated => state is AuthAuthenticated;
}
