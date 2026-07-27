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

  Future<ContentResource> getResource(String resourceId) async {
    final response = await _dioClient.get('/content-resources/$resourceId');
    return ContentResource.fromJson(response.data as Map<String, dynamic>);
  }

  Future<BookNarrationAudio> prepareNarration(
    String resourceId, {
    required String text,
    required String style,
    String? narratorProfile,
  }) async {
    final response = await _dioClient.post(
      '/content-resources/$resourceId/narration',
      data: {
        'text': text,
        'style': style,
        if (narratorProfile != null && narratorProfile.isNotEmpty)
          'narratorProfile': narratorProfile,
      },
    );
    final data = response.data as Map<String, dynamic>;
    final rawUrl = data['audioUrl']?.toString() ?? '';
    if (rawUrl.isEmpty) {
      throw const FormatException('Narration response has no audio URL');
    }
    final parsedUrl = Uri.parse(rawUrl);
    final base = Uri.parse(_dioClient.baseUrl);
    final origin = base.replace(path: '/', query: null, fragment: null);
    final offsetEncoding =
        data['offsetEncoding']?.toString().trim().toLowerCase() ?? '';
    final alignment =
        (data['alignment'] as List? ?? const [])
            .map(
              (raw) => BookNarrationCue.fromJson(
                raw as Map<String, dynamic>,
                sourceText: text,
                offsetEncoding: offsetEncoding,
              ),
            )
            .where(
              (cue) =>
                  cue.start >= 0 &&
                  cue.end > cue.start &&
                  cue.end <= text.length &&
                  cue.startTime >= Duration.zero &&
                  cue.endTime > cue.startTime,
            )
            .toList()
          ..sort((left, right) => left.startTime.compareTo(right.startTime));
    return BookNarrationAudio(
      audioUri: parsedUrl.hasScheme ? parsedUrl : origin.resolveUri(parsedUrl),
      style: data['style']?.toString() ?? style,
      voice: data['voice']?.toString() ?? '',
      voiceDisplayName:
          data['voiceDisplayName']?.toString().trim() ??
          data['voice']?.toString().trim() ??
          '',
      provider: data['provider']?.toString().trim() ?? '',
      model: data['model']?.toString().trim() ?? '',
      narratorProfile: data['narratorProfile']?.toString().trim() ?? '',
      narratorProfileLabel:
          data['narratorProfileLabel']?.toString().trim() ?? '',
      duration: switch (data['durationMs']) {
        final num milliseconds => Duration(milliseconds: milliseconds.round()),
        _ => null,
      },
      alignment: alignment,
      alignmentSource:
          data['alignmentSource']?.toString().trim() ??
          (alignment.isEmpty ? 'none' : 'transcription'),
      alignmentGranularity: BookNarrationAlignmentGranularity.fromApi(
        data['alignmentGranularity']?.toString(),
        hasAlignment: alignment.isNotEmpty,
      ),
      offsetEncoding: offsetEncoding.isEmpty
          ? 'unicode_codepoints'
          : offsetEncoding,
      sourceTextHash: data['sourceTextHash']?.toString().trim() ?? '',
      disclosure: data['disclosure']?.toString().trim() ?? '',
      isAiGenerated: data['isAiGenerated'] != false,
    );
  }

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

  Future<List<ContentResource>> listLibraryResources({
    String? kind,
    String? query,
    String? sort,
    int limit = 50,
    int offset = 0,
  }) async {
    final queryParams = <String, dynamic>{
      if (kind != null) 'kind': kind,
      if (query != null) 'q': query,
      if (sort != null) 'sort': sort,
      'limit': limit,
      'offset': offset,
    };
    final response = await _dioClient.get(
      '/content-resources/library',
      queryParameters: queryParams,
    );
    final data = response.data as Map<String, dynamic>;
    final resources = data['resources'] as List? ?? [];
    return resources
        .map((json) => ContentResource.fromJson(json as Map<String, dynamic>))
        .toList();
  }

  Future<ContentResource?> getContinueReading() async {
    final response = await _dioClient.get(
      '/content-resources/continue-reading',
    );
    if (response.data == null) return null;
    final data = response.data as Map<String, dynamic>;
    if (data.isEmpty) return null;
    final resource = data['resource'] as Map<String, dynamic>?;
    if (resource == null) return null;
    return ContentResource.fromJson(resource);
  }
}

class BookNarrationAudio {
  const BookNarrationAudio({
    required this.audioUri,
    required this.style,
    required this.voice,
    this.voiceDisplayName = '',
    this.provider = '',
    this.model = '',
    this.narratorProfile = '',
    this.narratorProfileLabel = '',
    required this.duration,
    required this.alignment,
    this.alignmentSource = 'none',
    this.alignmentGranularity = BookNarrationAlignmentGranularity.none,
    this.offsetEncoding = 'utf16',
    this.sourceTextHash = '',
    this.disclosure = '',
    required this.isAiGenerated,
  });

  final Uri audioUri;
  final String style;
  final String voice;
  final String voiceDisplayName;
  final String provider;
  final String model;
  final String narratorProfile;
  final String narratorProfileLabel;
  final Duration? duration;
  final List<BookNarrationCue> alignment;
  final String alignmentSource;
  final BookNarrationAlignmentGranularity alignmentGranularity;
  final String offsetEncoding;
  final String sourceTextHash;
  final String disclosure;
  final bool isAiGenerated;
}

enum BookNarrationAlignmentGranularity {
  none,
  word,
  phrase,
  sentence;

  factory BookNarrationAlignmentGranularity.fromApi(
    String? value, {
    required bool hasAlignment,
  }) {
    return switch (value?.trim().toLowerCase()) {
      'word' || 'words' => BookNarrationAlignmentGranularity.word,
      'phrase' ||
      'provider_segment' ||
      'segment' => BookNarrationAlignmentGranularity.phrase,
      'sentence' || 'sentences' => BookNarrationAlignmentGranularity.sentence,
      _ when hasAlignment => BookNarrationAlignmentGranularity.word,
      _ => BookNarrationAlignmentGranularity.none,
    };
  }

  bool get isExactTextRange => this != BookNarrationAlignmentGranularity.none;
}

class BookNarrationCue {
  const BookNarrationCue({
    required this.start,
    required this.end,
    required this.startTime,
    required this.endTime,
  });

  factory BookNarrationCue.fromJson(
    Map<String, dynamic> json, {
    String sourceText = '',
    String offsetEncoding = 'utf16',
  }) {
    var start = (json['start'] as num).toInt();
    var end = (json['end'] as num).toInt();
    if (sourceText.isNotEmpty &&
        offsetEncoding != 'utf16' &&
        offsetEncoding != 'utf-16') {
      start = _codePointOffsetToUtf16(sourceText, start);
      end = _codePointOffsetToUtf16(sourceText, end);
    }
    return BookNarrationCue(
      start: start,
      end: end,
      startTime: Duration(milliseconds: (json['startMs'] as num).round()),
      endTime: Duration(milliseconds: (json['endMs'] as num).round()),
    );
  }

  final int start;
  final int end;
  final Duration startTime;
  final Duration endTime;
}

int _codePointOffsetToUtf16(String text, int codePointOffset) {
  if (codePointOffset <= 0) return 0;
  var codePoints = 0;
  var utf16Offset = 0;
  for (final rune in text.runes) {
    if (codePoints >= codePointOffset) break;
    utf16Offset += rune > 0xFFFF ? 2 : 1;
    codePoints++;
  }
  return utf16Offset.clamp(0, text.length).toInt();
}
