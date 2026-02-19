import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/dio_client.dart';
import '../models/comparison_models.dart';

/// Comparison repository provider.
final comparisonRepositoryProvider = Provider<ComparisonRepository>((ref) {
  return ComparisonRepository(dioClient: ref.watch(dioClientProvider));
});

/// Repository for comparison operations.
class ComparisonRepository {
  ComparisonRepository({required DioClient dioClient}) : _dioClient = dioClient;

  final DioClient _dioClient;

  /// Get comparison between user and idol.
  ///
  /// [idolId] - The idol's unique identifier.
  /// [age] - Required age to compare at.
  /// [mode] - Comparison mode ('exact', 'up_to').
  /// Returns a [ComparisonResponse] with scores and breakdowns.
  Future<ComparisonResponse> getComparison(
    String idolId, {
    required int age,
    String mode = 'up_to',
  }) async {
    // Backend uses query params: /comparison?idolId={id}&age={age}&mode={mode}
    final queryParams = <String, dynamic>{
      'idolId': idolId,
      'age': age,
      'mode': mode,
    };

    final response = await _dioClient.get(
      '/comparison',
      queryParameters: queryParams,
    );

    return ComparisonResponse.fromJson(response.data);
  }

  /// Get comparison at a specific age.
  Future<ComparisonResponse> getComparisonAtAge(
    String idolId,
    int age, {
    String mode = 'up_to',
  }) async {
    return getComparison(idolId, age: age, mode: mode);
  }

  /// Get exact match comparison at a specific age.
  Future<ComparisonResponse> getExactComparison(String idolId, int age) async {
    return getComparison(idolId, age: age, mode: 'exact');
  }

  /// Refresh/regenerate comparison data.
  Future<ComparisonResponse> refreshComparison(String idolId) async {
    final response = await _dioClient.post('/comparison/$idolId/refresh');
    return ComparisonResponse.fromJson(response.data);
  }

  /// Get AI-enhanced comparison between user and idol.
  ///
  /// This uses an LLM to provide realistic, qualitative analysis.
  /// [idolId] - The idol's unique identifier.
  /// [age] - Required age to compare at.
  /// [mode] - Comparison mode ('exact', 'up_to').
  /// Returns a [ComparisonResponse] with AI-generated insights.
  Future<ComparisonResponse> getAIComparison(
    String idolId, {
    required int age,
    String mode = 'up_to',
  }) async {
    final queryParams = <String, dynamic>{
      'idolId': idolId,
      'age': age,
      'mode': mode,
    };

    final response = await _dioClient.get(
      '/comparison/ai',
      queryParameters: queryParams,
    );

    return ComparisonResponse.fromJson(response.data);
  }
}
