import 'dart:async';

import 'package:cmpys/core/network/api_error.dart';
import 'package:cmpys/core/ui/motion/page_transition.dart';
import 'package:cmpys/features/plan/presentation/book_reader_screen.dart';
import 'package:cmpys/features/plan/presentation/reading_library_screen.dart';
import 'package:cmpys/features/session/data/content_resources_repository.dart';
import 'package:cmpys/features/session/models/content_resource.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'fixtures/comparison_reader_harness.dart';

const _book = ContentResource(
  id: 'book-availability',
  kind: 'llm_book_summary',
  canonicalKey: 'book:qa:guide',
  title: 'Available guide',
  licenseStatus: 'test_fixture',
  isSaved: false,
  progressPercent: 0,
  contentMarkdown: '## A readable chapter\n\nThis text can be read.',
);

class _Repository extends Fake implements ContentResourcesRepository {
  Object? failure;
  Completer<ContentResource>? pending;
  bool resumeFails = false;
  int reads = 0;
  @override
  Future<ContentResource> getResource(String id) async {
    reads++;
    if (failure != null) throw failure!;
    return pending?.future ?? _book;
  }

  @override
  Future<List<ContentHighlight>> listHighlights(String id) async => [];
  @override
  Future<ContentResource> updateProgress(
    String id, {
    required int progressPercent,
    Map<String, dynamic>? cursorJson,
    bool? completed,
  }) async => _book;
  @override
  Future<ContentResource?> getContinueReading() async {
    if (resumeFails) {
      throw const ApiError(message: 'Unavailable resume', statusCode: 404);
    }
    return null;
  }

  @override
  Future<List<ContentResource>> listLibraryResources({
    String? kind,
    String? query,
    String? sort,
    int limit = 50,
    int offset = 0,
  }) async => [_book];
}

Widget _harness(_Repository repository, {String? source}) => ProviderScope(
  overrides: [contentResourcesRepositoryProvider.overrideWithValue(repository)],
  child: MaterialApp(
    home: Builder(
      builder: (context) => Scaffold(
        body: Center(
          child: TextButton(
            onPressed: () => Navigator.of(context).push(
              CmpysPageRoute<void>(
                builder: (_) => BookReaderScreen(
                  resourceId: _book.id,
                  fallbackTitle: _book.title,
                  fallbackSourceUrl: source,
                  narrator: ComparisonPreviewNarrator(),
                ),
              ),
            ),
            child: const Text('Open test book'),
          ),
        ),
      ),
    ),
  ),
);

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets(
    'book 404 explains unavailability, offers source and allows back',
    (tester) async {
      final repo = _Repository()
        ..failure = const ApiError(message: 'Not found', statusCode: 404);
      await tester.pumpWidget(
        _harness(repo, source: 'https://example.com/books/guide'),
      );
      await tester.tap(find.text('Open test book'));
      await tester.pumpAndSettle();
      expect(
        find.text('This book guide is not available for reading right now.'),
        findsOneWidget,
      );
      expect(find.textContaining('Check your connection'), findsNothing);
      expect(find.text('Open source'), findsOneWidget);
      expect(find.byTooltip('Book menu'), findsNothing);
      await tester.tap(find.byTooltip('Back'));
      await tester.pumpAndSettle();
      expect(find.text('Open test book'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('book can be closed while the content request is pending', (
    tester,
  ) async {
    final pending = Completer<ContentResource>();
    final repo = _Repository()..pending = pending;
    await tester.pumpWidget(_harness(repo));
    await tester.tap(find.text('Open test book'));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    expect(find.byTooltip('Back'), findsOneWidget);
    await tester.tap(find.byTooltip('Back'));
    await tester.pumpAndSettle();
    pending.complete(_book);
    await tester.pumpAndSettle();
    expect(find.text('Open test book'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('retry opens recovered book and unsafe source is not offered', (
    tester,
  ) async {
    final repo = _Repository()..failure = const NetworkError();
    await tester.pumpWidget(_harness(repo, source: 'javascript:alert(1)'));
    await tester.tap(find.text('Open test book'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Check your connection'), findsOneWidget);
    expect(find.text('Open source'), findsNothing);
    repo.failure = null;
    await tester.tap(find.text('Try again'));
    await tester.pumpAndSettle();
    expect(repo.reads, 2);
    expect(
      find.textContaining('This text can be read.', findRichText: true),
      findsWidgets,
    );
    expect(find.byTooltip('Book menu'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
  });

  testWidgets(
    'stale continue-reading entry does not hide available library books',
    (tester) async {
      final repo = _Repository()..resumeFails = true;
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            contentResourcesRepositoryProvider.overrideWithValue(repo),
          ],
          child: const MaterialApp(home: ReadingLibraryScreen()),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text(_book.title), findsWidgets);
      expect(find.text('Couldn’t load your reading library.'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );
}
