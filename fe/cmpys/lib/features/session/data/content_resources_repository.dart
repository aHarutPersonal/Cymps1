import 'package:dio/dio.dart';
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
      // Synthesis may take 60s, followed by up to two 10s timing passes.
      options: Options(receiveTimeout: const Duration(seconds: 90)),
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
    final duration = switch (data['durationMs']) {
      final num milliseconds when milliseconds.isFinite && milliseconds > 0 =>
        Duration(milliseconds: milliseconds.round()),
      _ => null,
    };
    final alignment = _parseNarrationAlignment(
      data['alignment'],
      text: text,
      offsetEncoding: offsetEncoding,
      duration: duration,
    );
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
      duration: duration,
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
      alignmentPending: data['alignmentPending'] == true,
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

// Bad timing must not make a valid recording unplayable or create guessed
// highlights. Preserve independently valid cues; leave real gaps elsewhere.
List<BookNarrationCue> _parseNarrationAlignment(
  Object? rawAlignment, {
  required String text,
  required String offsetEncoding,
  required Duration? duration,
}) {
  if (rawAlignment is! List) return const [];
  final utf16 = offsetEncoding == 'utf16' || offsetEncoding == 'utf-16';
  final sourceLength = utf16 ? text.length : text.runes.length;
  final candidates = <BookNarrationCue>[];
  for (final raw in rawAlignment) {
    if (raw is! Map) continue;
    final fields = [raw['start'], raw['end'], raw['startMs'], raw['endMs']];
    if (fields.any((value) => value is! num || !value.isFinite)) continue;
    final values = fields.cast<num>();
    if (values[0] != values[0].toInt() ||
        values[1] != values[1].toInt() ||
        values[0] < 0 ||
        values[1] <= values[0] ||
        values[1] > sourceLength ||
        values[2] < 0 ||
        values[3] <= values[2]) {
      continue;
    }
    final cue = BookNarrationCue.fromJson(
      {
        'start': values[0],
        'end': values[1],
        'startMs': values[2],
        'endMs': values[3],
      },
      sourceText: text,
      offsetEncoding: offsetEncoding,
    );
    bool splitsSurrogate(int offset) =>
        offset > 0 &&
        offset < text.length &&
        text.codeUnitAt(offset - 1) >= 0xD800 &&
        text.codeUnitAt(offset - 1) <= 0xDBFF &&
        text.codeUnitAt(offset) >= 0xDC00 &&
        text.codeUnitAt(offset) <= 0xDFFF;
    if (cue.endTime <= cue.startTime ||
        (duration != null && cue.endTime > duration) ||
        splitsSurrogate(cue.start) ||
        splitsSurrogate(cue.end)) {
      continue;
    }
    candidates.add(cue);
  }
  candidates.sort((a, b) => a.startTime.compareTo(b.startTime));
  final valid = <BookNarrationCue>[];
  for (var first = 0; first < candidates.length;) {
    var next = first + 1;
    var end = candidates[first].endTime;
    while (next < candidates.length && candidates[next].startTime < end) {
      if (candidates[next].endTime > end) end = candidates[next].endTime;
      next++;
    }
    // Every cue in an overlapping group is ambiguous, including a long cue
    // covering several otherwise disjoint words. Do not choose one by order.
    if (next == first + 1) valid.add(candidates[first]);
    first = next;
  }
  return valid;
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
    this.alignmentPending = false,
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
  final bool alignmentPending;
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
    if (!hasAlignment) return BookNarrationAlignmentGranularity.none;
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
