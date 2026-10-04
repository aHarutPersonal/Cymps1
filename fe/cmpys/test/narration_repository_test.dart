import 'package:cmpys/core/network/dio_client.dart';
import 'package:cmpys/features/session/data/content_resources_repository.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

class _NarrationClient extends Fake implements DioClient {
  Options? options;
  dynamic requestData;
  Map<String, dynamic> responseData = {
    'audioUrl': '/media/narration/clip.mp3',
    'voice': 'expressive',
    'alignment': [],
  };
  @override
  String get baseUrl => 'https://app.example.test/api/v1';
  @override
  Future<Response<T>> post<T>(
    String path, {
    dynamic data,
    Map<String, dynamic>? queryParameters,
    Options? options,
    bool skipAuth = false,
  }) async {
    this.options = options;
    requestData = data;
    return Response<T>(
      requestOptions: RequestOptions(path: path),
      data: responseData as T,
    );
  }
}

void main() {
  test(
    'transcription keeps valid UTF-16 cues and skips malformed ranges',
    () async {
      final client = _NarrationClient()
        ..responseData = {
          'audioUrl': '/media/narration/existing.wav',
          'durationMs': 2000,
          'alignmentSource': 'transcription',
          'alignmentGranularity': 'word',
          'offsetEncoding': 'utf16',
          'alignment': [
            {'start': 7, 'end': 11, 'startMs': 1000, 'endMs': 1300},
            null,
            {'start': 0, 'end': 2, 'startMs': 'bad', 'endMs': 100},
            {'start': 3, 'end': 6, 'startMs': 200, 'endMs': 500},
            {'start': 7, 'end': 50, 'startMs': 700, 'endMs': 800},
            {'start': 7, 'end': 11, 'startMs': -1, 'endMs': 100},
            {'start': 7, 'end': 11, 'startMs': 1500, 'endMs': 2500},
            {'start': 7, 'end': 11, 'startMs': double.nan, 'endMs': 1500},
            {'start': 7.5, 'end': 11, 'startMs': 1500, 'endMs': 1600},
            {'start': 7, 'end': 11, 'startMs': 1500, 'endMs': 1400},
          ],
        };
      final audio = await ContentResourcesRepository(
        dioClient: client,
      ).prepareNarration('book', text: '💡 One word.', style: 'expressive');
      expect(audio.alignmentSource, 'transcription');
      expect(
        audio.alignmentGranularity,
        BookNarrationAlignmentGranularity.word,
      );
      expect(audio.alignment.map((cue) => cue.start), [3, 7]);
      expect(audio.alignment.map((cue) => cue.startTime.inMilliseconds), [
        200,
        1000,
      ]);
      expect(audio.audioUri.path, '/media/narration/existing.wav');
    },
  );

  test(
    'overlapping cue groups are omitted rather than claiming an ambiguous word',
    () async {
      final client = _NarrationClient()
        ..responseData = {
          'audioUrl': '/media/narration/existing.wav',
          'durationMs': 2000,
          'alignmentSource': 'transcription',
          'alignmentGranularity': 'word',
          'offsetEncoding': 'utf16',
          'alignment': [
            {'start': 0, 'end': 3, 'startMs': 0, 'endMs': 1000},
            {'start': 4, 'end': 7, 'startMs': 200, 'endMs': 400},
            {'start': 8, 'end': 13, 'startMs': 500, 'endMs': 900},
            {'start': 14, 'end': 18, 'startMs': 1200, 'endMs': 1800},
          ],
        };
      final audio = await ContentResourcesRepository(dioClient: client)
          .prepareNarration(
            'book',
            text: 'One two three four',
            style: 'expressive',
          );
      expect(audio.alignment, hasLength(1));
      expect(audio.alignment.single.start, 14);
    },
  );

  test(
    'invalid transcription remains playable without timing claims',
    () async {
      final client = _NarrationClient()
        ..responseData = {
          'audioUrl': '/media/narration/existing.wav',
          'alignmentSource': 'transcription',
          'alignmentGranularity': 'word',
          'alignment': [
            false,
            {'start': 99, 'end': 100, 'startMs': 1, 'endMs': 2},
          ],
        };
      final audio = await ContentResourcesRepository(
        dioClient: client,
      ).prepareNarration('book', text: 'One word.', style: 'expressive');
      expect(audio.alignment, isEmpty);
      expect(
        audio.alignmentGranularity,
        BookNarrationAlignmentGranularity.none,
      );
    },
  );

  test('narration allows synthesis and timing passes to finish', () async {
    final client = _NarrationClient();
    final audio = await ContentResourcesRepository(dioClient: client)
        .prepareNarration(
          'book',
          text: 'A short passage.',
          style: 'warm',
          narratorProfile: 'expressive_narrator',
        );
    expect(client.options?.receiveTimeout, const Duration(seconds: 90));
    expect(client.requestData, {
      'text': 'A short passage.',
      'style': 'warm',
      'narratorProfile': 'expressive_narrator',
    });
    expect(
      audio.audioUri.toString(),
      'https://app.example.test/media/narration/clip.mp3',
    );
    expect(audio.alignment, isEmpty);
  });

  test('Gemini WAV with no timestamps remains playable and untimed', () async {
    final client = _NarrationClient()
      ..responseData = {
        'audioUrl': '/media/narration/gemini-clip.wav',
        'provider': 'gemini',
        'model': 'gemini-3.8-flash-tts',
        'voice': 'Sulafat',
        'durationMs': 16320,
        'alignment': [],
        'alignmentSource': 'none',
        'alignmentGranularity': 'none',
      };
    final audio = await ContentResourcesRepository(
      dioClient: client,
    ).prepareNarration('book', text: 'A useful passage.', style: 'expressive');
    expect(
      audio.audioUri.toString(),
      'https://app.example.test/media/narration/gemini-clip.wav',
    );
    expect(audio.provider, 'gemini');
    expect(audio.voice, 'Sulafat');
    expect(audio.duration, const Duration(milliseconds: 16320));
    expect(audio.alignment, isEmpty);
    expect(audio.alignmentSource, 'none');
    expect(audio.alignmentGranularity, BookNarrationAlignmentGranularity.none);
    // Inconsistent metadata cannot advertise timing when there are no cues.
    expect(
      BookNarrationAlignmentGranularity.fromApi('word', hasAlignment: false),
      BookNarrationAlignmentGranularity.none,
    );
  });
}
