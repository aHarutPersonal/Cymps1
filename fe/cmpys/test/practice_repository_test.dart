import 'package:cmpys/core/network/dio_client.dart';
import 'package:cmpys/features/plan/data/practice_repository.dart';
import 'package:cmpys/features/plan/models/practice_models.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

class _PracticeClient extends Fake implements DioClient {
  Options? options;
  String? path;
  Map<String, dynamic>? query;
  String? currentArtifact = 'new-artifact';
  String? currentVersion = 'same-content-and-key';
  int currentRevision = 4;
  List<Map<String, dynamic>> steps = [
    {'id': 'step', 'title': 'Title', 'lesson_content': 'Unchanged lesson'},
  ];
  final reads = <String>[];

  @override
  Future<Response<T>> get<T>(
    String path, {
    Map<String, dynamic>? queryParameters,
    Options? options,
    Duration? receiveTimeout,
    bool skipAuth = false,
  }) async {
    reads.add(path);
    query = queryParameters;
    return Response<T>(
      requestOptions: RequestOptions(path: path),
      data:
          (path.endsWith('/detailed')
                  ? {
                      'artifact_job_id': currentArtifact,
                      'details': {'steps': steps},
                    }
                  : {
                      'state': 'ready',
                      'lesson_version': currentVersion,
                      'revision': currentRevision,
                    })
              as T,
    );
  }

  @override
  Future<Response<T>> post<T>(
    String path, {
    dynamic data,
    Map<String, dynamic>? queryParameters,
    Options? options,
    bool skipAuth = false,
  }) async {
    this.path = path;
    this.options = options;
    query = queryParameters;
    return Response<T>(
      requestOptions: RequestOptions(path: path),
      data: {'state': 'not_started'} as T,
    );
  }
}

void main() {
  test(
    'unopened practice follows only the exact visible lesson and authenticated current artifact',
    () async {
      final client = _PracticeClient();
      final repo = PracticeRepository(client);
      expect(
        (await repo.refreshUnopened(
          'item',
          'step',
          'old',
          'Title',
          'Unchanged lesson',
        ))?.artifact,
        'new-artifact',
      );
      expect(client.query, {'artifactJobId': 'new-artifact'});
      for (final input in [
        ('step', 'Title', 'Changed lesson'),
        ('step', 'Different title', 'Unchanged lesson'),
        ('different', 'Title', 'Unchanged lesson'),
        ('step', 'Title', ''),
      ]) {
        expect(
          await repo.refreshUnopened(
            'item',
            input.$1,
            'old',
            input.$2,
            input.$3,
          ),
          isNull,
        );
      }
      client.steps.add(Map.of(client.steps.single));
      expect(
        await repo.refreshUnopened(
          'item',
          'step',
          'old',
          'Title',
          'Unchanged lesson',
        ),
        isNull,
      );
    },
  );
  test(
    'refreshes an artifact only for the identical practice version and revision',
    () async {
      final client = _PracticeClient();
      final prior = LessonPracticeState.fromJson({
        'state': 'ready',
        'lesson_version': 'same-content-and-key',
        'revision': 4,
      });
      final result = await PracticeRepository(
        client,
      ).refreshUnchanged('item', 'step', 'old-artifact', prior);
      expect(result?.artifact, 'new-artifact');
      expect(result?.state.lessonVersion, prior.lessonVersion);
      expect(client.query, {'artifactJobId': 'new-artifact'});
      expect(client.reads.length, 2);
    },
  );

  test(
    'changed answer keys, revisions and absent provenance cannot refresh',
    () async {
      final prior = LessonPracticeState.fromJson({
        'state': 'ready',
        'lesson_version': 'same-content-and-key',
        'revision': 4,
      });
      for (final client in [
        _PracticeClient()..currentVersion = 'changed-answer-key',
        _PracticeClient()..currentRevision = 5,
        _PracticeClient()..currentVersion = null,
        _PracticeClient()..currentArtifact = 'old-artifact',
        _PracticeClient()..currentArtifact = null,
      ]) {
        expect(
          await PracticeRepository(
            client,
          ).refreshUnchanged('item', 'step', 'old-artifact', prior),
          isNull,
        );
      }
      final client = _PracticeClient();
      expect(
        await PracticeRepository(client).refreshUnchanged(
          'item',
          'step',
          'old-artifact',
          LessonPracticeState.fromJson({'state': 'ready'}),
        ),
        isNull,
      );
      expect(client.reads, isEmpty);
    },
  );
  test(
    'practice preparation allows server deadline and lease transport margin',
    () async {
      final client = _PracticeClient();
      await PracticeRepository(client).prepare('item', 'step', 'artifact');
      expect(client.path, '/plan-items/item/steps/step/practice/prepare');
      expect(client.query, {'artifactJobId': 'artifact'});
      expect(client.options?.receiveTimeout, const Duration(seconds: 130));
    },
  );

  test('answer review retains its shorter timeout', () async {
    final client = _PracticeClient();
    await PracticeRepository(client).act(
      'item',
      'step',
      'artifact',
      action: 'submit',
      revision: 1,
      activity: 'case',
      requestId: 'request-1',
    );
    expect(client.path, '/plan-items/item/steps/step/practice/submit');
    expect(client.options?.receiveTimeout, const Duration(seconds: 70));
  });
}
