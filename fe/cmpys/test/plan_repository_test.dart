import 'dart:async';

import 'package:cmpys/core/network/api_error.dart';
import 'package:cmpys/core/network/dio_client.dart';
import 'package:cmpys/core/storage/token_store.dart';
import 'package:cmpys/features/plan/data/plan_repository.dart';
import 'package:cmpys/features/plan/models/plan_models.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('reviewed minute duration overrides the legacy hour estimate', () {
    final item = BackendPlanItem.fromJson({
      'estimatedHours': 8,
      'estimatedMinutes': 42,
    });
    expect(item.requiredMinutes, 42);
    expect(item.durationLabel, '42m');
    expect(BackendPlanItem.fromJson({'estimatedHours': 2}).durationLabel, '2h');
    expect(BackendPlanItem.formatMinutes(95), '1h 35m');
  });
  test('default book-guide polling covers long quality generation', () {
    expect(
      PlanRepository.bookGuidePollWindow,
      greaterThanOrEqualTo(const Duration(minutes: 6)),
    );
    expect(PlanRepository.bookGuidePollAttempts, greaterThanOrEqualTo(10));
  });

  test('getJobStatus narrows polling to plan jobs', () async {
    final client = _RecordingDioClient();
    final repository = PlanRepository(dioClient: client);

    final job = await repository.getJobStatus('job-123');

    expect(client.requestedPath, '/jobs/job-123');
    expect(client.requestedQuery, const {'type': 'plan'});
    expect(job.id, 'job-123');
    expect(job.status, 'running');
  });

  test('getPlanDetailJobStatus narrows polling to detail jobs', () async {
    final client = _RecordingDioClient();
    final repository = PlanRepository(dioClient: client);

    final job = await repository.getPlanDetailJobStatus('detail-job-123');

    expect(client.requestedPath, '/jobs/detail-job-123');
    expect(client.requestedQuery, const {'type': 'plan_detail'});
    expect(job.status, 'running');
  });

  test('completion requests carry the desired state as ?complete=', () async {
    final client = _RecordingDioClient();
    final repository = PlanRepository(dioClient: client);

    await repository.toggleStepComplete(
      'mission-1',
      'step_2',
      artifactJobId: 'artifact-1',
      complete: true,
    );
    expect(client.requestedPath, '/plan-items/mission-1/steps/step_2/toggle');
    expect(client.requestedQuery, const {
      'artifactJobId': 'artifact-1',
      'complete': true,
    });

    await repository.toggleStepComplete('mission-1', 'step_2', complete: true);
    expect(client.requestedQuery, const {'complete': true});

    await repository.toggleItemComplete(
      'mission-1',
      artifactJobId: 'artifact-1',
      complete: false,
    );
    expect(client.requestedPath, '/plan-items/mission-1/toggle-complete');
    expect(client.requestedQuery, const {
      'artifactJobId': 'artifact-1',
      'complete': false,
    });

    // Without a desired state the request is the plain toggle.
    await repository.toggleItemComplete('mission-1');
    expect(client.requestedQuery, isNull);
  });

  test('peekPlanItemDetailed reads details with ?peek=true', () async {
    final client = _RecordingDioClient();
    final repository = PlanRepository(dioClient: client);

    final detailed = await repository.peekPlanItemDetailed('mission-2');

    expect(client.requestedPath, '/plan-items/mission-2/detailed');
    expect(client.requestedQuery, const {'peek': true});
    // A peek with nothing written answers pending, with no job to poll.
    expect(detailed.detailsStatus, 'pending');
    expect(detailed.jobId, isNull);
    expect(detailed.detailsLoading, isTrue);
    expect(detailed.steps, isEmpty);

    // The normal read carries no peek.
    await repository.getPlanItemDetailed('mission-2');
    expect(client.requestedQuery, isNull);
  });

  test('getDailyStatus reads a habit’s own days of the week', () async {
    final client = _RecordingDioClient();
    final repository = PlanRepository(dioClient: client);

    final status = await repository.getDailyStatus('habit-1');

    expect(client.requestedPath, '/plan-items/habit-1/daily-status');
    expect(status.itemId, 'habit-1');
    expect(status.days.length, 7);
    expect(status.days.first.date, DateTime.utc(2026, 10, 19));
    expect(status.days.map((d) => d.completed), [
      false,
      false,
      false,
      true,
      true,
      false,
      false,
    ]);
  });

  test('resolveContentResourceId late-binds a generated book', () async {
    final client = _RecordingDioClient();
    final repository = PlanRepository(dioClient: client);

    final id = await repository.resolveContentResourceId('book:author:title');

    expect(client.requestedPath, '/content-resources/resolve');
    expect(client.requestedQuery, const {'canonicalKey': 'book:author:title'});
    expect(id, 'resource-123');
  });

  test('content resource resolution is single-flight and cached', () async {
    final client = _PendingResolveDioClient();
    final repository = PlanRepository(dioClient: client);

    final first = repository.resolveContentResourceId('book:author:title');
    final second = repository.resolveContentResourceId('book:author:title');

    expect(client.calls, 1);
    client.gate.complete();
    expect(await first, 'resource-123');
    expect(await second, 'resource-123');
    expect(
      await repository.resolveContentResourceId('book:author:title'),
      'resource-123',
    );
    expect(client.calls, 1);
  });

  test(
    'book guide wait uses bounded polling until the guide is ready',
    () async {
      final client = _EventuallyReadyDioClient();
      final repository = PlanRepository(dioClient: client);

      final id = await repository.waitForContentResourceId(
        'book:author:title',
        pollDelays: const [Duration.zero, Duration.zero, Duration.zero],
      );

      expect(id, 'resource-123');
      expect(client.calls, 3);
    },
  );

  test(
    'missing guide stops immediately instead of waiting six minutes',
    () async {
      final client = _TerminalResolveDioClient(status: 'missing');
      final repository = PlanRepository(dioClient: client);
      await expectLater(
        repository.waitForContentResourceId(
          'book:author:missing',
          pollDelays: const [Duration.zero, Duration.zero, Duration.zero],
        ),
        throwsA(
          isA<BookGuideUnavailableException>().having(
            (error) => error.status,
            'status',
            'missing',
          ),
        ),
      );
      expect(client.calls, 1);
    },
  );

  test('book guide wait stops on a terminal quality failure', () async {
    final client = _TerminalResolveDioClient();
    final repository = PlanRepository(dioClient: client);

    await expectLater(
      repository.waitForContentResourceId(
        'book:author:title',
        pollDelays: const [Duration.zero, Duration.zero, Duration.zero],
      ),
      throwsA(
        isA<BookGuideUnavailableException>()
            .having((error) => error.status, 'status', 'failed_quality')
            .having(
              (error) => error.message,
              'message',
              contains('quality standard'),
            ),
      ),
    );
    expect(client.calls, 1);
  });

  test('saveAchievement returns the server id; deleteAchievement deletes '
      'it', () async {
    final client = _AchievementDioClient();
    final repository = PlanRepository(dioClient: client);

    final id = await repository.saveAchievement(
      title: 'Wrote the owner’s memo',
      category: 'finance',
      source: 'plan_item',
      planItemId: 'mission-1',
    );
    expect(id, 'ach-9');
    expect(client.posts.single, '/achievements');

    // An older server (or an odd body) without an id gives null.
    client.body = const {'title': 'x'};
    expect(
      await repository.saveAchievement(
        title: 'x',
        category: 'other',
        source: 'manual',
      ),
      isNull,
    );

    await repository.deleteAchievement('ach-9');
    expect(client.deletes, ['/achievements/ach-9']);
  });

  test('listAchievements reads every page of GET /achievements', () async {
    final client = _AchievementListDioClient(total: 5, pageSize: 2);
    final repository = PlanRepository(dioClient: client);

    final all = await repository.listAchievements(pageSize: 2);

    expect(all.map((a) => a.id), ['a0', 'a1', 'a2', 'a3', 'a4']);
    expect(client.queries, [
      {'limit': 2, 'offset': 0},
      {'limit': 2, 'offset': 2},
      {'limit': 2, 'offset': 4},
    ]);
    final first = all.first;
    expect(first.title, 'Win 0');
    expect(first.category, 'finance');
    expect(first.source, 'plan_item');
    expect(first.notes, 'Notes 0');
    expect(first.createdAt, DateTime.utc(2026, 10, 20, 9));
    expect(first.achievementDate, isNull);
    expect(all[1].achievementDate, DateTime(2026, 10, 18));
  });

  test('listAchievements stops at a sane bound and skips odd rows', () async {
    final client = _AchievementListDioClient(total: 1000, pageSize: 2)
      ..oddRow = true;
    final repository = PlanRepository(dioClient: client);

    final all = await repository.listAchievements(pageSize: 2, maxPages: 3);

    expect(client.queries, hasLength(3));
    // Each page has one row without an id, which is skipped.
    expect(all, hasLength(6));
  });

  test('regeneratePlanItemDetails uses the explicit retry endpoint', () async {
    final client = _RecordingDioClient();
    final repository = PlanRepository(dioClient: client);

    final jobId = await repository.regeneratePlanItemDetails('item-123');

    expect(client.requestedPath, '/plan-items/item-123/regenerate-details');
    expect(jobId, 'detail-job-123');
  });
}

