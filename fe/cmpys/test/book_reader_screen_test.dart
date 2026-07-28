import 'dart:async';

import 'package:cmpys/app/design_tokens.dart';
import 'package:cmpys/core/network/dio_client.dart';
import 'package:cmpys/core/storage/token_store.dart';
import 'package:cmpys/features/plan/presentation/book_narration.dart';
import 'package:cmpys/features/plan/presentation/book_narration_checkpoint.dart';
import 'package:cmpys/features/plan/presentation/book_reader_screen.dart';
import 'package:cmpys/features/plan/presentation/reading_library_screen.dart';
import 'package:cmpys/features/session/data/content_resources_repository.dart';
import 'package:cmpys/features/session/models/content_resource.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _FakeContentResourcesRepository extends ContentResourcesRepository {
  _FakeContentResourcesRepository()
    : super(dioClient: DioClient(tokenStore: TokenStore()));

  final resource = const ContentResource(
    id: 'book-1',
    kind: 'llm_book_summary',
    canonicalKey: 'book:author:decision_systems',
    title: 'Decision Systems',
    authorOrCreator: 'A. Author',
    licenseStatus: 'llm_summary',
    contentMarkdown: '''
## Decision Systems

A useful decision starts by separating a reversible choice from an irreversible one. **Speed belongs to the first category; care belongs to the second.**

### Practice This
1. Label one decision as reversible or irreversible.
2. Write the smallest useful next step.

## Attention Loops

Attention improves when unfinished work has an explicit return point. Record the next action before changing contexts.

### Practice This
1. Close one loop before opening another.
2. Record what changed.

## Closing Synthesis

Combine the decision label and return point in one daily review.
''',
    durationMinutes: 18,
    isSaved: true,
    progressPercent: 0,
  );
  Map<String, dynamic>? lastCursorJson;
  @override
  Future<ContentResource> getResource(String resourceId) async => resource;

  @override
  Future<List<ContentHighlight>> listHighlights(String resourceId) async =>
      const [];

  @override
  Future<List<ContentResource>> listLibraryResources({
    String? kind,
    String? query,
    String? sort,
    int limit = 50,
    int offset = 0,
  }) async => [resource];

  @override
  Future<ContentResource?> getContinueReading() async => null;

  @override
  Future<ContentResource> updateProgress(
    String resourceId, {
    required int progressPercent,
    Map<String, dynamic>? cursorJson,
    bool? completed,
  }) async {
    lastCursorJson = cursorJson;
    return resource;
  }
}

class _FakeBookNarrator implements BookNarrator, BookNarrationStyleController {
  BookNarrationProgressHandler? progressHandler;
  BookNarrationErrorHandler? errorHandler;
  BookNarrationVoiceHandler? voiceHandler;
  final List<String> spokenTexts = [];
  final List<double> speeds = [];
  final List<BookNarrationStyle> styles = [];
  Completer<void>? _speech;
  int stopCalls = 0;

  @override
  BookNarrationStyle style = BookNarrationStyle.expressive;

  @override
  BookNarrationVoiceKind voiceKind = BookNarrationVoiceKind.expressiveAi;

  @override
  void setProgressHandler(BookNarrationProgressHandler? handler) {
    progressHandler = handler;
  }

  @override
  void setErrorHandler(BookNarrationErrorHandler? handler) {
    errorHandler = handler;
  }

  @override
  void setVoiceHandler(BookNarrationVoiceHandler? handler) {
    voiceHandler = handler;
  }

  @override
  Future<void> setStyle(BookNarrationStyle style) async {
    this.style = style;
    styles.add(style);
  }

  @override
  Future<void> initialize({required double speed}) async {
    speeds.add(speed);
  }

  @override
  Future<void> setSpeed(double speed) async {
    speeds.add(speed);
  }

  @override
  Future<void> speak(String text) {
    spokenTexts.add(text);
    _speech = Completer<void>();
    return _speech!.future;
  }

  void emitProgress({
    required int start,
    required int end,
    required String word,
  }) {
    progressHandler?.call(start, end, word);
  }

