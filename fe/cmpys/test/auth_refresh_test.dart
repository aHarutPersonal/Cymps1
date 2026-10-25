import 'dart:typed_data';
import 'package:cmpys/core/network/dio_client.dart';
import 'package:cmpys/core/storage/token_store.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

class MemoryTokens extends TokenStore {
  String? access = 'expired';
  String? refresh = 'refresh';
  int clears = 0;
  @override
  Future<String?> readAccessToken() async => access;
  @override
  Future<String?> readRefreshToken() async => refresh;
  @override
  Future<void> saveTokens({
    required String accessToken,
    String? refreshToken,
    DateTime? expiry,
    String? apiBase,
  }) async {
    access = accessToken;
    refresh = refreshToken;
  }

  @override
  Future<void> clear() async {
    clears++;
    access = null;
    refresh = null;
  }
}

class Adapter implements HttpClientAdapter {
  Adapter(this.reply);
  final Future<ResponseBody> Function(RequestOptions) reply;
  int calls = 0;
  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? stream,
    Future<void>? cancel,
  ) {
    calls++;
    return reply(options);
  }

  @override
  void close({bool force = false}) {}
}

ResponseBody body(int code, [String json = '{}']) => ResponseBody.fromString(
  json,
  code,
  headers: {
    Headers.contentTypeHeader: ['application/json'],
  },
);

void main() {
  for (final refreshStatus in [401, 429, 500]) {
    test(
      'refresh $refreshStatus clears credentials only on rejection',
      () async {
        final tokens = MemoryTokens();
        final refreshDio = Dio(BaseOptions(baseUrl: 'https://example.test'));
        refreshDio.httpClientAdapter = Adapter(
          (_) async => body(refreshStatus),
        );
        final client = DioClient(tokenStore: tokens, refreshDio: refreshDio);
        client.dio.httpClientAdapter = Adapter((_) async => body(401));
        await expectLater(client.dio.get('/me'), throwsA(isA<DioException>()));
        expect(tokens.clears, refreshStatus == 401 ? 1 : 0);
        client.dio.close();
        refreshDio.close();
      },
    );
  }
  test(
    'failed public login never refreshes or deletes another session',
    () async {
      final tokens = MemoryTokens();
      final refreshDio = Dio();
      final adapter = Adapter((_) async => body(200));
      refreshDio.httpClientAdapter = adapter;
      final client = DioClient(tokenStore: tokens, refreshDio: refreshDio);
      client.dio.httpClientAdapter = Adapter((_) async => body(401));
      await expectLater(
        client.dio.post(
          '/auth/login',
          options: Options(extra: {'skipAuth': true}),
        ),
        throwsA(isA<DioException>()),
      );
      expect(adapter.calls, 0);
      expect(tokens.clears, 0);
      client.dio.close();
      refreshDio.close();
    },
  );
  for (final retryStatus in [200, 401, 503]) {
    test(
      'retry after refresh returns $retryStatus without inappropriate logout',
      () async {
        final tokens = MemoryTokens();
        final refreshDio = Dio(BaseOptions(baseUrl: 'https://example.test'));
        final refreshAdapter = Adapter(
          (_) async =>
              body(200, '{"accessToken":"new","refreshToken":"rotated"}'),
        );
        refreshDio.httpClientAdapter = refreshAdapter;
        final client = DioClient(tokenStore: tokens, refreshDio: refreshDio);
        client.dio.httpClientAdapter = Adapter(
          (options) async => body(
            options.headers['Authorization'] == 'Bearer new'
                ? retryStatus
                : 401,
          ),
        );
        if (retryStatus == 200) {
          expect((await client.dio.get('/me')).statusCode, 200);
        } else {
          await expectLater(
            client.dio.get('/me'),
            throwsA(
              isA<DioException>().having(
                (e) => e.response?.statusCode,
                'actual status',
                retryStatus,
              ),
            ),
          );
        }
        expect(refreshAdapter.calls, 1);
        expect(tokens.clears, retryStatus == 401 ? 1 : 0);
        client.dio.close();
        refreshDio.close();
      },
    );
  }
  test(
    'malformed refresh preserves credentials and never retries protected request',
    () async {
      final tokens = MemoryTokens();
      final refreshDio = Dio(BaseOptions(baseUrl: 'https://example.test'));
      refreshDio.httpClientAdapter = Adapter((_) async => body(200));
      final client = DioClient(tokenStore: tokens, refreshDio: refreshDio);
      final adapter = Adapter((_) async => body(401));
      client.dio.httpClientAdapter = adapter;
      await expectLater(client.dio.get('/me'), throwsA(isA<DioException>()));
      expect(tokens.clears, 0);
      expect(adapter.calls, 1);
      client.dio.close();
      refreshDio.close();
    },
  );
}
