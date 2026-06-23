import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/dio_client.dart';
import '../models/me_models.dart';

/// Me repository provider.
final meRepositoryProvider = Provider<MeRepository>((ref) {
  return MeRepository(dioClient: ref.watch(dioClientProvider));
});

/// Repository for current user operations.
class MeRepository {
  MeRepository({required DioClient dioClient}) : _dioClient = dioClient;

  final DioClient _dioClient;

  /// Get current user profile.
  Future<Me> getMe() async {
    final response = await _dioClient.get('/me');
    return Me.fromJson(response.data);
  }

  /// Update current user profile.
  Future<Me> updateMe({
    String? fullName,
    DateTime? birthDate,
    List<String>? interests,
    String? timezone,
  }) async {
    final request = UpdateMeRequest(
      fullName: fullName,
      birthDate: birthDate,
      interests: interests,
      timezone: timezone,
    );

    final response = await _dioClient.patch('/me', data: request.toJson());

    return Me.fromJson(response.data);
  }

  /// Update user interests only.
  Future<Me> updateInterests(List<String> interests) async {
    return updateMe(interests: interests);
  }

  /// Complete onboarding profile setup.
  Future<Me> completeOnboarding({
    required String fullName,
    required DateTime birthDate,
    required List<String> interests,
  }) async {
    return updateMe(
      fullName: fullName,
      birthDate: birthDate,
      interests: interests,
    );
  }
}
