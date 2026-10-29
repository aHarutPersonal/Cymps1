import 'dart:async';

import 'package:cmpys/app/design_tokens.dart';
import 'package:cmpys/app/theme.dart';
import 'package:cmpys/core/network/api_error.dart';
import 'package:cmpys/core/ui/v3/v3.dart';
import 'package:cmpys/features/plan/presentation/book_narration_checkpoint.dart';
import 'package:cmpys/features/plan/presentation/book_reader_screen.dart';
import 'package:cmpys/features/plan/presentation/reading_library_screen.dart';
import 'package:cmpys/features/plan/presentation/book_narration_dock.dart';
import 'package:cmpys/features/plan/state/book_narration_remote_controller.dart';
import 'package:cmpys/features/session/data/content_resources_repository.dart';
import 'package:cmpys/features/session/models/content_resource.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

ContentResource _book(
  String id,
  String title,
  String author, {
  int progress = 0,
  bool saved = false,
  bool completed = false,
  Map<String, dynamic>? cursor,
  Map<String, dynamic>? summary,
}) => ContentResource(
  id: id,
  kind: 'llm_book_summary',
  canonicalKey: 'book:$id',
  title: title,
  authorOrCreator: author,
  licenseStatus: 'llm_summary',
  isSaved: saved,
  progressPercent: progress,
  cursorJson: cursor,
  summaryJson: summary,
  completedAt: completed ? DateTime(2026, 10, 1) : null,
  contentMarkdown: '## One\n\nA readable chapter for $title.',
);

final _essays = _book(
  'essays',
  'The Essays of Warren Buffett',
  'Lawrence Cunningham',
  progress: 42,
  saved: true,
  cursor: const {'chapter': 5, 'chapterTitle': 'Accounting essays'},
);
final _artOfWar = _book(
  'artofwar',
  'The Art of War',
  'Sun Tzu',
  summary: const {'reading_url': 'https://www.gutenberg.org/ebooks/132'},
);
final _wealth = _book(
  'wealth',
  'The Wealth of Nations',
  'Adam Smith',
  progress: 100,
  completed: true,
);
final _blindness = _book('blindness', 'Blindness', 'José Saramago');

class _Repository extends Fake implements ContentResourcesRepository {
  _Repository(this.books, {this.resume, this.fail = false});

  final List<ContentResource> books;
  ContentResource? resume;
  bool fail;

  /// While set, the next list call waits for it (a refresh in flight).
  Completer<List<ContentResource>>? hold;

  /// Held list calls, served in order (overlapping loads).
  final holds = <Completer<List<ContentResource>>>[];
  int lists = 0;

  @override
  Future<List<ContentResource>> listLibraryResources({
    String? kind,
    String? query,
    String? sort,
    int limit = 50,
    int offset = 0,
  }) async {
    lists++;
    if (holds.isNotEmpty) return holds.removeAt(0).future;
    final pending = hold;
    if (pending != null) {
      hold = null;
      return pending.future;
    }
    if (fail) throw const ApiError(message: 'down', statusCode: 500);
    return books;
  }

  @override
  Future<ContentResource?> getContinueReading() async => resume;

  @override
  Future<ContentResource> getResource(String resourceId) async =>
      books.firstWhere((b) => b.id == resourceId);

  @override
  Future<List<ContentHighlight>> listHighlights(String id) async => [];

  @override
  Future<ContentResource> updateProgress(
    String id, {
    required int progressPercent,
    Map<String, dynamic>? cursorJson,
    bool? completed,
  }) async => books.firstWhere((b) => b.id == id);
}

Future<void> _pump(
  WidgetTester tester,
  _Repository repo, {
  Size size = const Size(430, 1800),
  List<Override> overrides = const [],
  bool settle = true,
  Widget home = const ReadingLibraryScreen(),
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        contentResourcesRepositoryProvider.overrideWithValue(repo),
        ...overrides,
      ],
      child: MaterialApp(theme: AppTheme.light, home: home),
    ),
  );
  if (settle) {
    await tester.pumpAndSettle();
  } else {
    // Playing waves loop; let the entrance finish instead of settling.
    await tester.pump();
    await tester.pump(const Duration(seconds: 2));
  }
}

/// Backs out of the reader with a refresh held in flight.
Future<void> _backFromReader(WidgetTester tester) async {
  Navigator.of(tester.element(find.byType(BookReaderScreen))).pop();
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
}

Future<void> _leave(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox());
  await tester.pumpAndSettle();
}

/// A reader opened by Listen starts narrating at once, and its narration
/// controls loop while preparing or playing: wait for the page, not a settle.
Future<void> _openNarratingReader(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(seconds: 1));
}

Future<void> _leaveNarratingReader(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox());
  // Lets any narration-failure toast in the test's fake plugin-less world
  // run out its timer.
  await tester.pump(const Duration(seconds: 3));
}

Finder get _search => find.byType(TextField);

Finder _row(String id) => find.byKey(ValueKey('library-row-$id'));

/// The opacity `V3Rise` gives a row right now.
double _riseOpacity(WidgetTester tester, String id) => tester
    .widget<Opacity>(
      find.descendant(of: _row(id), matching: find.byType(Opacity)).first,
    )
    .opacity;