  @override
  Future<void> stop() async {
    stopCalls++;
    if (_speech case final speech? when !speech.isCompleted) {
      speech.complete();
    }
  }

  @override
  Future<void> dispose() => stop();
}

class _MemoryBookNarrationCheckpointStore
    implements BookNarrationCheckpointStore {
  final Map<String, BookNarrationCheckpoint> values = {};
  int writeCount = 0;

  @override
  Future<BookNarrationCheckpoint?> read(String resourceId) async =>
      values[resourceId];

  @override
  Future<void> write(
    String resourceId,
    BookNarrationCheckpoint checkpoint,
  ) async {
    writeCount++;
    values[resourceId] = checkpoint;
  }

  @override
  Future<void> clear(String resourceId) async {
    values.remove(resourceId);
  }
}

class _MemoryActiveBookNarrationResumeStore
    implements ActiveBookNarrationResumeStore {
  final Map<String, ActiveBookNarrationResume> values = {};
  int writeCount = 0;
  int clearCount = 0;

  @override
  Future<ActiveBookNarrationResume?> read(String ownerId) async =>
      values[ownerId];

  @override
  Future<void> write(ActiveBookNarrationResume value) async {
    writeCount++;
    values[value.ownerId] = value;
  }

  @override
  Future<void> clear(String ownerId) async {
    clearCount++;
    values.remove(ownerId);
  }
}

class _TabContinuityHarness extends StatefulWidget {
  const _TabContinuityHarness({required this.reader});

  final Widget reader;

  @override
  State<_TabContinuityHarness> createState() => _TabContinuityHarnessState();
}

class _TabContinuityHarnessState extends State<_TabContinuityHarness> {
  int _index = 0;

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        IndexedStack(
          index: _index,
          children: [
            widget.reader,
            const ColoredBox(color: AppColors.paper),
          ],
        ),
        Positioned(
          right: 8,
          top: 48,
          child: Material(
            color: Colors.transparent,
            child: IconButton.filled(
              key: const Key('switch-test-tab'),
              onPressed: () => setState(() => _index = _index == 0 ? 1 : 0),
              icon: const Icon(Icons.swap_horiz_rounded),
            ),
          ),
        ),
      ],
    );
  }
}

