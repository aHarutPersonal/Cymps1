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

  /// No draft has been loaded or edited yet. Follow a replaced mission only
  /// when the current step is the exact lesson the reader has open. The
  /// server still checks access, publication, prerequisites and the answer key.
  Future<({String artifact, LessonPracticeState state})?> refreshUnopened(
    String item,
    String step,
    String? previousArtifact,
    String lessonTitle,
    String lessonContent,
  ) async {
    if (lessonContent.trim().isEmpty) return null;
    final response = await client.get(
      '/plan-items/${Uri.encodeComponent(item)}/detailed',
    );
    final data = response.data as Map<String, dynamic>;
    final artifact =
        (data['artifact_job_id'] ?? data['artifactJobId']) as String?;
    if (artifact == null || artifact.isEmpty || artifact == previousArtifact) {
      return null;
    }
    final matches = ((data['details'] as Map?)?['steps'] as List? ?? const [])
        .whereType<Map>()
        .where((s) => s['id'] == step)
        .toList();
    if (matches.length != 1 ||
        matches.single['title'] != lessonTitle ||
        matches.single['lesson_content'] != lessonContent) {
      return null;
    }
    return (artifact: artifact, state: await load(item, step, artifact));
  }

  /// A generation retry can replace the mission while retaining an identical
  /// lesson and answer key. Refresh only that exact immutable practice version
  /// and revision, so a stale screen never overwrites changed work.
  Future<({String artifact, LessonPracticeState state})?> refreshUnchanged(
    String item,
    String step,
    String? previousArtifact,
    LessonPracticeState previous,
  ) async {
    final version = previous.lessonVersion;
    if (version == null || version.isEmpty) return null;
    final response = await client.get(
      '/plan-items/${Uri.encodeComponent(item)}/detailed',
    );
    final data = response.data as Map<String, dynamic>;
    final artifact =
        (data['artifact_job_id'] ?? data['artifactJobId']) as String?;
    if (artifact == null || artifact.isEmpty || artifact == previousArtifact) {
      return null;
    }
    final current = await load(item, step, artifact);
    if (current.lessonVersion != version ||
        current.revision != previous.revision) {
      return null;
    }
    return (artifact: artifact, state: current);
  }

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
    Map<String, String> answers, {
    List<PracticeActivity> activities = const [],
  }) async {
    final r = await client.put(
      '${_path(item, step)}/draft',
      queryParameters: _query(artifact),
      // multi_choice answers go in the server's canonical spelling, so the
      // echoed draft equals this one. Numbers are sent as given: the screen
      // normalises only what the learner changed, never a stored spelling.
      data: {
        'revision': revision,
        'answers': canonicalMultiChoiceAnswers(activities, answers),
      },
    );
    return LessonPracticeState.fromJson(r.data as Map<String, dynamic>);
  }

  /// Reveals one field's hint ([fieldId] is "activity.field" and must belong
  /// to [activity]). The server records it in `hints[]` with that
  /// `field_id`, so "Hint used" survives a reload.
  Future<LessonPracticeState> fieldHint(
    String item,
    String step,
    String? artifact, {
    required int revision,
    required String activity,
    required String fieldId,
    required String requestId,
  }) async {
    final r = await client.post(
      '${_path(item, step)}/hint',
      queryParameters: {...?_query(artifact), 'field_id': fieldId},
      data: {
        'revision': revision,
        'activity_id': activity,
        'request_id': requestId,
      },
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
