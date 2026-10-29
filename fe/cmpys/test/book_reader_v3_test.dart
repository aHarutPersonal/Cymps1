import 'dart:async';
import 'dart:math' as math;

import 'package:cmpys/app/design_tokens.dart';
import 'package:cmpys/core/network/dio_client.dart';
import 'package:cmpys/core/storage/token_store.dart';
import 'package:cmpys/core/ui/v3/v3.dart' show AccessType;
import 'package:cmpys/features/cmpys/state/cmpys_store.dart';
import 'package:cmpys/features/plan/presentation/book_narration.dart';
import 'package:cmpys/features/plan/presentation/book_reader_screen.dart';
import 'package:cmpys/features/plan/presentation/material_web_screen.dart';
import 'package:cmpys/features/session/data/content_resources_repository.dart';
import 'package:cmpys/features/session/models/content_resource.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'fixtures/comparison_reader_harness.dart' show ComparisonPreviewNarrator;

const _firstParagraph =
    'A useful decision starts by separating a reversible choice from an '
    'irreversible one.';

final _markdown = [
  '## Decision Systems',
  _firstParagraph,
  for (var i = 1; i <= 14; i++)
    'Paragraph $i keeps the reader busy with a long, steady passage about '
        'choosing well, so the chapter is tall enough to scroll on a phone.',
  '## Attention Loops',
  'Attention improves when unfinished work has an explicit return point.',
  '## Closing Synthesis',
  'Combine the decision label and return point in one daily review.',
].join('\n\n');

class _Repository extends ContentResourcesRepository {
  _Repository({
    this.readingUrl,
    this.kind = 'llm_book_summary',
    String? markdown,
    this.initial = const [],
    this.failLoad = false,
  }) : markdown = markdown ?? _markdown,
       super(dioClient: DioClient(tokenStore: TokenStore()));

  final String? readingUrl;

  /// The guide cannot be loaded, so the reader shows its error state.
  final bool failLoad;
  final String kind;
  final String markdown;
  final List<ContentHighlight> initial;
  final deleted = <String>[];
  bool saved = false;
  int saveCalls = 0;
  int unsaveCalls = 0;
  final created = <ContentHighlight>[];
  final locators = <Map<String, dynamic>?>[];

  @override
  Future<ContentResource> getResource(String resourceId) async {
    if (failLoad) throw StateError('unavailable');
    return ContentResource(
      id: 'book-1',
      kind: kind,
      canonicalKey: 'book:author:decision_systems',
      title: 'Decision Systems',
      authorOrCreator: 'A. Author',
      licenseStatus: 'llm_summary',
      contentMarkdown: markdown,
      summaryJson: readingUrl == null ? null : {'reading_url': readingUrl},
      isSaved: saved,
      progressPercent: 0,
    );
  }

  @override
  Future<void> saveResource(String resourceId) async {
    saveCalls++;
    saved = true;
  }

  @override
  Future<void> unsaveResource(String resourceId) async {
    unsaveCalls++;
    saved = false;
  }

  @override
  Future<List<ContentHighlight>> listHighlights(String resourceId) async =>
      initial;

  @override
  Future<void> deleteHighlight(String resourceId, String highlightId) async {
    deleted.add(highlightId);
  }

  @override
  Future<ContentHighlight> createHighlight(
    String resourceId, {
    Map<String, dynamic>? locatorJson,
    String? quoteText,
    String? noteText,
  }) async {
    final now = DateTime.utc(2026, 10, 27);
    final highlight = ContentHighlight(
      id: 'h${created.length + 1}',
      contentResourceId: resourceId,
      locatorJson: locatorJson,
      quoteText: quoteText,
      noteText: noteText,
      createdAt: now,
      updatedAt: now,
    );
    created.add(highlight);
    locators.add(locatorJson);
    return highlight;
  }

  @override
  Future<ContentResource> updateProgress(
    String resourceId, {
    required int progressPercent,
    Map<String, dynamic>? cursorJson,
    bool? completed,
  }) => getResource(resourceId);
}