bool _containsLiveWordHighlight(InlineSpan span) {
  if (span.style?.backgroundColor == AppColors.green) return true;
  if (span is TextSpan) {
    return span.children?.any(_containsLiveWordHighlight) ?? false;
  }
  return false;
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('reader exposes chapters, notes, and typography controls', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final repository = _FakeContentResourcesRepository();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          contentResourcesRepositoryProvider.overrideWithValue(repository),
        ],
        child: const MaterialApp(
          home: BookReaderScreen(
            resourceId: 'book-1',
            fallbackTitle: 'Fallback',
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('CHAPTER 01 OF 03'), findsOneWidget);
    expect(find.text('Decision Systems'), findsWidgets);
    expect(find.byType(SelectionArea), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.tap(find.byIcon(Icons.format_size_rounded));
    await tester.pumpAndSettle();
    expect(find.text('Reading settings'), findsOneWidget);
    expect(find.text('Warm'), findsOneWidget);
    expect(tester.takeException(), isNull);
    Navigator.of(tester.element(find.text('Reading settings'))).pop();
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.format_list_bulleted_rounded));
    await tester.pumpAndSettle();
    expect(find.text('Contents'), findsOneWidget);
    expect(find.text('Attention Loops'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('opening a book keeps the shell navigation available', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final repository = _FakeContentResourcesRepository();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          contentResourcesRepositoryProvider.overrideWithValue(repository),
        ],
        child: MaterialApp(
          home: Stack(
            children: [
              Positioned.fill(
                child: Navigator(
                  onGenerateRoute: (_) => MaterialPageRoute<void>(
                    builder: (_) => const ReadingLibraryScreen(),
                  ),
                ),
              ),
              const Align(
                alignment: Alignment.bottomCenter,
                child: Material(child: Text('GLOBAL SHELL NAV')),
              ),
            ],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('GLOBAL SHELL NAV'), findsOneWidget);
    await tester.tap(find.text('A. Author'));
    await tester.pumpAndSettle();

    expect(find.text('CHAPTER 01 OF 03'), findsOneWidget);
    expect(find.text('GLOBAL SHELL NAV'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('listen follows narration with sentence and word highlighting', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final repository = _FakeContentResourcesRepository();
    final narrator = _FakeBookNarrator();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          contentResourcesRepositoryProvider.overrideWithValue(repository),
        ],
        child: MaterialApp(
          home: BookReaderScreen(
            resourceId: 'book-1',
            fallbackTitle: 'Fallback',
            narrator: narrator,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('book-listen-button')), findsOneWidget);
    await tester.tap(find.byKey(const Key('book-listen-button')));
    await tester.pumpAndSettle();

    const firstSentence =
        'A useful decision starts by separating a reversible choice from an irreversible one.';
    final player = find.byKey(const Key('book-narration-player'));
    expect(player, findsOneWidget);
    expect(narrator.spokenTexts, [firstSentence]);
    expect(
      find.byWidgetPredicate(
        (widget) =>
            widget is Semantics &&
            widget.properties.label == 'Audiobook controls' &&
            (widget.properties.value ?? '').contains(firstSentence),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(of: player, matching: find.byType(Text)),
      findsNothing,
    );

    narrator.emitProgress(start: 2, end: 8, word: 'useful');
    await tester.pump();
    expect(
      find.byWidgetPredicate(
        (widget) =>
            widget is RichText && _containsLiveWordHighlight(widget.text),
      ),
      findsOneWidget,
    );

    await tester.tap(find.byKey(const Key('book-narration-play-pause')));
    await tester.pumpAndSettle();
    expect(narrator.stopCalls, greaterThanOrEqualTo(1));
    expect(find.byIcon(Icons.play_arrow_rounded), findsOneWidget);

    await tester.tap(find.byKey(const Key('book-narration-speed')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('1.5×').last);
    await tester.pumpAndSettle();
    expect(narrator.speeds.last, 1.5);
    expect(
      find.descendant(of: player, matching: find.byType(Text)),
      findsNothing,
    );

    await tester.tap(find.byKey(const Key('book-narration-style')));
    await tester.pumpAndSettle();
    expect(
      find.text('Dynamic pacing and emotion that follow the meaning.'),
      findsOneWidget,
    );
    await tester.tap(find.text('Warm'));
    await tester.pumpAndSettle();
    expect(narrator.styles.last, BookNarrationStyle.warm);
    expect(repository.lastCursorJson?['narrationStyle'], 'warm');
    expect(repository.lastCursorJson?['narrationSpeed'], 1.5);

    await tester.tap(find.byKey(const Key('book-narration-next')));
    await tester.pumpAndSettle();
    expect(
      find.byWidgetPredicate(
        (widget) =>
            widget is Semantics &&
            widget.properties.label == 'Audiobook controls' &&
            (widget.properties.value ?? '').contains(
              'Speed belongs to the first category; care belongs to the second.',
            ),
      ),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('narration keeps playing while another tab is selected', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final repository = _FakeContentResourcesRepository();
    final narrator = _FakeBookNarrator();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          contentResourcesRepositoryProvider.overrideWithValue(repository),
        ],
        child: MaterialApp(
          home: _TabContinuityHarness(
            reader: BookReaderScreen(
              resourceId: 'book-1',
              fallbackTitle: 'Fallback',
              narrator: narrator,
              checkpointStore: _MemoryBookNarrationCheckpointStore(),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('book-listen-button')));
    await tester.pumpAndSettle();
    expect(narrator.spokenTexts, isNotEmpty);
    expect(narrator.stopCalls, 0);

    await tester.tap(find.byKey(const Key('switch-test-tab')));
    await tester.pumpAndSettle();
    expect(narrator.stopCalls, 0);

    narrator.emitProgress(start: 2, end: 8, word: 'useful');
    await tester.pump();
    await tester.tap(find.byKey(const Key('switch-test-tab')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('book-narration-player')), findsOneWidget);
    expect(narrator.stopCalls, 0);
    expect(tester.takeException(), isNull);
  });

  testWidgets('paused narration resumes from its persisted character offset', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final repository = _FakeContentResourcesRepository();
    final checkpoints = _MemoryBookNarrationCheckpointStore();
    final firstNarrator = _FakeBookNarrator();

    Widget reader(BookNarrator narrator) => ProviderScope(
      overrides: [
        contentResourcesRepositoryProvider.overrideWithValue(repository),
      ],
      child: MaterialApp(
        home: BookReaderScreen(
          resourceId: 'book-1',
          fallbackTitle: 'Fallback',
          narrator: narrator,
          checkpointStore: checkpoints,
        ),
      ),
    );

    await tester.pumpWidget(reader(firstNarrator));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('book-listen-button')));
    await tester.pumpAndSettle();

    firstNarrator.emitProgress(start: 2, end: 8, word: 'useful');
    await tester.pump();
    await tester.tap(find.byKey(const Key('book-narration-play-pause')));
    await tester.pumpAndSettle();

    final saved = checkpoints.values['book-1'];
    expect(saved?.chapterIndex, 0);
    expect(saved?.segmentIndex, 0);
    expect(saved?.characterOffset, 2);
    expect(repository.lastCursorJson?['narrationChapter'], 0);
    expect(repository.lastCursorJson?['narrationSegment'], 0);
    expect(repository.lastCursorJson?['narrationCharacterOffset'], 2);

    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();

    final resumedNarrator = _FakeBookNarrator();
    await tester.pumpWidget(reader(resumedNarrator));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('book-narration-player')), findsOneWidget);

    await tester.tap(find.byKey(const Key('book-narration-play-pause')));
    await tester.pumpAndSettle();
    const firstSentence =
        'A useful decision starts by separating a reversible choice from an irreversible one.';
    expect(resumedNarrator.spokenTexts, [firstSentence.substring(2)]);
    expect(tester.takeException(), isNull);
  });

  testWidgets('cold start reopens active narration and autoplays exact offset', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final repository = _FakeContentResourcesRepository();
    final checkpoints = _MemoryBookNarrationCheckpointStore();
    final activeResumes = _MemoryActiveBookNarrationResumeStore();
    final firstNarrator = _FakeBookNarrator();

    Widget reader(BookNarrator narrator, {bool autoplayOnRestore = false}) =>
        ProviderScope(
          overrides: [
            contentResourcesRepositoryProvider.overrideWithValue(repository),
          ],
          child: MaterialApp(
            home: BookReaderScreen(
              resourceId: 'book-1',
              fallbackTitle: 'Fallback',
              narrator: narrator,
              checkpointStore: checkpoints,
              activeResumeStore: activeResumes,
              autoplayOnRestore: autoplayOnRestore,
            ),
          ),
        );

    await tester.pumpWidget(reader(firstNarrator));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('book-listen-button')));
    await tester.pumpAndSettle();
    firstNarrator.emitProgress(start: 7, end: 13, word: 'decision');
    await tester.pump();

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await tester.pumpAndSettle();
    expect(checkpoints.values['book-1']?.characterOffset, 7);
    expect(activeResumes.values['local']?.wasPlaying, isTrue);
    expect(activeResumes.values['local']?.checkpoint.characterOffset, 7);

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
    activeResumes.values['local'] = activeResumes.values['local']!.copyWith(
      wasPlaying: false,
    );

    final resumedNarrator = _FakeBookNarrator();
    await tester.pumpWidget(reader(resumedNarrator, autoplayOnRestore: true));
    await tester.pumpAndSettle();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 1));

    expect(find.byKey(const Key('book-narration-player')), findsOneWidget);
    expect(find.byTooltip('Pause narration'), findsOneWidget);
    expect(resumedNarrator.stopCalls, 0);
    const firstSentence =
        'A useful decision starts by separating a reversible choice from an irreversible one.';
    expect(resumedNarrator.spokenTexts, [firstSentence.substring(7)]);

    await tester.tap(find.byKey(const Key('book-narration-options')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Stop listening'));
    await tester.pumpAndSettle();
    expect(activeResumes.values['local'], isNull);
    expect(resumedNarrator.stopCalls, greaterThanOrEqualTo(1));
    expect(tester.takeException(), isNull);
  });

  testWidgets('continuous word progress reaches durable storage periodically', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final repository = _FakeContentResourcesRepository();
    final narrator = _FakeBookNarrator();
    final checkpoints = _MemoryBookNarrationCheckpointStore();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          contentResourcesRepositoryProvider.overrideWithValue(repository),
        ],
        child: MaterialApp(
          home: BookReaderScreen(
            resourceId: 'book-1',
            fallbackTitle: 'Fallback',
            narrator: narrator,
            checkpointStore: checkpoints,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('book-listen-button')));
    await tester.pumpAndSettle();

    for (var offset = 1; offset <= 10; offset++) {
      narrator.emitProgress(start: offset, end: offset + 1, word: 'x');
      await tester.pump(const Duration(milliseconds: 100));
    }

    expect(checkpoints.writeCount, greaterThanOrEqualTo(1));
    expect(
      checkpoints.values['book-1']?.characterOffset,
      greaterThanOrEqualTo(5),
    );

    await tester.pump(const Duration(milliseconds: 250));
    expect(checkpoints.writeCount, greaterThanOrEqualTo(2));
    expect(checkpoints.values['book-1']?.characterOffset, 10);
    expect(tester.takeException(), isNull);
  });

  testWidgets('listening controls fit a narrow phone with larger text', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 568);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final repository = _FakeContentResourcesRepository();
    final narrator = _FakeBookNarrator();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          contentResourcesRepositoryProvider.overrideWithValue(repository),
        ],
        child: MaterialApp(
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: const TextScaler.linear(1.35)),
            child: child!,
          ),
          home: BookReaderScreen(
            resourceId: 'book-1',
            fallbackTitle: 'Fallback',
            narrator: narrator,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('book-listen-button')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('book-narration-player')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'saving a book note closes without lifecycle or overflow errors',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      ContentHighlight? returnedNote;
      String? submittedText;
      var saveCalls = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => FilledButton(
                onPressed: () async {
                  returnedNote = await showModalBottomSheet<ContentHighlight>(
                    context: context,
                    isScrollControlled: true,
                    builder: (sheetContext) {
                      final media = MediaQuery.of(sheetContext);
                      return MediaQuery(
                        data: media.copyWith(
                          viewInsets: const EdgeInsets.only(bottom: 300),
                        ),
                        child: BookNoteComposerSheet(
                          quote: 'A reversible choice rewards speed.',
                          background: Colors.white,
                          chrome: Colors.white,
                          ink: Colors.black,
                          muted: Colors.grey,
                          dark: false,
                          onSave: (noteText) async {
                            saveCalls++;
                            submittedText = noteText;
                            await Future<void>.delayed(
                              const Duration(milliseconds: 10),
                            );
                            final now = DateTime.utc(2026, 7, 14);
                            return ContentHighlight(
                              id: 'note-1',
                              contentResourceId: 'book-1',
                              quoteText: 'A reversible choice rewards speed.',
                              noteText: noteText,
                              createdAt: now,
                              updatedAt: now,
                            );
                          },
                        ),
                      );
                    },
                  );
                },
                child: const Text('Open composer'),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Open composer'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byType(TextField),
        'Compare reversibility first.',
      );
      await tester.tap(find.text('Save note'));
      await tester.pumpAndSettle();

      expect(saveCalls, 1);
      expect(submittedText, 'Compare reversibility first.');
      expect(returnedNote?.id, 'note-1');
      expect(find.text('Open composer'), findsOneWidget);
      expect(tester.takeException(), isNull);

      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    },
  );
}
