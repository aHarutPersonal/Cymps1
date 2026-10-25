import 'package:cmpys/core/network/dio_client.dart';
import 'package:cmpys/core/storage/token_store.dart';
import 'package:cmpys/features/plan/data/plan_repository.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'verified original can open independently of an unavailable guide',
    () async {
      final client = SourceClient(
        'https://www.gutenberg.org/cache/epub/46/pg46-images.html',
      );
      final url = await PlanRepository(
        dioClient: client,
      ).resolveOriginalBookSource('A Christmas Carol', 'Charles Dickens');
      expect(url, client.url);
      expect(client.path, '/content-resources/original-source');
      expect(client.query, {
        'title': 'A Christmas Carol',
        'author': 'Charles Dickens',
      });
    },
  );
  for (final url in [
    null,
    'javascript:alert(1)',
    'http://www.gutenberg.org/book',
    'https://evil.test/book',
    'https://user:pass@www.gutenberg.org/book',
    'https://www.gutenberg.org:8000/book',
  ]) {
    test('rejects unavailable or unsafe original source: $url', () async {
      expect(
        await PlanRepository(
          dioClient: SourceClient(url),
        ).resolveOriginalBookSource('Book', null),
        isNull,
      );
    });
  }
}

class SourceClient extends DioClient {
  SourceClient(this.url) : super(tokenStore: TokenStore());
  final String? url;
  String? path;
  Map<String, dynamic>? query;
  @override
  Future<Response<T>> get<T>(
    String path, {
    Map<String, dynamic>? queryParameters,
    Options? options,
    bool skipAuth = false,
    Duration? receiveTimeout,
  }) async {
    this.path = path;
    query = queryParameters;
    return Response<T>(
      data: <String, dynamic>{'url': url} as T,
      requestOptions: RequestOptions(path: path),
    );
  }
}
