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
