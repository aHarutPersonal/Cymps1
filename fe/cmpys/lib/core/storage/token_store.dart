import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Token storage provider.
final tokenStoreProvider = Provider<TokenStore>((ref) {
  return TokenStore();
});

/// Secure token storage using platform-specific secure storage.
///
/// - iOS: Keychain
/// - Android: EncryptedSharedPreferences
///
/// Usage:
/// ```dart
/// final tokenStore = ref.read(tokenStoreProvider);
/// await tokenStore.saveAccessToken('your_token');
/// final token = await tokenStore.readAccessToken();
/// await tokenStore.clear();
/// ```
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

  // ============================================
  // ACCESS TOKEN
  // ============================================

  /// Save access token to secure storage.
  Future<void> saveAccessToken(String token) async {
    await _storage.write(key: _keyAccessToken, value: token);
  }

  /// Read access token from secure storage.
  /// Returns null if not found.
  Future<String?> readAccessToken() async {
    return _storage.read(key: _keyAccessToken);
  }

  /// Delete access token.
  Future<void> deleteAccessToken() async {
    await _storage.delete(key: _keyAccessToken);
  }

  // ============================================
  // REFRESH TOKEN
  // ============================================

  /// Save refresh token to secure storage.
  Future<void> saveRefreshToken(String token) async {
    await _storage.write(key: _keyRefreshToken, value: token);
  }

  /// Read refresh token from secure storage.
  Future<String?> readRefreshToken() async {
    return _storage.read(key: _keyRefreshToken);
  }

  /// Delete refresh token.
  Future<void> deleteRefreshToken() async {
    await _storage.delete(key: _keyRefreshToken);
  }

  // ============================================
  // TOKEN EXPIRY
  // ============================================

  /// Save token expiry timestamp.
  Future<void> saveTokenExpiry(DateTime expiry) async {
    await _storage.write(
      key: _keyTokenExpiry,
      value: expiry.millisecondsSinceEpoch.toString(),
    );
  }

  /// Read token expiry timestamp.
  Future<DateTime?> readTokenExpiry() async {
    final value = await _storage.read(key: _keyTokenExpiry);
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
    await _storage.write(key: _keyUserId, value: userId);
  }

  /// Read user ID.
  Future<String?> readUserId() async {
    return _storage.read(key: _keyUserId);
  }

  // ============================================
  // CONVENIENCE METHODS
  // ============================================

  /// Save both access and refresh tokens.
  Future<void> saveTokens({
    required String accessToken,
    String? refreshToken,
    DateTime? expiry,
  }) async {
    await saveAccessToken(accessToken);
    if (refreshToken != null) {
      await saveRefreshToken(refreshToken);
    }
    if (expiry != null) {
      await saveTokenExpiry(expiry);
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
      _storage.delete(key: _keyAccessToken),
      _storage.delete(key: _keyRefreshToken),
      _storage.delete(key: _keyTokenExpiry),
      _storage.delete(key: _keyUserId),
    ]);
  }

  /// Clear all data from secure storage (full reset).
  Future<void> clearAll() async {
    await _storage.deleteAll();
  }
}