Future<ProviderContainer> _pump(
  WidgetTester tester,
  _Repository repository, {
  NavigatorObserver? observer,
  String? fallbackSourceUrl,
}) async {
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final container = ProviderContainer(
    overrides: [
      contentResourcesRepositoryProvider.overrideWithValue(repository),
    ],
  );
  addTearDown(container.dispose);
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        navigatorObservers: [?observer],
        home: BookReaderScreen(
          resourceId: 'book-1',
          fallbackTitle: 'Decision Systems',
          fallbackSourceUrl: fallbackSourceUrl,
          narrator: ComparisonPreviewNarrator(),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return container;
}

Future<void> _end(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox());
  await tester.pumpAndSettle();
}

Finder _paragraph(String text) => find.textContaining(text, findRichText: true);

/// Records pushed screens without building them (the web viewer needs a
/// platform view a widget test does not have).
class _Opened extends NavigatorObserver {
  final List<Widget> screens = [];

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    if (previousRoute == null || route is! MaterialPageRoute) return;
    screens.add(route.builder(navigator!.context));
    scheduleMicrotask(() => route.navigator?.removeRoute(route));
  }
}

ContentHighlight _highlight(String id, String quote, {String? note}) {
  final now = DateTime.utc(2026, 10, 27);
  return ContentHighlight(
    id: id,
    contentResourceId: 'book-1',
    locatorJson: const {'chapter': 0, 'chapterTitle': 'Decision Systems'},
    quoteText: quote,
    noteText: note,
    createdAt: now,
    updatedAt: now,
  );
}

Color? _wash(WidgetTester tester, String key) {
  final box = tester.widget<AnimatedContainer>(
    find
        .descendant(
          of: find.byKey(ValueKey(key)),
          matching: find.byType(AnimatedContainer),
        )
        .first,
  );
  return (box.decoration as BoxDecoration?)?.color;
}

