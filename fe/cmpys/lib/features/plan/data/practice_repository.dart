import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/network/dio_client.dart';
import '../models/practice_models.dart';

final practiceRepositoryProvider = Provider(
  (ref) => PracticeRepository(ref.watch(dioClientProvider)),
);

class PracticeRepository {
  PracticeRepository(this.client);
  final DioClient client;

  String _path(String item, String step) =>
      '/plan-items/${Uri.encodeComponent(item)}/steps/${Uri.encodeComponent(step)}/practice';
  Map<String, dynamic>? _query(String? artifact) =>
      artifact == null ? null : {'artifactJobId': artifact};

  Future<LessonPracticeState> load(
    String item,
    String step,
    String? artifact,
  ) async {
    final r = await client.get(
      _path(item, step),
      queryParameters: _query(artifact),
    );
    return LessonPracticeState.fromJson(r.data as Map<String, dynamic>);
  }

  Future<LessonPracticeState> prepare(
    String item,
    String step,
    String? artifact,
  ) async {
    final r = await client.post(
      '${_path(item, step)}/prepare',
      queryParameters: _query(artifact),
      // Preparation has a 100-second server deadline and 120-second lease.
      // Leave transport margin so its terminal response reaches the screen.
      options: Options(receiveTimeout: const Duration(seconds: 130)),
    );
    return LessonPracticeState.fromJson(r.data as Map<String, dynamic>);
  }

  Future<LessonPracticeState> save(
    String item,
    String step,
    String? artifact,
    int revision,
    Map<String, String> answers,
  ) async {
    final r = await client.put(
      '${_path(item, step)}/draft',
      queryParameters: _query(artifact),
      data: {'revision': revision, 'answers': answers},
    );
    return LessonPracticeState.fromJson(r.data as Map<String, dynamic>);
  }

  Future<LessonPracticeState> act(
    String item,
    String step,
    String? artifact, {
    required String action,
    required int revision,
    required String activity,
    required String requestId,
    bool solution = false,
  }) async {
    final r = await client.post(
      '${_path(item, step)}/$action',
      queryParameters: {...?_query(artifact), if (solution) 'solution': true},
      data: {
        'revision': revision,
        'activity_id': activity,
        'request_id': requestId,
      },
      options: Options(receiveTimeout: const Duration(seconds: 70)),
    );
    return LessonPracticeState.fromJson(r.data as Map<String, dynamic>);
  }
}
