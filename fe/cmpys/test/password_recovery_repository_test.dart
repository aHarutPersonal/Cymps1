import 'dart:typed_data';

import 'package:cmpys/core/network/api_error.dart';
import 'package:cmpys/core/network/dio_client.dart';
import 'package:cmpys/core/storage/token_store.dart';
import 'package:cmpys/features/auth/data/password_recovery_repository.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

class _Tokens extends TokenStore {
  int reads = 0;
  int clears = 0;
  @override
  Future<void> clear() async {
    clears++;
  }

  @override
  Future<String?> readAccessToken() async {
    reads++;
    return 'unused-test-session';
  }
}

class _Adapter implements HttpClientAdapter {
  _Adapter(this.respond);
  final ResponseBody Function(RequestOptions) respond;
  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? stream,
    Future<void>? cancel,
  ) async => respond(options);
  @override
  void close({bool force = false}) {}
}

ResponseBody _body(
  int status, [
  String body = '',
  Map<String, List<String>> extra = const {},
]) => ResponseBody.fromString(
  body,
  status,
  headers: {
    Headers.contentTypeHeader: ['application/json'],
    ...extra,
  },
);

void main() {
  late _Tokens tokens;
  late DioClient client;
  late PasswordRecoveryRepository repo;
  setUp(() {
    tokens = _Tokens();
    client = DioClient(tokenStore: tokens);
    repo = PasswordRecoveryRepository(client, tokenStore: tokens);
  });
  tearDown(() => client.dio.close());

  test(
    'exact public contract keeps credentials in POST bodies and never signs in',
    () async {
      final requests = <RequestOptions>[];
      client.dio.httpClientAdapter = _Adapter((request) {
        requests.add(request);
        return switch (request.path) {
          '/auth/password-reset/availability' => _body(
            200,
            '{"available":true}',
          ),
          '/auth/password-reset/request' => _body(202, '{"message":"generic"}'),
          '/auth/password-reset/confirm' => _body(204),
          _ => throw StateError('Unexpected route'),
        };
      });
      expect(await repo.isAvailable(), isTrue);
      await repo.requestCode(' qa@example.com ');
      await repo.confirm(
        token: ' inert-fixture-token ',
        password: ' test password ',
      );
      expect(requests.map((r) => r.method), ['GET', 'POST', 'POST']);
      expect(requests[1].data, {'email': 'qa@example.com'});
      expect(requests[2].data, {
        'token': 'inert-fixture-token',
        'password': ' test password ',
      });
      expect(requests.every((r) => r.extra['skipAuth'] == true), isTrue);
      expect(
        requests.every(
          (r) =>
              !r.headers.containsKey('Authorization') &&
              r.queryParameters.isEmpty,
        ),
        isTrue,
      );
      expect(tokens.reads, 0);
      expect(tokens.clears, 1);
    },
  );

  test('older server reports recovery unavailable', () async {
    client.dio.httpClientAdapter = _Adapter(
      (_) => _body(404, '{"detail":"Not found"}'),
    );
    expect(await repo.isAvailable(), isFalse);
  });

  test('malformed availability cannot enable recovery', () async {
    client.dio.httpClientAdapter = _Adapter(
      (_) => _body(200, '{"available":"true"}'),
    );
    await expectLater(repo.isAvailable(), throwsFormatException);
  });

  test(
    'server request limit retains Retry-After through the shared client',
    () async {
      client.dio.httpClientAdapter = _Adapter(
        (_) => _body(
          429,
          '{"detail":"Too many recovery attempts. Try again later."}',
          {
            'retry-after': ['900'],
          },
        ),
      );
      await expectLater(
        repo.requestCode('qa@example.com'),
        throwsA(
          isA<ApiError>()
              .having((error) => error.statusCode, 'status', 429)
              .having(
                (error) => error.retryAfterSeconds,
                'retry interval',
                900,
              ),
        ),
      );
    },
  );

  test('disabled delivery is not accepted as a sent request', () async {
    client.dio.httpClientAdapter = _Adapter(
      (_) => _body(503, '{"detail":"Account recovery is not connected yet."}'),
    );
    await expectLater(
      repo.requestCode('qa@example.com'),
      throwsA(isA<ApiError>()),
    );
  });

  test(
    'invalid code preserves server failure instead of resetting a session',
    () async {
      client.dio.httpClientAdapter = _Adapter(
        (_) => _body(400, '{"detail":"Invalid or expired code"}'),
      );
      await expectLater(
        repo.confirm(token: 'inert-code', password: 'FixturePass7!'),
        throwsA(
          isA<ApiError>().having((error) => error.statusCode, 'status', 400),
        ),
      );
      expect(tokens.reads, 0);
      expect(tokens.clears, 0);
    },
  );

  test('unexpected successful status cannot claim a completed reset', () async {
    client.dio.httpClientAdapter = _Adapter((_) => _body(202, '{}'));
    await expectLater(
      repo.confirm(token: 'inert-code', password: 'FixturePass7!'),
      throwsFormatException,
    );
  });
}
