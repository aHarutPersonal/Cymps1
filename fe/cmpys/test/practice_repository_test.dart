import 'package:cmpys/core/network/dio_client.dart';
import 'package:cmpys/features/plan/data/practice_repository.dart';
import 'package:cmpys/features/plan/models/practice_models.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

class _PracticeClient extends Fake implements DioClient {
  Options? options;
  String? path;
  Map<String, dynamic>? query;
  dynamic body;
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
    body = data;
    return Response<T>(
      requestOptions: RequestOptions(path: path),
      data: {'state': 'not_started'} as T,
    );
  }

  @override
  Future<Response<T>> put<T>(
    String path, {
    dynamic data,
    Map<String, dynamic>? queryParameters,
    Options? options,
    bool skipAuth = false,
  }) async {
    this.path = path;
    query = queryParameters;
    body = data;
    return Response<T>(
      requestOptions: RequestOptions(path: path),
      data: {'state': 'ready'} as T,
    );
  }
}

final _workbookActivity = PracticeActivity.fromJson({
  'id': 'guided',
  'title': 'Owner earnings',
  'kind': 'practice',
  'instructions': 'Work out what the owners really earned this year.',
  'minutes_min': 4,
  'minutes_max': 8,
  'fields': [
    {'id': 'oe', 'label': 'Owner earnings', 'kind': 'number', 'unit': 'm'},
    {
      'id': 'lines',
      'label': 'Which lines are maintenance?',
      'kind': 'multi_choice',
      'choices': [
        {'id': 'warehouse', 'label': 'New warehouse'},
        {'id': 'line', 'label': 'Production line'},
        {'id': 'stores', 'label': 'Store refits'},
      ],
    },
  ],
});

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

  test('field hint names the field with field_id', () async {
    final client = _PracticeClient();
    await PracticeRepository(client).fieldHint(
      'item',
      'step',
      'artifact',
      revision: 3,
      activity: 'guided',
      fieldId: 'guided.oe',
      requestId: 'request-1',
    );
    expect(client.path, '/plan-items/item/steps/step/practice/hint');
    expect(client.query, {'artifactJobId': 'artifact', 'field_id': 'guided.oe'});
    expect(client.body, {
      'revision': 3,
      'activity_id': 'guided',
      'request_id': 'request-1',
    });
  });

  test('draft sends multi_choice canonically and numbers as given', () async {
    final client = _PracticeClient();
    await PracticeRepository(client).save(
      'item',
      'step',
      null,
      2,
      {'guided.oe': '4,5', 'guided.lines': 'stores, warehouse,stores'},
      activities: [_workbookActivity],
    );
    expect(client.path, '/plan-items/item/steps/step/practice/draft');
    // The screen normalises only edited numbers; a stored "4,5" must reach
    // the server unchanged so its passed attempt still matches.
    expect(client.body, {
      'revision': 2,
      'answers': {'guided.oe': '4,5', 'guided.lines': 'warehouse,stores'},
    });
  });

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