class _RecordingDioClient extends DioClient {
  _RecordingDioClient() : super(tokenStore: TokenStore());

  String? requestedPath;
  Map<String, dynamic>? requestedQuery;

  @override
  Future<Response<T>> get<T>(
    String path, {
    Map<String, dynamic>? queryParameters,
    Options? options,
    bool skipAuth = false,
    Duration? receiveTimeout,
  }) async {
    requestedPath = path;
    requestedQuery = queryParameters;
    if (path == '/content-resources/resolve') {
      return Response<T>(
        data:
            <String, dynamic>{
                  'id': 'resource-123',
                  'canonicalKey': queryParameters?['canonicalKey'],
                }
                as T,
        requestOptions: RequestOptions(path: path),
      );
    }
    if (path.endsWith('/detailed')) {
      return Response<T>(
        data:
            <String, dynamic>{
                  'item': {'id': 'mission-2', 'title': 'Second mission'},
                  'details_status': 'pending',
                  'completed': false,
                }
                as T,
        requestOptions: RequestOptions(path: path),
      );
    }
    if (path.endsWith('/daily-status')) {
      return Response<T>(
        data:
            <String, dynamic>{
                  'item_id': 'habit-1',
                  'days': [
                    for (var i = 0; i < 7; i++)
                      {
                        'date': '2026-10-${19 + i}',
                        'day_name': 'Day',
                        'completed': i == 3 || i == 4,
                      },
                  ],
                }
                as T,
        requestOptions: RequestOptions(path: path),
      );
    }
    return Response<T>(
      data:
          <String, dynamic>{
                'id': 'job-123',
                'status': 'running',
                'progressPercent': 20,
              }
              as T,
      requestOptions: RequestOptions(path: path),
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
    requestedPath = path;
    requestedQuery = queryParameters;
    return Response<T>(
      data: <String, dynamic>{'job_id': 'detail-job-123'} as T,
      requestOptions: RequestOptions(path: path),
    );
  }
}

class _PendingResolveDioClient extends DioClient {
  _PendingResolveDioClient() : super(tokenStore: TokenStore());

