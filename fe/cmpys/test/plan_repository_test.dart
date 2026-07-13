import 'package:cmpys/core/network/dio_client.dart';
import 'package:cmpys/core/storage/token_store.dart';
import 'package:cmpys/features/plan/data/plan_repository.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
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

  test('resolveContentResourceId late-binds a generated book', () async {
    final client = _RecordingDioClient();
    final repository = PlanRepository(dioClient: client);

    final id = await repository.resolveContentResourceId('book:author:title');

    expect(client.requestedPath, '/content-resources/resolve');
    expect(client.requestedQuery, const {'canonicalKey': 'book:author:title'});
    expect(id, 'resource-123');
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
