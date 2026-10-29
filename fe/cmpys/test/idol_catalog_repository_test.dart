import 'package:cmpys/core/network/dio_client.dart';
import 'package:cmpys/features/session/data/session_repository.dart';
import 'package:cmpys/features/session/models/session_models.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

// The idol-catalog calls behind mentor discovery and the mentor preview:
// POST /idols/import ("Prepare profile") and GET /idols/search +
// GET /idols/{id}/timeline (the preview's documented timeline).

class _Client extends Fake implements DioClient {
  final posts = <String, Object?>{};
  final gets = <String, Map<String, dynamic>?>{};
  Map<String, dynamic> importBody = {
    'idolId': 'idol-1',
    'jobId': 'job-1',
    'status': 'queued',
  };
  Map<String, dynamic> searchBody = {'idols': <dynamic>[], 'total': 0};
  Map<String, dynamic> timelineBody = {'events': <dynamic>[]};

  @override
  Future<Response<T>> post<T>(
    String path, {
    dynamic data,
    Map<String, dynamic>? queryParameters,
    Options? options,
    bool skipAuth = false,
  }) async {
    posts[path] = data;
    return Response<T>(
      requestOptions: RequestOptions(path: path),
      statusCode: 201,
      data: importBody as T,
    );
  }

  @override
  Future<Response<T>> get<T>(
    String path, {
    Map<String, dynamic>? queryParameters,
    Options? options,
    Duration? receiveTimeout,
    bool skipAuth = false,
  }) async {
    gets[path] = queryParameters;
    return Response<T>(
      requestOptions: RequestOptions(path: path),
      data: (path.endsWith('/timeline') ? timelineBody : searchBody) as T,
    );
  }
}

void main() {
  test('importIdol posts the typed name as an llm import and maps the job', () {
    final client = _Client();
    return SessionRepository(
      dioClient: client,
    ).importIdol('  Zed  Nobody ').then((result) {
      expect(client.posts.keys, ['/idols/import']);
      expect(client.posts['/idols/import'], {
        'provider': 'llm',
        'externalId': 'llm:zed_nobody',
        'name': 'Zed Nobody',
      });
      expect(result.idolId, 'idol-1');
      expect(result.jobId, 'job-1');
      expect(result.status, 'queued');
      // A new profile always waits for review; only an explicit
      // published status would be ready to preview.
      expect(result.isPublished, isFalse);
      expect(
        const IdolImportResult(idolId: 'i', status: 'published').isPublished,
        isTrue,
      );
    });
  });

  test(
    'idolTimeline finds the exact catalog idol and keeps aged events',
    () async {
      final client = _Client()
        ..searchBody = {
          'idols': [
            {
              'id': 'other',
              'name': 'Warren Buffett Jr.',
              'aliases': <dynamic>[],
            },
            {
              'id': 'wb',
              'name': 'Warren  Buffett',
              'aliases': [
                {'alias_text': 'The Oracle of Omaha'},
              ],
            },
          ],
          'total': 2,
        }
        ..timelineBody = {
          'events': [
            {
              'id': 'ev-1',
              'canonicalTitle': 'Buys his first stock',
              'canonicalDescription': 'Three shares.',
              'ageAtEvent': 11,
              'category': 'finance',
            },
            {
              'canonicalTitle': 'Undated milestone',
              'canonicalDescription': 'No age is known.',
              'ageAtEvent': null,
            },
            {
              'canonicalTitle': '',
              'canonicalDescription': 'Joins Graham-Newman.',
              'ageAtEvent': 24,
            },
          ],
        };
      final entries = await SessionRepository(
        dioClient: client,
      ).idolTimeline('warren buffett');

      expect(client.gets['/idols/search']?['q'], 'warren buffett');
      expect(client.gets.containsKey('/idols/wb/timeline'), isTrue);
      expect(client.gets['/idols/wb/timeline']?['limit'], 50);
      expect(entries.map((e) => e.age), [11, 24]);
      expect(entries.map((e) => e.text), [
        'Buys his first stock',
        'Joins Graham-Newman.',
      ]);
      // The event's id and category come along when the server sends them.
      expect(entries.map((e) => e.id), ['ev-1', null]);
      expect(entries.map((e) => e.category), ['finance', null]);
    },
  );

  test(
    'idolTimeline matches an alias and returns nothing without a match',
    () async {
      final client = _Client()
        ..searchBody = {
          'idols': [
            {
              'id': 'wb',
              'name': 'Warren Buffett',
              'aliases': [
                {'alias_text': 'The Oracle of Omaha'},
              ],
            },
          ],
          'total': 1,
        };
      final repo = SessionRepository(dioClient: client);

      await repo.idolTimeline('the oracle of omaha');
      expect(client.gets.containsKey('/idols/wb/timeline'), isTrue);

      client.gets.clear();
      expect(await repo.idolTimeline('Somebody Else'), isEmpty);
      expect(client.gets.keys, ['/idols/search']);
    },
  );

  test('idolTimeline asks for the server’s whole page of matches', () async {
    final client = _Client()
      ..searchBody = {
        'idols': [
          {'id': 'wb', 'name': 'Warren Buffett', 'aliases': <dynamic>[]},
        ],
        'total': 1,
      };
    await SessionRepository(dioClient: client).idolTimeline('Warren Buffett');
    // The search is unordered: a small page could cut the exact match off.
    expect(client.gets['/idols/search']?['limit'], 100);
    expect(client.gets.containsKey('/idols/wb/timeline'), isTrue);
  });

  test('idolTimeline gives nothing for a name two catalog idols share', () async {
    final client = _Client()
      ..searchBody = {
        'idols': [
          {'id': 'jsmith-1', 'name': 'John Smith', 'aliases': <dynamic>[]},
          {
            'id': 'jsmith-2',
            'name': 'John Smith (explorer)',
            'aliases': [
              {'alias_text': 'John  Smith'},
            ],
          },
        ],
        'total': 2,
      };
    final repo = SessionRepository(dioClient: client);
    // Homonyms: never show one person's timeline for another.
    expect(await repo.idolTimeline('john smith'), isEmpty);
    expect(client.gets.keys, ['/idols/search']);
  });

  test('one idol matching by name and alias is still one match', () async {
    final client = _Client()
      ..searchBody = {
        'idols': [
          {
            'id': 'wb',
            'name': 'Warren Buffett',
            'aliases': [
              {'alias_text': 'warren buffett'},
            ],
          },
        ],
        'total': 1,
      };
    await SessionRepository(dioClient: client).idolTimeline('Warren Buffett');
    expect(client.gets.containsKey('/idols/wb/timeline'), isTrue);
  });

  test('a cut-off search page cannot prove the match is the only one', () async {
    final client = _Client()
      ..searchBody = {
        'idols': [
          {'id': 'wb', 'name': 'Warren Buffett', 'aliases': <dynamic>[]},
        ],
        // More matches than the page holds: another exact match may be among
        // the rest.
        'total': 140,
      };
    final repo = SessionRepository(dioClient: client);
    expect(await repo.idolTimeline('Warren Buffett'), isEmpty);
    expect(client.gets.keys, ['/idols/search']);
  });
}
