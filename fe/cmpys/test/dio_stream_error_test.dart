import 'dart:typed_data';

import 'package:cmpys/core/network/api_error.dart';
import 'package:cmpys/core/network/dio_client.dart';
import 'package:cmpys/core/storage/token_store.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

/// Answers every request with [body] and [status].
class _JsonAdapter implements HttpClientAdapter {
  _JsonAdapter(this.body, this.status);

  final String body;
  final int status;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async => ResponseBody.fromString(
    body,
    status,
    headers: {
      Headers.contentTypeHeader: ['application/json'],
    },
  );

  @override
  void close({bool force = false}) {}
}

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

  test('a 422 validation list keeps its fields and never its raw text', () async {
    final client = DioClient(tokenStore: TokenStore());
    client.dio.httpClientAdapter = _JsonAdapter(
      '{"detail":[{"type":"value_error","loc":["body","email"],'
      '"msg":"value is not a valid email address: The part after the @-sign '
      'is a special-use or reserved name that cannot be used with email.",'
      '"input":"v3-live@example.test","ctx":{"reason":"reserved"}},'
      '{"type":"string_too_short","loc":["body","password"],'
      '"msg":"String should have at least 8 characters"}]}',
      422,
    );
    addTearDown(() => client.dio.close(force: true));

    await expectLater(
      client.post<dynamic>('/auth/register', data: const {}, skipAuth: true),
      throwsA(
        isA<ApiError>()
            .having((e) => e.statusCode, 'statusCode', 422)
            .having(
              (e) => e.fieldErrors.map((f) => (f.field, f.type)).toList(),
              'fieldErrors',
              [('email', 'value_error'), ('password', 'string_too_short')],
            )
            .having((e) => e.message, 'message', 'Invalid data provided'),
      ),
    );
  });
}