Future<void> _openMenu(WidgetTester tester) async {
  await tester.tap(find.bySemanticsLabel('Book menu'));
  await tester.pumpAndSettle();
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('bookReaderParagraphs splits blocks and keeps fences whole', () {
    final blocks = bookReaderParagraphs(
      [
        'A **bold** start.',
        '### Practice This\n1. Label one decision.\n2. Write the next step.',
        '```comparison\nLeft | Right\n\nStill inside\n```',
        '> A quoted\n> line.',
      ].join('\n\n'),
    );
    expect(blocks.map((b) => b.markdown), [
      'A **bold** start.',
      '### Practice This',
      '1. Label one decision.\n2. Write the next step.',
      '```comparison\nLeft | Right\n\nStill inside\n```',
      '> A quoted\n> line.',
    ]);
    expect(blocks.map((b) => b.text), [
      'A bold start.',
      'Practice This',
      'Label one decision. Write the next step.',
      'Left | Right Still inside',
      'A quoted line.',
    ]);
    expect(blocks.map((b) => b.tappable), [true, false, true, false, true]);
  });

  test('unescapeNarrationText decodes entities once', () {
    expect(
      unescapeNarrationText(
        '&quot;go&quot; &amp; &#39;stay&#39; &lt;3 &#x2014;',
      ),
      '"go" & \'stay\' <3 —',
    );
    expect(unescapeNarrationText('&amp;quot;'), '&quot;');
    expect(unescapeNarrationText('Plain text'), 'Plain text');
    expect(unescapeNarrationText('&unknown; & alone'), '&unknown; & alone');
  });

  testWidgets('paragraph_tap_shows_actions', (tester) async {
    final repository = _Repository();
    await _pump(tester, repository);
    expect(find.text('Highlight'), findsNothing);

    await tester.tap(_paragraph('A useful decision starts'));
    await tester.pumpAndSettle();
    expect(find.text('Highlight'), findsOneWidget);
    expect(find.text('Note'), findsOneWidget);
    expect(find.text('Quote'), findsOneWidget);

    // Highlight goes through the existing highlights API.
    await tester.tap(find.text('Highlight'));
    await tester.pumpAndSettle();
    expect(repository.created, hasLength(1));
    expect(repository.created.single.quoteText, _firstParagraph);
    expect(repository.created.single.noteText, isNull);
    expect(repository.locators.single, {
      'chapter': 0,
      'chapterTitle': 'Decision Systems',
    });
    expect(find.text('Highlighted'), findsOneWidget);
    expect(find.text('Quote'), findsNothing);

    // Note opens the note sheet and saves a note on the same paragraph.
    await tester.tap(_paragraph('A useful decision starts'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Note'));
    await tester.pumpAndSettle();
    expect(find.text('Add a note'), findsOneWidget);
    await tester.enterText(find.byType(TextField), 'Label it first.');
    await tester.pump();
    await tester.tap(find.text('Save note'));
    await tester.pumpAndSettle();
    expect(repository.created, hasLength(2));
    expect(repository.created.last.noteText, 'Label it first.');
    expect(repository.created.last.quoteText, _firstParagraph);
    expect(find.text('Note saved to this book'), findsOneWidget);
    expect(find.text('Add a note'), findsNothing);

    // Quote copies the paragraph (no quote/share action exists yet).
    String? copied;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.setData') {
          copied = (call.arguments as Map)['text'] as String?;
        }
        return null;
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      ),
    );
    await tester.tap(_paragraph('Paragraph 1 keeps'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Quote'));
    await tester.pumpAndSettle();
    expect(copied, startsWith('Paragraph 1 keeps the reader busy'));
    expect(find.text('Copied quote'), findsOneWidget);
    expect(repository.created, hasLength(2));

    // The menu counts the book's notes and highlights.
    await _openMenu(tester);
    expect(find.text('Notes & highlights · 2'), findsOneWidget);
    await tester.tap(find.text('Notes & highlights · 2'));
    await tester.pumpAndSettle();
    expect(find.text('Note · Ch. 1'), findsOneWidget);
    expect(find.text('Highlight · Ch. 1'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await _end(tester);
  });

  testWidgets('menu_save_toggles', (tester) async {
    final repository = _Repository();
    await _pump(tester, repository);

    await _openMenu(tester);
    expect(find.text('Contents'), findsOneWidget);
    expect(find.text('Notes & highlights · 0'), findsOneWidget);
    expect(find.text('Reading settings'), findsOneWidget);
    await tester.tap(find.text('Save book'));
    await tester.pumpAndSettle();
    expect(repository.saveCalls, 1);
    expect(find.text('Book saved'), findsOneWidget);
    expect(find.text('Save book'), findsNothing);

    await _openMenu(tester);
    await tester.tap(find.text('Remove from saved'));
    await tester.pumpAndSettle();
    expect(repository.unsaveCalls, 1);
    expect(find.text('Removed from saved'), findsOneWidget);

    await _openMenu(tester);
    expect(find.text('Save book'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await _end(tester);
  });

  testWidgets('chrome hides on scroll-down and returns on scroll-up', (
    tester,
  ) async {
    await _pump(tester, _Repository());
    AnimatedSlide chrome() =>
        tester.widget<AnimatedSlide>(find.byKey(BookReaderScreen.chromeKey));
    AnimatedSlide fab() =>
        tester.widget<AnimatedSlide>(find.byKey(BookReaderScreen.listenKey));
    expect(chrome().offset, Offset.zero);
    expect(find.byKey(const Key('book-listen-button')), findsOneWidget);

    await tester.dragFrom(const Offset(195, 600), const Offset(0, -400));
    await tester.pumpAndSettle();
    expect(chrome().offset.dy, lessThan(0));
    expect(fab().offset.dy, greaterThan(0));

    await tester.dragFrom(const Offset(195, 400), const Offset(0, 120));
    await tester.pumpAndSettle();
    expect(chrome().offset, Offset.zero);
    expect(fab().offset, Offset.zero);
    await _end(tester);
  });

  testWidgets('a restored chapter offset does not flicker the chrome', (
    tester,
  ) async {
    await _pump(tester, _Repository());
    AnimatedSlide chrome() =>
        tester.widget<AnimatedSlide>(find.byKey(BookReaderScreen.chromeKey));
    await tester.dragFrom(const Offset(195, 600), const Offset(0, -400));
    await tester.pumpAndSettle();
    expect(chrome().offset.dy, lessThan(0));

    // Over to chapter 2 and back: chapter 1 comes back mid-page. (Swipes
    // start in the page margin; over text, SelectionArea takes the drag.)
    await tester.dragFrom(const Offset(384, 400), const Offset(-320, 0));
    await tester.pumpAndSettle();
    expect(find.text('CHAPTER 2'), findsOneWidget);
    expect(chrome().offset, Offset.zero);
    await tester.dragFrom(const Offset(6, 400), const Offset(320, 0));
    await tester.pumpAndSettle();
    expect(find.text('Chapter 1 of 3'), findsOneWidget);
    expect(chrome().offset, Offset.zero);

    // Scrolling up from the restored offset keeps the chrome shown.
    await tester.dragFrom(const Offset(195, 400), const Offset(0, 60));
    await tester.pumpAndSettle();
    expect(chrome().offset, Offset.zero);
    await _end(tester);
  });

  testWidgets('chrome hides instantly under reduced motion', (tester) async {
    tester.platformDispatcher.accessibilityFeaturesTestValue =
        const FakeAccessibilityFeatures(disableAnimations: true);
    addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
    await _pump(tester, _Repository());
    await tester.dragFrom(const Offset(195, 600), const Offset(0, -400));
    await tester.pump();
    final chrome = tester.widget<AnimatedSlide>(
      find.byKey(BookReaderScreen.chromeKey),
    );
    expect(chrome.offset.dy, lessThan(0));
    expect(chrome.duration, Duration.zero);
    await _end(tester);
  });

  testWidgets('menu hides Read original book without a URL', (tester) async {
    await _pump(tester, _Repository());
    await _openMenu(tester);
    expect(find.text('Save book'), findsOneWidget);
    expect(find.text('Read original book'), findsNothing);
    await _end(tester);

    await _pump(
      tester,
      _Repository(readingUrl: 'https://www.gutenberg.org/ebooks/2680'),
    );
    await _openMenu(tester);
    expect(find.text('Read original book'), findsOneWidget);
    await _end(tester);
  });

  testWidgets('study-guide banner names the author and the original', (
    tester,
  ) async {
    await _pump(
      tester,
      _Repository(readingUrl: 'https://www.gutenberg.org/ebooks/2680'),
    );
    expect(
      find.text(
        'Study guide written for CMPYS. Not A. Author’s full text. '
        'The original is available from the menu.',
      ),
      findsOneWidget,
    );
    await _end(tester);

    await _pump(tester, _Repository());
    expect(
      find.text('Study guide written for CMPYS. Not A. Author’s full text.'),
      findsOneWidget,
    );
    await _end(tester);

    await _pump(tester, _Repository(kind: 'public_domain_book'));
    expect(find.textContaining('Study guide written for CMPYS'), findsNothing);
    await _end(tester);
  });

  testWidgets('shared reading setting changes the reader theme', (
    tester,
  ) async {
    final container = await _pump(tester, _Repository());
    Color background() => tester
        .widget<Scaffold>(
          find
              .descendant(
                of: find.byType(BookReaderScreen),
                matching: find.byType(Scaffold),
              )
              .first,
        )
        .backgroundColor!;
    expect(background(), ReaderTheme.light.bg);

    await tester.tap(find.bySemanticsLabel('Reading settings'));
    await tester.pumpAndSettle();
    expect(find.text('Sepia'), findsOneWidget);
    await tester.tap(find.text('Dark'));
    await tester.pumpAndSettle();
    expect(container.read(cmpysStoreProvider).settings.readTheme, 'dark');
    expect(background(), ReaderTheme.dark.bg);

    // The same store value drives the reader (shared with the tutorial).
    container.read(cmpysStoreProvider.notifier).setReadTheme('sepia');
    await tester.pumpAndSettle();
    expect(background(), ReaderTheme.sepia.bg);
    await _end(tester);
  });

  testWidgets('chapter end offers Next: Chapter n', (tester) async {
    await _pump(tester, _Repository());
    expect(find.text('CHAPTER 1'), findsOneWidget);
    expect(find.text('Chapter 1 of 3'), findsOneWidget);
    final next = find.text('Next: Chapter 2');
    await tester.ensureVisible(next);
    await tester.pumpAndSettle();
    await tester.tap(next);
    await tester.pumpAndSettle();
    expect(find.text('CHAPTER 2'), findsOneWidget);
    expect(find.text('Chapter 2 of 3'), findsOneWidget);
    await _end(tester);
  });

  testWidgets('narrated paragraph saves plain text, not HTML entities', (
    tester,
  ) async {
    // The dock's waves loop while narration plays; hold them still so the
    // test can settle.
    tester.platformDispatcher.accessibilityFeaturesTestValue =
        const FakeAccessibilityFeatures(disableAnimations: true);
    addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
    const quote = 'It\'s "go" time & we leave together.';
    final repository = _Repository(
      markdown: '## Leaving\n\n$quote\n\nAnother passage follows here.',
    );
    await _pump(tester, repository);
    await tester.tap(find.byKey(const Key('book-listen-button')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('book-narration-player')), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('book-paragraph-0-0')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Highlight'));
    await tester.pumpAndSettle();
    expect(repository.created.single.quoteText, quote);
    // The saved quote matches the narrated paragraph it came from.
    expect(_wash(tester, 'book-paragraph-0-0'), AppColors.goldSoft);
    await _end(tester);
  });

  testWidgets('popover stays on screen for a tall paragraph past its top', (
    tester,
  ) async {
    final tall = List.filled(260, 'steady').join(' ');
    await _pump(
      tester,
      _Repository(markdown: '## Long\n\nIntro line.\n\nTall $tall.\n\nAfter.'),
    );
    await tester.dragFrom(const Offset(195, 600), const Offset(0, -500));
    await tester.pumpAndSettle();
    final paragraph = find.byKey(const ValueKey('book-paragraph-0-1'));
    expect(tester.getRect(paragraph).top, lessThan(0));

    await tester.tapAt(const Offset(195, 420));
    await tester.pumpAndSettle();
    final actions = tester.getRect(
      find.byKey(const ValueKey('book-paragraph-actions')),
    );
    expect(actions.top, greaterThanOrEqualTo(0));
    expect(actions.bottom, lessThanOrEqualTo(844));
    // Flipped below the tap point, since the paragraph's top is off-screen.
    expect(actions.top, greaterThan(420));
    expect(find.text('Quote'), findsOneWidget);
    await _end(tester);
  });

  testWidgets('popover fits a 320 pt phone at large text', (tester) async {
    await _pump(tester, _Repository());
    tester.view.physicalSize = const Size(320, 568);
    tester.platformDispatcher.textScaleFactorTestValue = 2;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    await tester.pumpAndSettle();
    // Bring the first paragraph up under the chrome, then tap into it.
    final first = find.byKey(const ValueKey('book-paragraph-0-0'));
    for (var i = 0; i < 8 && tester.getRect(first).top > 150; i++) {
      final step = math.min(tester.getRect(first).top - 150, 350.0);
      await tester.dragFrom(const Offset(160, 450), Offset(0, -step));
      await tester.pumpAndSettle();
    }
    await tester.tapAt(Offset(160, tester.getRect(first).top + 60));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    final actions = tester.getRect(
      find.byKey(const ValueKey('book-paragraph-actions')),
    );
    expect(actions.left, greaterThanOrEqualTo(0));
    expect(actions.right, lessThanOrEqualTo(320));
    for (final label in ['Highlight', 'Note', 'Quote']) {
      final target = tester.getSize(
        find
            .ancestor(
              of: find.text(label),
              matching: find.byType(ConstrainedBox),
            )
            .first,
      );
      expect(target.height, greaterThanOrEqualTo(44), reason: label);
    }
    await _end(tester);
  });

  testWidgets('highlight and note mark the paragraph', (tester) async {
    await _pump(tester, _Repository());
    expect(_wash(tester, 'book-paragraph-0-0'), isNot(AppColors.goldSoft));
    expect(find.byKey(BookReaderScreen.noteGlyphKey), findsNothing);

    await tester.tap(_paragraph('A useful decision starts'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Highlight'));
    await tester.pumpAndSettle();
    expect(_wash(tester, 'book-paragraph-0-0'), AppColors.goldSoft);
    expect(find.byKey(BookReaderScreen.noteGlyphKey), findsNothing);

    await tester.tap(_paragraph('Paragraph 1 keeps'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Note'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'Worth a reread.');
    await tester.pump();
    await tester.tap(find.text('Save note'));
    await tester.pumpAndSettle();
    expect(_wash(tester, 'book-paragraph-0-1'), AppColors.goldSoft);
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('book-paragraph-0-1')),
        matching: find.byKey(BookReaderScreen.noteGlyphKey),
      ),
      findsOneWidget,
    );
    await _end(tester);
  });

  testWidgets('paragraph actions close on scroll and on an outside tap', (
    tester,
  ) async {
    await _pump(tester, _Repository());
    await tester.tap(_paragraph('Paragraph 1 keeps'));
    await tester.pumpAndSettle();
    expect(find.text('Quote'), findsOneWidget);
    // The chapter title is not a paragraph: tapping it is an outside tap.
    await tester.tap(find.text('Decision Systems').last);
    await tester.pumpAndSettle();
    expect(find.text('Quote'), findsNothing);

    await tester.tap(_paragraph('Paragraph 1 keeps'));
    await tester.pumpAndSettle();
    expect(find.text('Quote'), findsOneWidget);
    await tester.dragFrom(const Offset(195, 600), const Offset(0, -120));
    await tester.pumpAndSettle();
    expect(find.text('Quote'), findsNothing);

    // A second tap on the same paragraph closes it too.
    await tester.tap(_paragraph('Paragraph 1 keeps'));
    await tester.pumpAndSettle();
    expect(find.text('Quote'), findsOneWidget);
    await tester.tap(_paragraph('Paragraph 1 keeps'));
    await tester.pumpAndSettle();
    expect(find.text('Quote'), findsNothing);
    await _end(tester);
  });

  testWidgets('Notes & highlights deletes an entry', (tester) async {
    final repository = _Repository(
      initial: [_highlight('h-1', _firstParagraph)],
    );
    await _pump(tester, repository);
    expect(_wash(tester, 'book-paragraph-0-0'), AppColors.goldSoft);
    await _openMenu(tester);
    await tester.tap(find.text('Notes & highlights · 1'));
    await tester.pumpAndSettle();
    expect(find.text('Highlight · Ch. 1'), findsOneWidget);
    await tester.tap(find.bySemanticsLabel('Delete highlight'));
    await tester.pumpAndSettle();
    expect(repository.deleted, ['h-1']);
    expect(find.text('Highlight · Ch. 1'), findsNothing);
    expect(
      find.text(
        'Tap any paragraph to highlight it or add a note. They’re saved to '
        'this book.',
      ),
      findsOneWidget,
    );
    Navigator.of(tester.element(find.text('Notes & highlights'))).pop();
    await tester.pumpAndSettle();
    expect(_wash(tester, 'book-paragraph-0-0'), isNot(AppColors.goldSoft));
    await _end(tester);
  });

  testWidgets('Read original book opens the original in the web viewer', (
    tester,
  ) async {
    final opened = _Opened();
    await _pump(
      tester,
      _Repository(readingUrl: 'https://www.gutenberg.org/ebooks/2680'),
      observer: opened,
    );
    await _openMenu(tester);
    await tester.tap(find.text('Read original book'));
    await tester.pumpAndSettle();
    expect(opened.screens, hasLength(1));
    final screen = opened.screens.single as MaterialWebScreen;
    expect(screen.url, 'https://www.gutenberg.org/ebooks/2680');
    expect(screen.title, 'Decision Systems');
    expect(screen.access, AccessType.original);
    await _end(tester);
  });

  testWidgets('Open source on the error state opens the source as a web page', (
    tester,
  ) async {
    final opened = _Opened();
    await _pump(
      tester,
      _Repository(failLoad: true),
      observer: opened,
      fallbackSourceUrl: 'https://example.org/decision-systems',
    );
    await tester.tap(find.text('Open source'));
    await tester.pumpAndSettle();
    final screen = opened.screens.single as MaterialWebScreen;
    expect(screen.url, 'https://example.org/decision-systems');
    expect(screen.access, AccessType.web);
    await _end(tester);
  });
}
