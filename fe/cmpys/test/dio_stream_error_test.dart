import 'dart:typed_data';

import 'package:cmpys/core/network/api_error.dart';
import 'package:cmpys/core/network/dio_client.dart';
import 'package:cmpys/core/storage/token_store.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

class _ErrorAdapter implements HttpClientAdapter {
  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    return ResponseBody.fromString(
      '{"detail":{"code":"interview_turn_in_progress",'
      '"message":"The mentor is still finishing this reply."}}',
      409,
      headers: {
        Headers.contentTypeHeader: ['application/json'],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

void main() {
  test(
    'streaming HTTP errors preserve FastAPI detail code and message',
    () async {
      final client = DioClient(tokenStore: TokenStore());
      client.dio.httpClientAdapter = _ErrorAdapter();
      addTearDown(() => client.dio.close(force: true));

      await expectLater(
        client.post<dynamic>(
          '/sessions/session-1/interview',
          data: const {'content': 'answer'},
          options: Options(responseType: ResponseType.stream),
          skipAuth: true,
        ),
        throwsA(
          isA<ApiError>()
              .having((error) => error.statusCode, 'statusCode', 409)
              .having(
                (error) => error.code,
                'code',
                'interview_turn_in_progress',
              )
              .having(
                (error) => error.message,
                'message',
                'The mentor is still finishing this reply.',
              ),
        ),
      );
    },
  );
}
