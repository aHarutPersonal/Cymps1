import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/dio_client.dart';
import '../../../core/storage/token_store.dart';
import '../models/auth_models.dart';

/// Auth repository provider.
final authRepositoryProvider = Provider<AuthRepository>((ref) {
  return AuthRepository(
    dioClient: ref.watch(dioClientProvider),
    tokenStore: ref.watch(tokenStoreProvider),
  );
});

/// Repository for authentication operations.
class AuthRepository {
  AuthRepository({required DioClient dioClient, required TokenStore tokenStore})
    : _dioClient = dioClient,
      _tokenStore = tokenStore;

  final DioClient _dioClient;
  final TokenStore _tokenStore;

  /// Register a new user.
  Future<AuthResponse> register({
    required String email,
    required String password,
    String? fullName,
  }) async {
    final request = RegisterRequest(
      email: email,
      password: password,
      fullName: fullName,
    );

    debugPrint('🔐 Register request: ${request.toJson()}');

    final response = await _dioClient.post(
      '/auth/register',
      data: request.toJson(),
      skipAuth: true,
    );

    debugPrint('🔐 Register response status: ${response.statusCode}');
    debugPrint('🔐 Register response data: ${response.data}');
    debugPrint('🔐 Register response type: ${response.data.runtimeType}');

    final data = response.data as Map<String, dynamic>?;
    if (data == null) {
      debugPrint('❌ Response data is null');
      throw Exception('Invalid response from server: data is null');
    }

    // Check for both camelCase and snake_case token keys
    final hasToken =
        data['access_token'] != null || data['accessToken'] != null;
    if (!hasToken) {
      debugPrint(
        '❌ No access token found. Available keys: ${data.keys.toList()}',
      );
      throw Exception('Invalid response from server: missing access token');
    }

    final authResponse = AuthResponse.fromJson(data);
    debugPrint(
      '✅ Registration successful! Token: ${authResponse.accessToken.substring(0, 20)}...',
    );
    await _saveTokens(authResponse);
    return authResponse;
  }

  /// Login with email and password.
  Future<AuthResponse> login({
    required String email,
    required String password,
  }) async {
    final request = LoginRequest(email: email, password: password);

    debugPrint('🔐 Login request for: $email');

    final response = await _dioClient.post(
      '/auth/login',
      data: request.toJson(),
      skipAuth: true,
    );

    debugPrint('🔐 Login response status: ${response.statusCode}');

    final data = response.data as Map<String, dynamic>?;
    if (data == null) {
      throw Exception('Invalid response from server: data is null');
    }

    // Check for both camelCase and snake_case token keys
    final hasToken =
        data['access_token'] != null || data['accessToken'] != null;
    if (!hasToken) {
      debugPrint(
        '❌ No access token found. Available keys: ${data.keys.toList()}',
      );
      throw Exception('Invalid response from server: missing access token');
    }

    final authResponse = AuthResponse.fromJson(data);
    debugPrint('✅ Login successful!');
    await _saveTokens(authResponse);
    return authResponse;
  }

  /// Login with OAuth provider (Google, Apple).
  Future<AuthResponse> loginWithOAuth({
    required String provider,
    required String idToken,
  }) async {
    final request = OAuthRequest(provider: provider, idToken: idToken);

    final response = await _dioClient.post(
      '/auth/oauth',
      data: request.toJson(),
      skipAuth: true,
    );

    final authResponse = AuthResponse.fromJson(response.data);
    await _saveTokens(authResponse);
    return authResponse;
  }

  /// Refresh the access token.
  Future<AuthResponse> refreshToken() async {
    final refreshToken = await _tokenStore.readRefreshToken();
    if (refreshToken == null) {
      throw Exception('No refresh token available');
    }

    final response = await _dioClient.post(
      '/auth/refresh',
      data: {'refreshToken': refreshToken},
      skipAuth: true,
    );

    final authResponse = AuthResponse.fromJson(response.data);
    await _saveTokens(authResponse);
    return authResponse;
  }

  /// Logout and clear tokens.
  Future<void> logout() async {
    try {
      await _dioClient.post('/auth/logout');
    } catch (_) {
      // Ignore errors, still clear local tokens
    } finally {
      await _tokenStore.clear();
    }
  }

  /// Check if user is authenticated.
  Future<bool> isAuthenticated() async {
    return _tokenStore.hasValidToken();
  }

  /// Save tokens from auth response.
  Future<void> _saveTokens(AuthResponse response) async {
    await _tokenStore.saveAccessToken(response.accessToken);
    if (response.refreshToken != null) {
      await _tokenStore.saveRefreshToken(response.refreshToken!);
    }
    if (response.expiresIn != null) {
      final expiry = DateTime.now().add(Duration(seconds: response.expiresIn!));
      await _tokenStore.saveTokenExpiry(expiry);
    }
  }
}
