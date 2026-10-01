import 'package:cmpys/core/network/dio_client.dart';
import 'package:cmpys/features/plan/data/practice_repository.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

class _PracticeClient extends Fake implements DioClient {
  Options? options;
  String? path;
  Map<String, dynamic>? query;

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
