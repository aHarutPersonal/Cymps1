import 'dart:io' show Platform;
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Token storage provider.
final tokenStoreProvider = Provider<TokenStore>((ref) {
  return TokenStore();
});

/// Secure token storage using platform-specific secure storage.
///
/// - iOS: Keychain
/// - Android: EncryptedSharedPreferences
/// - macOS/Web: SharedPreferences (Fallback due to local keychain limits)
class TokenStore {
  TokenStore()
    : _storage = const FlutterSecureStorage(
        aOptions: AndroidOptions(
          encryptedSharedPreferences: true,
          resetOnError: true,
        ),
        iOptions: IOSOptions(
          accessibility: KeychainAccessibility.first_unlock_this_device,
          synchronizable: false,
        ),
      );

  final FlutterSecureStorage _storage;

  // Storage keys
  static const _keyAccessToken = 'cmpys_access_token';
  static const _keyRefreshToken = 'cmpys_refresh_token';
  static const _keyTokenExpiry = 'cmpys_token_expiry';
  static const _keyUserId = 'cmpys_user_id';
  static const _keyTokenApiBase = 'cmpys_token_api_base';

  bool get _usePrefs {
    if (kIsWeb) return true;
    try {
      if (Platform.isMacOS) return true;
    } catch (_) {}
    return false;
  }

  Future<void> _write(String key, String value) async {
    if (_usePrefs) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(key, value);
    } else {
      await _storage.write(key: key, value: value);
    }
  }

  Future<String?> _read(String key) async {
    if (_usePrefs) {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getString(key);
    } else {
      return await _storage.read(key: key);
    }
  }

  Future<void> _delete(String key) async {
    if (_usePrefs) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(key);
    } else {
      await _storage.delete(key: key);
    }
  }

  // ============================================
  // ACCESS TOKEN
  // ============================================

  /// Save access token to secure storage.
  Future<void> saveAccessToken(String token) async {
    await _write(_keyAccessToken, token);
  }

  /// Read access token from secure storage.
  /// Returns null if not found.
  Future<String?> readAccessToken() async {
    return _read(_keyAccessToken);
  }

  /// Delete access token.
  Future<void> deleteAccessToken() async {
    await _delete(_keyAccessToken);
  }

  // ============================================
  // REFRESH TOKEN
  // ============================================

  /// Save refresh token to secure storage.
  Future<void> saveRefreshToken(String token) async {
    await _write(_keyRefreshToken, token);
  }

  /// Read refresh token from secure storage.
  Future<String?> readRefreshToken() async {
    return _read(_keyRefreshToken);
  }

  /// Delete refresh token.
  Future<void> deleteRefreshToken() async {
    await _delete(_keyRefreshToken);
  }

  // ============================================
  // TOKEN EXPIRY
  // ============================================

  /// Save token expiry timestamp.
  Future<void> saveTokenExpiry(DateTime expiry) async {
    await _write(_keyTokenExpiry, expiry.millisecondsSinceEpoch.toString());
  }

  /// Read token expiry timestamp.
  Future<DateTime?> readTokenExpiry() async {
    final value = await _read(_keyTokenExpiry);
    if (value == null) return null;
    return DateTime.fromMillisecondsSinceEpoch(int.parse(value));
  }

  /// Check if token is expired.
  Future<bool> isTokenExpired() async {
    final expiry = await readTokenExpiry();
    if (expiry == null) return true;
    return DateTime.now().isAfter(expiry);
  }

  // ============================================
  // USER ID
  // ============================================

  /// Save user ID.
  Future<void> saveUserId(String userId) async {
    await _write(_keyUserId, userId);
  }

  /// Read user ID.
  Future<String?> readUserId() async {
    return _read(_keyUserId);
  }

  // ============================================
  // CONVENIENCE METHODS
  // ============================================

  /// Save both access and refresh tokens.
  Future<void> saveTokens({
    required String accessToken,
    String? refreshToken,
    DateTime? expiry,
    String? apiBase,
  }) async {
    await saveAccessToken(accessToken);
    if (refreshToken != null) {
      await saveRefreshToken(refreshToken);
    }
    if (expiry != null) {
      await saveTokenExpiry(expiry);
    }
    if (apiBase != null) {
      await _write(_keyTokenApiBase, apiBase);
    }
  }

  /// Invalidate stored tokens if they were issued by a different API base than
  /// `currentApiBase`. Prevents the cross-environment auth loop where a token
  /// from a local backend (different JWT secret) keeps 401'ing prod and never
  /// gets cleaned up.
  ///
  /// An unbound token (saved before this guard existed, or written by an
  /// older app version) is treated as untrusted and wiped — better one
  /// re-login than a loop nobody can recover from.
  Future<void> ensureTokenBoundTo(String currentApiBase) async {
    final saved = await _read(_keyTokenApiBase);
    if (saved != currentApiBase) {
      await clear();
      await _write(_keyTokenApiBase, currentApiBase);
    }
  }

  /// Check if user has a valid (non-expired) token.
  Future<bool> hasValidToken() async {
    final token = await readAccessToken();
    if (token == null || token.isEmpty) return false;

    final expiry = await readTokenExpiry();
    if (expiry != null && DateTime.now().isAfter(expiry)) {
      return false;
    }

    return true;
  }

  /// Check if user is authenticated (has any token).
  Future<bool> isAuthenticated() async {
    final token = await readAccessToken();
    return token != null && token.isNotEmpty;
  }

  /// Clear all stored tokens and user data.
  Future<void> clear() async {
    await Future.wait([
      _delete(_keyAccessToken),
      _delete(_keyRefreshToken),
      _delete(_keyTokenExpiry),
      _delete(_keyUserId),
      _delete(_keyTokenApiBase),
    ]);
  }

  /// Clear all data from secure storage (full reset).
  Future<void> clearAll() async {
    if (_usePrefs) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.clear();
    } else {
      await _storage.deleteAll();
    }
  }
}