  final gate = Completer<void>();
  int calls = 0;

  @override
  Future<Response<T>> get<T>(
    String path, {
    Map<String, dynamic>? queryParameters,
    Options? options,
    bool skipAuth = false,
    Duration? receiveTimeout,
  }) async {
    calls++;
    await gate.future;
    return Response<T>(
      data:
          <String, dynamic>{
                'id': 'resource-123',
                'canonicalKey': queryParameters?['canonicalKey'],
              }
              as T,
      requestOptions: RequestOptions(path: path),
    );
  }
}

class _EventuallyReadyDioClient extends DioClient {
  _EventuallyReadyDioClient() : super(tokenStore: TokenStore());

  int calls = 0;

  @override
  Future<Response<T>> get<T>(
    String path, {
    Map<String, dynamic>? queryParameters,
    Options? options,
    bool skipAuth = false,
    Duration? receiveTimeout,
  }) async {
    calls++;
    if (calls < 3) {
      throw const ApiError(message: 'Guide is pending', statusCode: 404);
    }
    return Response<T>(
      data:
          <String, dynamic>{
                'id': 'resource-123',
                'canonicalKey': queryParameters?['canonicalKey'],
              }
              as T,
      requestOptions: RequestOptions(path: path),
    );
  }
}

class _TerminalResolveDioClient extends DioClient {
  _TerminalResolveDioClient({this.status = 'failed_quality'})
    : super(tokenStore: TokenStore());

