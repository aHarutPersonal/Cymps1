import 'package:cmpys/core/network/dio_client.dart';
import 'package:cmpys/core/storage/token_store.dart';
import 'package:cmpys/features/plan/data/plan_repository.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

class ReadingClient extends DioClient {
  ReadingClient(this.source, {this.guide}) : super(tokenStore: TokenStore());
  final Map<String, dynamic> source;
  final Map<String, dynamic>? guide;
  final List<String> paths = [];
  @override
  Future<Response<T>> get<T>(
    String path, {
    Map<String, dynamic>? queryParameters,
    Options? options,
    bool skipAuth = false,
    Duration? receiveTimeout,
  }) async {
    paths.add(path);
    return Response<T>(
      data: (path.endsWith('/resolve') ? guide : source) as T,
      requestOptions: RequestOptions(path: path),
    );
  }
}

void main() {
  const excerpt = {
    'url':
        'https://www.johnyorkestory.com/2017/01/into-the-woods-preface-to-the-us-edition/',
    'scope': 'excerpt',
    'description': 'Author preface. Full book not included.',
  };
  test(
    'terminal guide failure still opens an explicitly scoped author excerpt',
    () async {
      final client = ReadingClient(
        excerpt,
        guide: {'status': 'failed_quality', 'message': 'No verified source'},
      );
      final access = await PlanRepository(dioClient: client)
          .resolveBookReadingAccess(
            'book:john:woods',
            'Into the Woods',
            'John Yorke',
          );
      expect(access.resourceId, isNull);
      expect(access.source!.actionLabel, 'Read excerpt');
      expect(access.source!.scope, 'excerpt');
      expect(access.unavailable, isNotNull);
      expect(client.paths, [
        '/content-resources/resolve',
        '/content-resources/reading-source',
      ]);
    },
  );
  test(
    'ready quality-approved guide takes priority without source lookup',
    () async {
      final client = ReadingClient(
        excerpt,
        guide: {'status': 'ready', 'id': 'ready-book'},
      );
      final access = await PlanRepository(dioClient: client)
          .resolveBookReadingAccess(
            'book:john:woods',
            'Into the Woods',
            'John Yorke',
          );
      expect(access.resourceId, 'ready-book');
      expect(client.paths, ['/content-resources/resolve']);
    },
  );
  test('missing source preserves terminal failure and never polls', () async {
    final client = ReadingClient(
      {'url': null},
      guide: {'status': 'failed_quality', 'message': 'No verified source'},
    );
    final access = await PlanRepository(
      dioClient: client,
    ).resolveBookReadingAccess('book:author:title', 'Book', 'Author');
    expect(access.source, isNull);
    expect(access.unavailable!.message, 'No verified source');
    expect(client.paths.length, 2);
  });
  for (final invalid in [
    {...excerpt, 'scope': 'full_text'},
    {...excerpt, 'url': 'https://www.johnyorkestory.com/unrelated/'},
    {...excerpt, 'url': 'https://www.johnyorkestory.com.evil.test/book'},
    {
      ...excerpt,
      'url':
          'https://user:secret@www.johnyorkestory.com/2017/01/into-the-woods-preface-to-the-us-edition/',
    },
    {
      ...excerpt,
      'url':
          'http://www.johnyorkestory.com/2017/01/into-the-woods-preface-to-the-us-edition/',
    },
  ]) {
    test(
      'rejects unverified source or incorrect full-book claim: $invalid',
      () async {
        expect(
          await PlanRepository(
            dioClient: ReadingClient(invalid),
          ).resolveBookReadingSource('Into the Woods', 'John Yorke'),
          isNull,
        );
      },
    );
  }
}
