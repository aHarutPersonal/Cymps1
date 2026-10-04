import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_error.dart';
import '../../../core/network/dio_client.dart';
import '../../../core/storage/token_store.dart';

final passwordRecoveryRepositoryProvider = Provider<PasswordRecoveryRepository>(
  (ref) => PasswordRecoveryRepository(
    ref.watch(dioClientProvider),
    tokenStore: ref.watch(tokenStoreProvider),
  ),
);

/// Public recovery endpoints. Codes/passwords stay in POST bodies and are
/// never persisted or exchanged for a session by the client.
class PasswordRecoveryRepository {
  PasswordRecoveryRepository(this._client, {required TokenStore tokenStore})
    : _tokenStore = tokenStore;
  final DioClient _client;
  final TokenStore _tokenStore;

  Future<bool> isAvailable() async {
    try {
      final response = await _client.get(
        '/auth/password-reset/availability',
        skipAuth: true,
      );
      final data = response.data;
      if (data is! Map || data['available'] is! bool) {
        throw const FormatException('Invalid recovery availability response');
      }
      return data['available'] as bool;
    } on ApiError catch (error) {
      // An older server has no recovery routes yet.
      if (error.statusCode == 404) return false;
      rethrow;
    }
  }

  Future<void> requestCode(String email) async {
    final response = await _client.post(
      '/auth/password-reset/request',
      data: {'email': email.trim()},
      skipAuth: true,
    );
    if (response.statusCode != 202) {
      throw const FormatException('Recovery request was not accepted');
    }
  }

  Future<void> confirm({
    required String token,
    required String password,
  }) async {
    final response = await _client.post(
      '/auth/password-reset/confirm',
      data: {'token': token.trim(), 'password': password},
      skipAuth: true,
    );
    if (response.statusCode != 204) {
      throw const FormatException('Recovery was not confirmed');
    }
    await _tokenStore.clear();
  }
}
