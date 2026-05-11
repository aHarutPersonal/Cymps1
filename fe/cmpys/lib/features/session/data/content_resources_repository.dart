import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/dio_client.dart';
import '../models/content_resource.dart';

final contentResourcesRepositoryProvider = Provider<ContentResourcesRepository>(
  (ref) => ContentResourcesRepository(dioClient: ref.watch(dioClientProvider)),
);

class ContentResourcesRepository {
  ContentResourcesRepository({required DioClient dioClient})
    : _dioClient = dioClient;

  final DioClient _dioClient;

  Future<List<ContentResource>> listVaultResources() async {
    final response = await _dioClient.get('/content-resources/vault');
    final data = response.data as Map<String, dynamic>;
    final resources = data['resources'] as List? ?? [];
    return resources
        .map((json) => ContentResource.fromJson(json as Map<String, dynamic>))
        .toList();
  }

  Future<void> saveResource(String resourceId) async {
    await _dioClient.post('/content-resources/$resourceId/save', data: {});
  }

  Future<void> unsaveResource(String resourceId) async {
    await _dioClient.delete('/content-resources/$resourceId/save');
  }

  Future<List<ContentHighlight>> listHighlights(String resourceId) async {
    final response = await _dioClient.get(
      '/content-resources/$resourceId/highlights',
    );
    final data = response.data as Map<String, dynamic>;
    final highlights = data['highlights'] as List? ?? [];
    return highlights
        .map((json) => ContentHighlight.fromJson(json as Map<String, dynamic>))
        .toList();
  }

  Future<ContentHighlight> createHighlight(
    String resourceId, {
    Map<String, dynamic>? locatorJson,
    String? quoteText,
    String? noteText,
  }) async {
    final response = await _dioClient.post(
      '/content-resources/$resourceId/highlights',
      data: {
        if (locatorJson != null) 'locatorJson': locatorJson,
        if (quoteText != null && quoteText.trim().isNotEmpty)
          'quoteText': quoteText.trim(),
        if (noteText != null && noteText.trim().isNotEmpty)
          'noteText': noteText.trim(),
      },
    );
    return ContentHighlight.fromJson(response.data as Map<String, dynamic>);
  }

  Future<void> deleteHighlight(String resourceId, String highlightId) async {
    await _dioClient.delete(
      '/content-resources/$resourceId/highlights/$highlightId',
    );
  }

  Future<ContentResource> updateProgress(
    String resourceId, {
    required int progressPercent,
    Map<String, dynamic>? cursorJson,
    bool? completed,
  }) async {
    final response = await _dioClient.patch(
      '/content-resources/$resourceId/progress',
      data: {
        'progressPercent': progressPercent,
        if (cursorJson != null) 'cursorJson': cursorJson,
        if (completed != null) 'completed': completed,
      },
    );
    return ContentResource.fromJson(response.data as Map<String, dynamic>);
  }
}