Finder _icon(V3Icons icon) =>
    find.byWidgetPredicate((w) => w is V3Icon && w.icon == icon);

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('header and search', () {
    testWidgets('shows the kicker, the title and the search field', (
      tester,
    ) async {
      await _pump(tester, _Repository([_essays, _artOfWar, _wealth]));
      expect(find.text('LIBRARY'), findsOneWidget);
      expect(find.text('Reading'), findsOneWidget);
      expect(find.text('Search title or author'), findsOneWidget);
      expect(_icon(V3Icons.search), findsOneWidget);
      await _leave(tester);
    });

    testWidgets('search_filters_by_author', (tester) async {
      await _pump(
        tester,
        _Repository([_essays, _artOfWar, _wealth, _blindness]),
      );
      expect(find.text('4 books'), findsOneWidget);

      // Author only: case-insensitive.
      await tester.enterText(_search, 'SMITH');
      await tester.pumpAndSettle();
      expect(find.text('The Wealth of Nations'), findsWidgets);
      expect(find.text('The Art of War'), findsNothing);
      expect(find.text('The Essays of Warren Buffett'), findsNothing);
      expect(find.text('1 book'), findsOneWidget);

      // Diacritics are folded on both sides.
      await tester.enterText(_search, 'jose');
      await tester.pumpAndSettle();
      expect(find.text('Blindness'), findsWidgets);
      expect(find.text('1 book'), findsOneWidget);
      await tester.enterText(_search, 'Saramágo');
      await tester.pumpAndSettle();
      expect(find.text('Blindness'), findsWidgets);

      // Title still matches.
      await tester.enterText(_search, 'art of war');
      await tester.pumpAndSettle();
      expect(find.text('The Art of War'), findsWidgets);
      expect(find.text('Blindness'), findsNothing);

      // Clearing the query brings every book back.
      await tester.enterText(_search, '');
      await tester.pumpAndSettle();
      expect(find.text('4 books'), findsOneWidget);
      await _leave(tester);
    });

    testWidgets('search with no hits has its own empty state', (tester) async {
      await _pump(tester, _Repository([_essays, _wealth]));
      await tester.enterText(_search, 'zzz');
      await tester.pumpAndSettle();
      expect(find.text('0 books'), findsOneWidget);
      // One line, no body.
      expect(find.text('No books match your search.'), findsOneWidget);
      expect(find.text('No books match this view.'), findsNothing);
      // The filter copy does not apply to a search with no hits.
      expect(find.text('Nothing here yet'), findsNothing);
      expect(find.text('No saved books yet'), findsNothing);
      await _leave(tester);
    });
  });

  group('continue reading', () {
    testWidgets('hero shows chapter, progress, Continue and Listen', (
      tester,
    ) async {
      await _pump(
        tester,
        _Repository([_essays, _artOfWar, _wealth], resume: _essays),
      );
      expect(find.text('Continue reading'), findsOneWidget);
      expect(find.text('Ch. 6 · Accounting essays'), findsOneWidget);
      expect(find.text('Continue'), findsOneWidget);
      expect(find.text('Listen'), findsOneWidget);
      expect(_icon(V3Icons.headphones), findsOneWidget);
      await _leave(tester);
    });

    testWidgets('hero falls back to the first book in progress', (
      tester,
    ) async {
      await _pump(tester, _Repository([_artOfWar, _essays, _wealth]));
      expect(find.text('Continue reading'), findsOneWidget);
      // The hero names the in-progress book.
      expect(
        find.descendant(
          of: find.byKey(const Key('library-hero')),
          matching: find.text('The Essays of Warren Buffett'),
        ),
        findsWidgets,
      );
      await _leave(tester);
    });

    testWidgets('hero hides while searching and with nothing in progress', (
      tester,
    ) async {
      await _pump(tester, _Repository([_essays, _wealth], resume: _essays));
      expect(find.text('Continue reading'), findsOneWidget);
      await tester.enterText(_search, 'adam');
      await tester.pumpAndSettle();
      expect(find.text('Continue reading'), findsNothing);
      await _leave(tester);

      await _pump(tester, _Repository([_artOfWar, _wealth]));
      expect(find.text('Continue reading'), findsNothing);
      await _leave(tester);
    });

    testWidgets('chapter line is hidden when the book has no cursor', (
      tester,
    ) async {
      final plain = _book('p', 'Plain Book', 'Some Author', progress: 30);
      await _pump(tester, _Repository([plain], resume: plain));
      expect(find.text('Continue reading'), findsOneWidget);
      expect(find.textContaining('Ch.'), findsNothing);
      await _leave(tester);
    });

    testWidgets('Continue opens the reader', (tester) async {
      await _pump(tester, _Repository([_essays], resume: _essays));
      await tester.tap(find.text('Continue'));
      await tester.pumpAndSettle();
      final reader = tester.widget<BookReaderScreen>(
        find.byType(BookReaderScreen),
      );
      expect(reader.resourceId, 'essays');
      expect(reader.autoplayOnRestore, isFalse);
      expect(reader.startNarrationOnOpen, isFalse);
      // The library opens from You by default.
      expect(
        reader.shellBranchIndex,
        ActiveBookNarrationResume.profileBranchIndex,
      );
      await _leave(tester);
    });

    testWidgets('a library opened from Today opens books in Today (R3-M9)', (
      tester,
    ) async {
      await _pump(
        tester,
        _Repository([_essays], resume: _essays),
        home: const ReadingLibraryScreen(
          shellBranchIndex: ActiveBookNarrationResume.todayBranchIndex,
        ),
      );
      await tester.tap(find.text('Continue'));
      await tester.pumpAndSettle();
      final reader = tester.widget<BookReaderScreen>(
        find.byType(BookReaderScreen),
      );
      expect(
        reader.shellBranchIndex,
        ActiveBookNarrationResume.todayBranchIndex,
      );
      await _leave(tester);
    });

    testWidgets('Listen opens the reader and starts narration', (
      tester,
    ) async {
      await _pump(tester, _Repository([_essays], resume: _essays));
      await tester.tap(find.text('Listen'));
      await _openNarratingReader(tester);
      final reader = tester.widget<BookReaderScreen>(
        find.byType(BookReaderScreen),
      );
      expect(reader.resourceId, 'essays');
      // Starts even when the book was never narrated (no checkpoint).
      expect(reader.startNarrationOnOpen, isTrue);
      expect(reader.autoplayOnRestore, isFalse);
      await _leaveNarratingReader(tester);
    });
  });

  group('filters', () {
    testWidgets('All, Saved and Completed filter the list and the count', (
      tester,
    ) async {
      await _pump(tester, _Repository([_essays, _artOfWar, _wealth]));
      expect(find.text('All'), findsOneWidget);
      expect(find.text('Saved'), findsOneWidget);
      expect(find.text('Completed'), findsOneWidget);
      expect(find.text('3 books'), findsOneWidget);

      await tester.tap(find.text('Saved'));
      await tester.pumpAndSettle();
      expect(find.text('1 book'), findsOneWidget);
      expect(_row('essays'), findsOneWidget);
      expect(_row('artofwar'), findsNothing);

      await tester.tap(find.text('Completed'));
      await tester.pumpAndSettle();
      expect(find.text('1 book'), findsOneWidget);
      expect(_row('wealth'), findsOneWidget);
      expect(_row('essays'), findsNothing);
      await _leave(tester);
    });

    testWidgets('filter_saved_empty_state', (tester) async {
      await _pump(tester, _Repository([_artOfWar, _wealth]));
      await tester.tap(find.text('Saved'));
      await tester.pumpAndSettle();
      expect(find.text('0 books'), findsOneWidget);
      expect(find.text('No saved books yet'), findsOneWidget);
      expect(
        find.text('Save a book from its menu to find it here.'),
        findsOneWidget,
      );
      expect(find.text('The Art of War'), findsNothing);
      await _leave(tester);
    });

    testWidgets('an empty Completed filter reads "Nothing here yet"', (
      tester,
    ) async {
      await _pump(tester, _Repository([_artOfWar, _essays]));
      await tester.tap(find.text('Completed'));
      await tester.pumpAndSettle();
      expect(find.text('Nothing here yet'), findsOneWidget);
      expect(find.text('Books you finish will appear here.'), findsOneWidget);
      expect(find.textContaining('Save a book'), findsNothing);
      await _leave(tester);
    });

    testWidgets('an empty library reads "Nothing here yet"', (tester) async {
      await _pump(tester, _Repository(const []));
      expect(find.text('0 books'), findsOneWidget);
      expect(find.text('Nothing here yet'), findsOneWidget);
      expect(
        find.text('Books from your learning plan will appear here.'),
        findsOneWidget,
      );
      expect(find.textContaining('Save a book'), findsNothing);
      await _leave(tester);
    });

    testWidgets('each filter has its own empty body', (tester) async {
      // Books exist, but none is saved or finished.
      await _pump(tester, _Repository([_artOfWar]));
      expect(find.text('Nothing here yet'), findsNothing);

      await tester.tap(find.text('Saved'));
      await tester.pumpAndSettle();
      expect(find.text('No saved books yet'), findsOneWidget);
      expect(
        find.text('Save a book from its menu to find it here.'),
        findsOneWidget,
      );

      await tester.tap(find.text('Completed'));
      await tester.pumpAndSettle();
      expect(find.text('Nothing here yet'), findsOneWidget);
      expect(find.text('Books you finish will appear here.'), findsOneWidget);
      expect(find.text('No saved books yet'), findsNothing);
      await _leave(tester);
    });

    testWidgets('search combined with each filter updates the count', (
      tester,
    ) async {
      final savedSmith = _book(
        'smith2',
        'Theory of Moral Sentiments',
        'Adam Smith',
        saved: true,
      );
      await _pump(
        tester,
        _Repository([_essays, _artOfWar, _wealth, savedSmith]),
      );
      await tester.enterText(_search, 'smith');
      await tester.pumpAndSettle();
      // All: both Smith books.
      expect(find.text('2 books'), findsOneWidget);
      expect(_row('wealth'), findsOneWidget);
      expect(_row('smith2'), findsOneWidget);

      // Saved: only the saved one.
      await tester.tap(find.text('Saved'));
      await tester.pumpAndSettle();
      expect(find.text('1 book'), findsOneWidget);
      expect(_row('smith2'), findsOneWidget);
      expect(_row('wealth'), findsNothing);

      // Completed: only the finished one.
      await tester.tap(find.text('Completed'));
      await tester.pumpAndSettle();
      expect(find.text('1 book'), findsOneWidget);
      expect(_row('wealth'), findsOneWidget);

      // A search nobody matches is the search-empty state under any filter.
      await tester.enterText(_search, 'tzu');
      await tester.pumpAndSettle();
      expect(find.text('0 books'), findsOneWidget);
      expect(find.text('No books match your search.'), findsOneWidget);
      expect(find.text('No books match this view.'), findsNothing);
      expect(find.text('Nothing here yet'), findsNothing);
      await tester.tap(find.text('Saved'));
      await tester.pumpAndSettle();
      expect(find.text('No books match your search.'), findsOneWidget);
      expect(find.text('No saved books yet'), findsNothing);
      await tester.tap(find.text('All'));
      await tester.pumpAndSettle();
      expect(find.text('1 book'), findsOneWidget);
      expect(_row('artofwar'), findsOneWidget);
      await _leave(tester);
    });
  });

  group('rows', () {
    testWidgets('show author, access badges, progress ring, check and mark', (
      tester,
    ) async {
      await _pump(tester, _Repository([_essays, _artOfWar, _wealth]));

      // One study-guide badge per row; the original badge only where the
      // reader offers the original text.
      expect(find.text('Study guide'), findsNWidgets(3));
      expect(find.text('Original · public domain'), findsOneWidget);

      expect(find.text('Lawrence Cunningham'), findsOneWidget);
      expect(find.text('Sun Tzu'), findsOneWidget);
      // Progress ring with the percentage, a check for the finished book,
      // and the bookmark on the saved one only.
      expect(find.text('42'), findsOneWidget);
      expect(find.text('0'), findsOneWidget);
      expect(find.byType(V3Ring), findsNWidgets(2));
      expect(_icon(V3Icons.check), findsOneWidget);
      expect(_icon(V3Icons.bookmark), findsOneWidget);
      // The backend has no chapter total, so none is shown.
      expect(find.textContaining('chapters'), findsNothing);
      await _leave(tester);
    });

    testWidgets('tapping a row opens the reader', (tester) async {
      await _pump(tester, _Repository([_artOfWar, _wealth]));
      await tester.tap(find.text('Adam Smith'));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<BookReaderScreen>(find.byType(BookReaderScreen))
            .resourceId,
        'wealth',
      );
      await _leave(tester);
    });
  });

  group('states', () {
    for (final scale in [1.0, 2.0]) {
      testWidgets('lays out at 320 pt wide, text x$scale, without overflow', (
        tester,
      ) async {
        final repo = _Repository([
          _essays,
          _artOfWar,
          _wealth,
        ], resume: _essays);
        tester.view.physicalSize = const Size(320, 1800);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              contentResourcesRepositoryProvider.overrideWithValue(repo),
            ],
            child: MaterialApp(
              theme: AppTheme.light,
              builder: (context, child) => MediaQuery(
                data: MediaQuery.of(
                  context,
                ).copyWith(textScaler: TextScaler.linear(scale)),
                child: child!,
              ),
              home: const ReadingLibraryScreen(),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.text('Original · public domain'), findsOneWidget);
        expect(tester.takeException(), isNull);
        await _leave(tester);
      });
    }

    testWidgets('a failed load shows the retry state', (tester) async {
      final repo = _Repository([_essays], fail: true);
      await _pump(tester, repo);
      expect(find.text('Couldn’t load your reading library.'), findsOneWidget);
      repo.fail = false;
      await tester.tap(find.text('Try again'));
      await tester.pumpAndSettle();
      expect(find.text('The Essays of Warren Buffett'), findsWidgets);
      await _leave(tester);
    });

    testWidgets('loading shows skeletons, not a spinner', (tester) async {
      final gate = Completer<List<ContentResource>>();
      final repo = _GatedRepository(gate.future);
      tester.view.physicalSize = const Size(430, 1800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            contentResourcesRepositoryProvider.overrideWithValue(repo),
          ],
          child: MaterialApp(
            theme: AppTheme.light,
            home: const ReadingLibraryScreen(),
          ),
        ),
      );
      await tester.pump();
      expect(find.byType(V3Skel), findsWidgets);
      expect(find.byType(CircularProgressIndicator), findsNothing);
      gate.complete([_essays]);
      await tester.pumpAndSettle();
      expect(find.byType(V3Skel), findsNothing);
      await _leave(tester);
    });
  });

  group('refresh in place', () {
    final many = [for (var i = 0; i < 30; i++) _book('b$i', 'Book $i', 'A $i')];

    testWidgets('returning from the reader keeps the list mounted', (
      tester,
    ) async {
      final repo = _Repository(many);
      await _pump(tester, repo, size: const Size(430, 800));
      final scroll = find.byType(CustomScrollView);
      await tester.drag(scroll, const Offset(0, -600));
      await tester.pumpAndSettle();
      final position = tester
          .state<ScrollableState>(
            find
                .descendant(of: scroll, matching: find.byType(Scrollable))
                .first,
          )
          .position;
      final offset = position.pixels;
      expect(offset, greaterThan(300));
      final before = tester.element(_row('b5'));

      await tester.tap(_row('b5'));
      await tester.pumpAndSettle();
      expect(find.byType(BookReaderScreen), findsOneWidget);

      // Back from the reader with the reload still in flight.
      final gate = Completer<List<ContentResource>>();
      repo.hold = gate;
      await _backFromReader(tester);
      expect(repo.lists, 2);
      expect(find.byType(V3Skel), findsNothing);
      expect(identical(tester.element(_row('b5')), before), isTrue);
      expect(position.pixels, offset);

      // The reload lands: rows update without remounting.
      gate.complete([
        for (final b in many)
          b.id == 'b5' ? _book('b5', 'Book 5', 'A 5', progress: 61) : b,
      ]);
      await tester.pumpAndSettle();
      expect(find.byType(V3Skel), findsNothing);
      expect(identical(tester.element(_row('b5')), before), isTrue);
      expect(position.pixels, offset);
      expect(find.text('61'), findsOneWidget);
      await _leave(tester);
    });

    testWidgets('pull to refresh does not blank the list', (tester) async {
      final repo = _Repository(many);
      await _pump(tester, repo, size: const Size(430, 800));
      final before = tester.element(_row('b0'));
      final gate = Completer<List<ContentResource>>();
      repo.hold = gate;

      await tester.fling(
        find.byType(CustomScrollView),
        const Offset(0, 400),
        1000,
      );
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      expect(repo.lists, 2);
      expect(find.byType(V3Skel), findsNothing);
      expect(identical(tester.element(_row('b0')), before), isTrue);

      gate.complete(many);
      await tester.pumpAndSettle();
      expect(find.byType(V3Skel), findsNothing);
      expect(identical(tester.element(_row('b0')), before), isTrue);
      await _leave(tester);
    });

    testWidgets('a failed refresh keeps the list', (tester) async {
      final repo = _Repository(many);
      await _pump(tester, repo, size: const Size(430, 800));
      repo.fail = true;
      await tester.fling(
        find.byType(CustomScrollView),
        const Offset(0, 400),
        1000,
      );
      await tester.pumpAndSettle();
      expect(repo.lists, 2);
      expect(find.text('Couldn’t load your reading library.'), findsNothing);
      expect(_row('b0'), findsOneWidget);
      await _leave(tester);
    });
  });

  group('lazy rows', () {
    final hundred = [
      for (var i = 0; i < 100; i++) _book('b$i', 'Book $i', 'A $i'),
    ];

    testWidgets('only the rows near the screen are built', (tester) async {
      await _pump(tester, _Repository(hundred), size: const Size(430, 800));
      expect(find.text('100 books'), findsOneWidget);
      expect(find.byType(V3Ring), findsWidgets);
      expect(find.byType(V3Ring).evaluate().length, lessThan(30));
      expect(_row('b99'), findsNothing);

      await tester.scrollUntilVisible(
        _row('b50'),
        600,
        scrollable: find
            .descendant(
              of: find.byType(CustomScrollView),
              matching: find.byType(Scrollable),
            )
            .first,
      );
      expect(_row('b50'), findsOneWidget);
      // Every row has the same entrance wrapper, so a row keeps its state
      // wherever a search moves it.
      expect(
        find.descendant(of: _row('b50'), matching: find.byType(V3Rise)),
        findsOneWidget,
      );
      await _leave(tester);
    });

    testWidgets('the first rows rise, staggered', (tester) async {
      await _pump(tester, _Repository(hundred), size: const Size(430, 800));
      expect(
        find.descendant(of: _row('b0'), matching: find.byType(V3Rise)),
        findsOneWidget,
      );
      await _leave(tester);
    });
  });

  group('covers', () {
    testWidgets('use the shared ground and the short title', (tester) async {
      final book = _book(
        'ds',
        'Decision Systems: A Field Guide',
        'A. Author',
        progress: 30,
      );
      await _pump(tester, _Repository([book], resume: book));
      final covers = tester.widgetList<V3Cover>(find.byType(V3Cover)).toList();
      expect(covers, hasLength(2)); // hero + row
      for (final cover in covers) {
        expect(cover.title, 'Decision Systems');
        expect(cover.background, v3CoverGround('ds'));
        expect(cover.foreground, kV3CoverInk);
      }
      // The row still names the whole title.
      expect(find.text('Decision Systems: A Field Guide'), findsWidgets);
      await _leave(tester);
    });

    test('v3CoverGround is stable and drawn from the shared grounds', () {
      expect(v3CoverGround('essays'), v3CoverGround('essays'));
      for (final id in ['a', 'essays', 'wealth', 'artofwar', '']) {
        expect(kV3CoverGrounds, contains(v3CoverGround(id)));
      }
    });
  });

  group('hero', () {
    testWidgets('has no grain and a 4 pt ember progress bar', (tester) async {
      await _pump(tester, _Repository([_essays], resume: _essays));
      final hero = find.byKey(const Key('library-hero'));
      // The cover paints its own grain; the card adds none.
      expect(
        find.descendant(of: hero, matching: find.byType(V3Grain)),
        findsNWidgets(
          find
              .descendant(of: hero, matching: find.byType(V3Cover))
              .evaluate()
              .length,
        ),
      );
      final bar = tester.widget<V3Bar>(
        find.descendant(of: hero, matching: find.byType(V3Bar)),
      );
      expect(bar.value, closeTo(.42, 1e-9));
      expect(bar.height, 4);
      expect(bar.color, AppColors.ember);
      expect(bar.track, const Color(0x24FFFFFF));
      await _leave(tester);
    });

    testWidgets('a completed continue-reading entry is skipped', (
      tester,
    ) async {
      await _pump(tester, _Repository([_essays, _wealth], resume: _wealth));
      final hero = find.byKey(const Key('library-hero'));
      expect(hero, findsOneWidget);
      expect(
        find.descendant(
          of: hero,
          matching: find.text('The Essays of Warren Buffett'),
        ),
        findsWidgets,
      );
      expect(
        find.descendant(of: hero, matching: find.text('The Wealth of Nations')),
        findsNothing,
      );
      await _leave(tester);

      // Nothing in progress: no hero at all.
      await _pump(tester, _Repository([_artOfWar, _wealth], resume: _wealth));
      expect(hero, findsNothing);
      await _leave(tester);
    });

    testWidgets('a continue-reading entry that is not a book is skipped', (
      tester,
    ) async {
      const article = ContentResource(
        id: 'article',
        kind: 'article',
        canonicalKey: 'article:1',
        title: 'An article',
        licenseStatus: 'x',
        isSaved: false,
        progressPercent: 50,
      );
      await _pump(tester, _Repository([_artOfWar], resume: article));
      expect(find.byKey(const Key('library-hero')), findsNothing);
      expect(find.text('An article'), findsNothing);
      await _leave(tester);
    });

    testWidgets('Listen toggles the book that is already narrating', (
      tester,
    ) async {
      final remote = _FakeRemote('essays');
      await _pump(
        tester,
        _Repository([_essays], resume: _essays),
        overrides: [
          bookNarrationRemoteControllerProvider.overrideWith((ref) => remote),
        ],
      );
      await tester.tap(find.text('Listen'));
      await tester.pumpAndSettle();
      expect(remote.toggles, 1);
      expect(find.byType(BookReaderScreen), findsNothing);
      await _leave(tester);
    });

    testWidgets('Listen on book B while A plays switches to B', (
      tester,
    ) async {
      final remote = _FakeRemote('art-of-war', playingNow: true);
      await _pump(
        tester,
        _Repository([_essays], resume: _essays),
        overrides: [
          bookNarrationRemoteControllerProvider.overrideWith((ref) => remote),
        ],
      );
      // A plays: B's hero does not claim it.
      expect(find.byType(BookNarrationWaves), findsNothing);
      await tester.tap(find.text('Listen'));
      await _openNarratingReader(tester);
      // A is not paused in place: B opens and starts (its reader takes the
      // session over, which stops A).
      expect(remote.toggles, 0);
      final reader = tester.widget<BookReaderScreen>(
        find.byType(BookReaderScreen),
      );
      expect(reader.resourceId, 'essays');
      expect(reader.startNarrationOnOpen, isTrue);
      await _leaveNarratingReader(tester);
    });

    testWidgets('the hero shows playing for the book actually playing', (
      tester,
    ) async {
      final remote = _FakeRemote('essays', playingNow: true);
      await _pump(
        tester,
        _Repository([_essays], resume: _essays),
        overrides: [
          bookNarrationRemoteControllerProvider.overrideWith((ref) => remote),
        ],
        settle: false,
      );
      final waves = find.byType(BookNarrationWaves);
      expect(waves, findsOneWidget);
      final listen = tester.widget<V3Button>(
        find.ancestor(of: waves, matching: find.byType(V3Button)),
      );
      expect(listen.semanticLabel, 'Listening');
      expect(
        find.descendant(
          of: find.byKey(const Key('library-hero')),
          matching: find.text('Listen'),
        ),
        findsOneWidget,
      );
      await _leave(tester);
    });
  });

  group('search field', () {
    testWidgets('a clear button replaces the search icon while typing', (
      tester,
    ) async {
      await _pump(tester, _Repository([_essays, _artOfWar, _wealth]));
      expect(_icon(V3Icons.x), findsNothing);
      await tester.enterText(_search, 'smith');
      await tester.pumpAndSettle();
      expect(_icon(V3Icons.search), findsNothing);
      expect(_icon(V3Icons.x), findsOneWidget);
      expect(find.text('1 book'), findsOneWidget);

      final target = find.ancestor(
        of: _icon(V3Icons.x),
        matching: find.byType(V3Pressable),
      );
      expect(tester.getSize(target).width, greaterThanOrEqualTo(44));
      expect(tester.getSize(target).height, greaterThanOrEqualTo(44));

      await tester.tap(_icon(V3Icons.x));
      await tester.pumpAndSettle();
      expect(tester.widget<TextField>(_search).controller!.text, isEmpty);
      expect(find.text('3 books'), findsOneWidget);
      expect(_icon(V3Icons.search), findsOneWidget);
      expect(_icon(V3Icons.x), findsNothing);
      await _leave(tester);
    });

    test('foldSearchText lower-cases and strips diacritics', () {
      expect(foldSearchText('José'), 'jose');
      expect(foldSearchText('José'), 'jose'); // already decomposed
      expect(foldSearchText('Dvořák'), 'dvorak');
      expect(foldSearchText('Łódź'), 'lodz');
      expect(foldSearchText('Straße'), 'strasse');
      expect(foldSearchText('Œuvre'), 'oeuvre');
      expect(foldSearchText('Ærø'), 'aero');
      expect(foldSearchText('Ångström'), 'angstrom');
      expect(foldSearchText('İstanbul'), 'istanbul');
      expect(foldSearchText('Đorđe'), 'dorde');
      expect(foldSearchText('Достоевский'), 'достоевский');
      expect(foldSearchText('Sun Tzu'), 'sun tzu');
    });
  });

  group('accessibility', () {
    testWidgets('Reading is a header and the count is a live region', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      await _pump(tester, _Repository([_essays, _wealth]));
      expect(
        tester.getSemantics(find.text('Reading')),
        matchesSemantics(label: 'Reading', isHeader: true),
      );
      expect(
        tester.getSemantics(find.text('2 books')),
        matchesSemantics(label: '2 books', isLiveRegion: true),
      );
      handle.dispose();
      await _leave(tester);
    });

    testWidgets('a row reads title, author, access, progress and saved', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      await _pump(tester, _Repository([_essays, _artOfWar, _wealth]));
      Finder label(String text) => find.bySemanticsLabel(text);
      expect(
        label(
          'The Essays of Warren Buffett, Lawrence Cunningham, Study guide, '
          '42% read, Saved',
        ),
        findsOneWidget,
      );
      expect(
        label(
          'The Art of War, Sun Tzu, Study guide, Original · public domain, '
          '0% read',
        ),
        findsOneWidget,
      );
      expect(
        label('The Wealth of Nations, Adam Smith, Study guide, Completed'),
        findsOneWidget,
      );
      // The whole row is the tap target.
      final size = tester.getSize(_row('essays'));
      expect(size.height, greaterThanOrEqualTo(44));
      expect(size.width, greaterThanOrEqualTo(44));
      handle.dispose();
      await _leave(tester);
    });
  });

  group('entrance', () {
    final hundred = [
      for (var i = 0; i < 100; i++) _book('b$i', 'Book $i', 'A $i'),
    ];
    Finder list() => find.byType(CustomScrollView);

    testWidgets('rows do not rise again after scrolling away and back', (
      tester,
    ) async {
      await _pump(tester, _Repository(hundred), size: const Size(430, 800));
      // While the entrance runs, the first row is still on its way in.
      await tester.pump(const Duration(seconds: 2)); // the entrance is over
      await tester.drag(list(), const Offset(0, -4000));
      await tester.pumpAndSettle();
      expect(_row('b0'), findsNothing);

      await tester.drag(list(), const Offset(0, 4000));
      await tester.pump(); // one frame after returning
      for (final id in ['b0', 'b1', 'b2', 'b3']) {
        expect(_row(id), findsOneWidget, reason: id);
        expect(_riseOpacity(tester, id), 1.0, reason: id);
      }
      await _leave(tester);
    });

    testWidgets('a row a search moves up does not restart its entrance', (
      tester,
    ) async {
      final books = [
        for (var i = 0; i < 12; i++) _book('b$i', 'Book $i', 'Writer $i'),
        _book('target', 'Target Title', 'Zed Special'),
      ];
      await _pump(tester, _Repository(books));
      await tester.pump(const Duration(seconds: 2));
      expect(_riseOpacity(tester, 'target'), 1.0);

      // The row moves from index 12 to index 0.
      await tester.enterText(_search, 'zed');
      await tester.pump();
      expect(_row('target'), findsOneWidget);
      expect(_riseOpacity(tester, 'target'), 1.0);

      // And back down again as the query is cleared.
      await tester.enterText(_search, '');
      await tester.pump();
      expect(_riseOpacity(tester, 'target'), 1.0);
      await _leave(tester);
    });

    testWidgets('rows still rise in on the first load', (tester) async {
      final repo = _Repository([_essays, _artOfWar, _wealth]);
      tester.view.physicalSize = const Size(430, 1800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            contentResourcesRepositoryProvider.overrideWithValue(repo),
          ],
          child: MaterialApp(
            theme: AppTheme.light,
            home: const ReadingLibraryScreen(),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      // The last row has not started yet (delay 120 ms).
      expect(_riseOpacity(tester, 'wealth'), 0.0);
      await tester.pumpAndSettle();
      expect(_riseOpacity(tester, 'wealth'), 1.0);
      await _leave(tester);
    });
  });

  group('refresh failures and ordering', () {
    final many = [for (var i = 0; i < 12; i++) _book('b$i', 'Book $i', 'A $i')];
    const toast = 'Couldn’t refresh — try again.';

    testWidgets('a failed pull to refresh says so', (tester) async {
      final repo = _Repository(many);
      await _pump(tester, repo, size: const Size(430, 800));
      repo.fail = true;
      await tester.fling(
        find.byType(CustomScrollView),
        const Offset(0, 400),
        1000,
      );
      await tester.pumpAndSettle();
      expect(find.text(toast), findsOneWidget);
      // The list stays as it was.
      expect(_row('b0'), findsOneWidget);
      expect(find.text('Couldn’t load your reading library.'), findsNothing);
      await tester.pump(const Duration(seconds: 4));
      await _leave(tester);
    });

    testWidgets('a failed reload after the reader stays quiet', (tester) async {
      final repo = _Repository(many);
      await _pump(tester, repo, size: const Size(430, 800));
      await tester.tap(_row('b1'));
      await tester.pumpAndSettle();
      repo.fail = true;
      await _backFromReader(tester);
      await tester.pumpAndSettle();
      expect(repo.lists, 2);
      expect(find.text(toast), findsNothing);
      expect(_row('b1'), findsOneWidget);
      await _leave(tester);
    });

    testWidgets('a slow earlier load cannot overwrite a newer one', (
      tester,
    ) async {
      final repo = _Repository(many);
      await _pump(tester, repo, size: const Size(430, 800));
      final slow = Completer<List<ContentResource>>();
      final fast = Completer<List<ContentResource>>();
      repo.holds.addAll([slow, fast]);

      // Load 2: a pull to refresh, held.
      await tester.fling(
        find.byType(CustomScrollView),
        const Offset(0, 400),
        1000,
      );
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      expect(repo.lists, 2);

      // Load 3: opening a book and coming back, also held.
      await tester.tap(_row('b2'));
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      await tester.pump(const Duration(seconds: 1));
      expect(find.byType(BookReaderScreen), findsOneWidget);
      await _backFromReader(tester);
      expect(repo.lists, 3);

      List<ContentResource> withProgress(int percent) => [
        for (final b in many)
          b.id == 'b2' ? _book('b2', 'Book 2', 'A 2', progress: percent) : b,
      ];
      // The newer load lands first, then the older one with stale data.
      fast.complete(withProgress(61));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));
      expect(find.text('61'), findsOneWidget);
      slow.complete(withProgress(7));
      await tester.pumpAndSettle();
      expect(find.text('61'), findsOneWidget);
      expect(find.text('7'), findsNothing);
      await _leave(tester);
    });
  });

  group('cover title', () {
    test('v3CoverTitle cuts only at a subtitle separator', () {
      expect(v3CoverTitle('The Art of War: A Guide'), 'The Art of War');
      expect(v3CoverTitle('Deep Work — Rules for Focus'), 'Deep Work');
      expect(v3CoverTitle('  Spaced Title : Sub  '), 'Spaced Title');
      expect(v3CoverTitle('A: B: C'), 'A');
      expect(v3CoverTitle('One — Two: Three'), 'One');
      // Commas and semicolons are part of the title.
      expect(
        v3CoverTitle('Thinking, Fast and Slow'),
        'Thinking, Fast and Slow',
      );
      expect(
        v3CoverTitle('Moby Dick; Or, The Whale'),
        'Moby Dick; Or, The Whale',
      );
      // A colon with no space (a time, a ratio) and a hyphen are not cuts.
      expect(v3CoverTitle('Catch-22'), 'Catch-22');
      expect(v3CoverTitle('Ratio 3:1'), 'Ratio 3:1');
      // Nothing left of the cut: keep the whole title.
      expect(v3CoverTitle(': Odd'), ': Odd');
      expect(v3CoverTitle(''), '');
    });
  });

  group('folding', () {
    testWidgets('thich nhat hanh finds Thích Nhất Hạnh', (tester) async {
      final tnh = _book('tnh', 'Peace Is Every Step', 'Thích Nhất Hạnh');
      await _pump(tester, _Repository([_essays, tnh, _wealth]));
      await tester.enterText(_search, 'thich nhat hanh');
      await tester.pumpAndSettle();
      expect(find.text('1 book'), findsOneWidget);
      expect(_row('tnh'), findsOneWidget);
      // And the other way round: a marked query finds plain text.
      await tester.enterText(_search, 'Ádám Smíth');
      await tester.pumpAndSettle();
      expect(_row('wealth'), findsOneWidget);
      await _leave(tester);
    });

    test('Latin Extended-Additional and the Romanian comma letters fold', () {
      expect(foldSearchText('Thích Nhất Hạnh'), 'thich nhat hanh');
      expect(foldSearchText('Nguyễn Huệ'), 'nguyen hue');
      expect(foldSearchText('Trương Đặng'), 'truong dang');
      expect(foldSearchText('Phở bò Ngọc Ưu'), 'pho bo ngoc uu');
      expect(foldSearchText('Mỹ Quỳnh Vỹ Ỵ'), 'my quynh vy y');
      expect(foldSearchText('Ștefan Țepeș'), 'stefan tepes');
      // The decomposed form (letter + marks) folds to the same text.
      expect(foldSearchText('Nhất Hạnh'), foldSearchText('Nhất Hạnh'));
    });
  });
}

class _FakeRemote extends BookNarrationRemoteController {
  _FakeRemote(this._book, {this.playingNow = false});

  final String _book;
  final bool playingNow;
  int toggles = 0;

  @override
  bool get active => true;

  @override
  String? get resourceId => _book;

  @override
  bool get playing => playingNow;

  @override
  Future<void> toggle() async => toggles++;
}

class _GatedRepository extends _Repository {
  _GatedRepository(this.gate) : super(const []);
  final Future<List<ContentResource>> gate;

  @override
  Future<List<ContentResource>> listLibraryResources({
    String? kind,
    String? query,
    String? sort,
    int limit = 50,
    int offset = 0,
  }) => gate;
}