  final String status;

  int calls = 0;

  @override
  Future<Response<T>> get<T>(
    String path, {
    Map<String, dynamic>? queryParameters,
    Options? options,
    bool skipAuth = false,
    Duration? receiveTimeout,
  }) async {
    calls++;
    return Response<T>(
      data:
          <String, dynamic>{
                'id': null,
                'status': status,
                'message':
                    'This guide did not meet the reading-quality standard.',
                'canonicalKey': queryParameters?['canonicalKey'],
              }
              as T,
      requestOptions: RequestOptions(path: path),
    );
  }
}

class _AchievementDioClient extends DioClient {
  _AchievementDioClient() : super(tokenStore: TokenStore());

  Object? body = const {'id': 'ach-9', 'title': 'Wrote the owner’s memo'};
  final posts = <String>[];
  final deletes = <String>[];

  @override
  Future<Response<T>> post<T>(
    String path, {
    dynamic data,
    Map<String, dynamic>? queryParameters,
    Options? options,
    bool skipAuth = false,
  }) async {
    posts.add(path);
    return Response<T>(data: body as T, requestOptions: RequestOptions(path: path));
  }

  @override
  Future<Response<T>> delete<T>(
    String path, {
    dynamic data,
    Map<String, dynamic>? queryParameters,
    Options? options,
    bool skipAuth = false,
  }) async {
    deletes.add(path);
    return Response<T>(statusCode: 204, requestOptions: RequestOptions(path: path));
  }
}

/// Serves `GET /achievements` in pages of [pageSize] out of [total].
class _AchievementListDioClient extends DioClient {
  _AchievementListDioClient({required this.total, required this.pageSize})
    : super(tokenStore: TokenStore());

  final int total;
  final int pageSize;
  bool oddRow = false;
  final queries = <Map<String, dynamic>?>[];

  @override
  Future<Response<T>> get<T>(
    String path, {
    Map<String, dynamic>? queryParameters,
    Options? options,
    bool skipAuth = false,
    Duration? receiveTimeout,
  }) async {
    expect(path, '/achievements');
    queries.add(queryParameters);
    final offset = queryParameters?['offset'] as int;
    final limit = queryParameters?['limit'] as int;
    final rows = [
      for (var i = offset; i < total && i < offset + limit; i++)
        {
          'id': 'a$i',
          'userId': 'u1',
          'title': 'Win $i',
          'category': 'finance',
          'achievementDate': i == 1 ? '2026-10-18' : null,
          'notes': 'Notes $i',
          'createdAt': '2026-10-20T09:00:00+00:00',
          'source': 'plan_item',
        },
      if (oddRow) {'title': 'No id'},
    ];
    return Response<T>(
      data: <String, dynamic>{'achievements': rows, 'total': total} as T,
      requestOptions: RequestOptions(path: path),
    );
  }
}
