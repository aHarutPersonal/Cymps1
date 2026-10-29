import 'dart:async';
import 'package:cmpys/core/ui/motion/page_transition.dart';

import 'package:cmpys/app/design_tokens.dart';
import 'package:cmpys/core/network/dio_client.dart';
import 'package:cmpys/core/storage/token_store.dart';
import 'package:cmpys/core/ui/v3/v3.dart';
import 'package:cmpys/features/plan/presentation/book_narration.dart';
import 'package:cmpys/features/plan/presentation/book_narration_checkpoint.dart';
import 'package:cmpys/features/plan/presentation/book_narration_dock.dart';
import 'package:cmpys/features/plan/presentation/book_reader_screen.dart';
import 'package:cmpys/features/plan/presentation/reading_library_screen.dart';
import 'package:cmpys/features/plan/state/book_narration_remote_controller.dart';
import 'package:cmpys/features/session/data/content_resources_repository.dart';
import 'package:cmpys/features/session/models/content_resource.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:just_audio/just_audio.dart';

import 'support/fake_book_audio_player.dart';

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

class _TrackContentResourcesRepository extends _FakeContentResourcesRepository {
  int preparations = 0;
  bool audioOnly = false;
  bool singleChapter = false;
  bool failPreparation = false;
  Completer<BookNarrationAudio>? pendingPreparation;

  @override
  Future<ContentResource> getResource(String resourceId) async => singleChapter
      ? ContentResource(
          id: resource.id,
          kind: resource.kind,
          canonicalKey: resource.canonicalKey,
          title: resource.title,
          licenseStatus: resource.licenseStatus,
          isSaved: true,
          progressPercent: 0,
          contentMarkdown:
              '## Decisions\n\n${List.generate(8, (index) => 'Passage $index describes a useful decision.').join('\n\n')}',
        )
      : resource;

  @override
  Future<BookNarrationAudio> prepareNarration(
    String resourceId, {
    required String text,
    required String style,
    String? narratorProfile,
  }) async {
    preparations++;
    if (failPreparation) throw StateError('Preparation failed');
    if (pendingPreparation case final pending?) return pending.future;
    final timed = !audioOnly && preparations == 1;
    return BookNarrationAudio(
      audioUri: Uri.parse('https://audio.example.test/$preparations.wav'),
      style: style,
      voice: 'expressive',
      provider: 'gemini',
      duration: const Duration(seconds: 20),
      alignment: timed
          ? const [
              BookNarrationCue(
                start: 0,
                end: 1,
                startTime: Duration.zero,
                endTime: Duration(seconds: 1),
              ),
            ]
          : const [],
      alignmentGranularity: timed
          ? BookNarrationAlignmentGranularity.word
          : BookNarrationAlignmentGranularity.none,
      alignmentSource: timed ? 'transcription' : 'none',
      isAiGenerated: true,
    );
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
  Completer<void>? pendingWrite;

  @override
  Future<BookNarrationCheckpoint?> read(String resourceId) async =>
      values[resourceId];

  @override
  Future<void> write(
    String resourceId,
    BookNarrationCheckpoint checkpoint,
  ) async {
    await pendingWrite?.future;
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

/// The narration dock's waves loop while playing; a test that settles while
/// narration plays holds them still with reduced motion.
void _holdWavesStill(WidgetTester tester) {
  tester.platformDispatcher.accessibilityFeaturesTestValue =
      const FakeAccessibilityFeatures(disableAnimations: true);
  addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
}

/// Stops narration the v3 way: the dock opens the full player, whose Stop
/// closes it and ends the session.
Future<void> _stopFromPlayer(WidgetTester tester) async {
  final dock = tester.getRect(find.byKey(const Key('book-narration-player')));
  await tester.tapAt(Offset(dock.left + 30, dock.center.dy));
  await tester.pumpAndSettle();
  await tester.ensureVisible(find.text('Stop'));
  await tester.pumpAndSettle();
  await tester.tap(find.text('Stop'));
  await tester.pumpAndSettle();
}

/// Opens the full player from the dock.
Future<void> _openPlayer(WidgetTester tester) async {
  final dock = tester.getRect(find.byKey(const Key('book-narration-player')));
  await tester.tapAt(Offset(dock.left + 30, dock.center.dy));
  await tester.pumpAndSettle();
}

bool _containsLiveWordHighlight(InlineSpan span) {
  if (span.style?.backgroundColor == AppColors.green) return true;
  if (span is TextSpan) {
    return span.children?.any(_containsLiveWordHighlight) ?? false;
  }
  return false;
}

bool _containsNarrationHighlight(InlineSpan span) {
  if (span.style?.backgroundColor == AppColors.green ||
      span.style?.backgroundColor == AppColors.greenSoft) {
    return true;
  }
  return span is TextSpan &&
      (span.children?.any(_containsNarrationHighlight) ?? false);
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  Future<
    ({FakeBookAudioPlayer player, _TrackContentResourcesRepository repository})
  >
  mountProductionTrack(
    WidgetTester tester, {
    bool audioOnly = false,
    bool singleChapter = false,
    BookNarrationCheckpointStore? checkpointStore,
    Completer<BookNarrationAudio>? initialPreparation,
    _TrackContentResourcesRepository? repository,
  }) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    _holdWavesStill(tester);
    final player = FakeBookAudioPlayer();
    final trackRepository = (repository ?? _TrackContentResourcesRepository())
      ..audioOnly = audioOnly
      ..singleChapter = singleChapter
      ..pendingPreparation = initialPreparation;
    final narrator = ExpressiveBookNarrator(
      repository: trackRepository,
      resourceId: 'book-1',
      audioPlayer: player,
      configureAudioSession: () async {},
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          contentResourcesRepositoryProvider.overrideWithValue(
            trackRepository,
          ),
        ],
        child: MaterialApp(
          home: BookReaderScreen(
            resourceId: 'book-1',
            fallbackTitle: 'Decision Systems',
            narrator: narrator,
            checkpointStore: checkpointStore,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('book-listen-button')));
    if (initialPreparation == null) {
      await tester.pumpAndSettle();
    } else {
      await tester.pump();
    }
    return (player: player, repository: trackRepository);
  }

  String narrationSemantics(WidgetTester tester) =>
      tester
          .widget<Semantics>(
            find.byWidgetPredicate(
              (widget) =>
                  widget is Semantics &&
                  widget.properties.label == 'Audiobook controls',
            ),
          )
          .properties
          .value ??
      '';

  testWidgets(
    'transcription gaps clear both the word and sentence background',
    (tester) async {
      final setup = await mountProductionTrack(tester);
      final highlights = find.byWidgetPredicate(
        (widget) =>
            widget is RichText && _containsNarrationHighlight(widget.text),
      );
      expect(highlights, findsWidgets);
      await setup.player.seek(const Duration(milliseconds: 1200));
      await tester.pump();
      expect(highlights, findsNothing);
      await setup.player.seek(const Duration(milliseconds: 300));
      await tester.pump();
      expect(highlights, findsWidgets);
      await tester.tap(find.byKey(const Key('book-narration-play-pause')));
      await tester.pumpAndSettle();
      expect(highlights, findsNothing);
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
    },
  );

  testWidgets(
    'narration marker follows audio approximately without word timing',
    (tester) async {
      await mountProductionTrack(tester, audioOnly: true);
      const caption =
          'Position follows audio approximately. This voice doesn’t provide '
          'word timing.';
      final marker = find.byKey(const ValueKey('book-narration-marker'));
      expect(marker, findsOneWidget);
      expect(find.text(caption), findsOneWidget);
      // The marker sits on the paragraph the narration position maps to.
      expect(
        find.ancestor(
          of: marker,
          matching: find.byKey(const ValueKey('book-paragraph-0-0')),
        ),
        findsOneWidget,
      );
      // Listening hides the Listen button.
      expect(find.byKey(const Key('book-listen-button')), findsNothing);
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
    },
  );

  testWidgets('word-timed narration keeps the marker without the caption', (
    tester,
  ) async {
    await mountProductionTrack(tester);
    expect(narrationSemantics(tester), contains('Word synchronized.'));
    expect(
      find.byKey(const ValueKey('book-narration-marker')),
      findsOneWidget,
    );
    expect(
      find.textContaining('Position follows audio approximately'),
      findsNothing,
    );
    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
  });

  testWidgets('reopening narration does not flash the approximate caption', (
    tester,
  ) async {
    final setup = await mountProductionTrack(tester);
    expect(narrationSemantics(tester), contains('Word synchronized.'));
    await _stopFromPlayer(tester);
    expect(find.byKey(const Key('book-narration-player')), findsNothing);

    final pending = Completer<BookNarrationAudio>();
    setup.repository.pendingPreparation = pending;
    await tester.tap(find.byKey(const Key('book-listen-button')));
    await tester.pump();
    const caption = 'Position follows audio approximately';
    expect(find.byKey(const Key('book-narration-player')), findsOneWidget);
    expect(find.textContaining(caption), findsNothing);
    await tester.pump(const Duration(milliseconds: 200));
    expect(find.textContaining(caption), findsNothing);
    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
  });

  testWidgets(
    'changing chapter during preparation starts the selected chapter',
    (tester) async {
      final pending = Completer<BookNarrationAudio>();
      final setup = await mountProductionTrack(
        tester,
        initialPreparation: pending,
      );
      expect(narrationSemantics(tester), contains('Preparing narration.'));
      setup.repository.pendingPreparation = null;
      tester.widget<PageView>(find.byType(PageView)).controller!.jumpToPage(1);
      await tester.pump();
      await tester.runAsync(() => Future<void>.delayed(Duration.zero));
      await tester.pumpAndSettle();
      expect(setup.player.playing, isTrue);
      expect(
        narrationSemantics(tester),
        isNot(contains('Preparing narration.')),
      );
      final loads = setup.player.loads;
      pending.complete(
        BookNarrationAudio(
          audioUri: Uri.parse('https://audio.example.test/obsolete.wav'),
          style: 'expressive',
          voice: 'voice',
          duration: const Duration(seconds: 20),
          alignment: const [],
          isAiGenerated: true,
        ),
      );
      await tester.pumpAndSettle();
      expect(setup.player.loads, loads);
      expect(setup.player.playing, isTrue);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
    },
  );

  testWidgets(
    'native playback failure exits buffering and Play reloads the expressive track',
    (tester) async {
      final setup = await mountProductionTrack(tester);
      expect(find.bySemanticsLabel('Pause'), findsOneWidget);
      final prepared = setup.repository.preparations;
      setup.player.emitState(ProcessingState.buffering);
      await tester.pump();
      expect(narrationSemantics(tester), contains('Preparing narration.'));
      setup.player.errors.add(
        PlayerException(-11800, 'Native stream failed', 0),
      );
      await tester.pump();
      expect(
        find.text('Narration audio couldn’t be loaded. Try again.'),
        findsOneWidget,
      );
      expect(find.bySemanticsLabel('Play'), findsOneWidget);
      expect(
        narrationSemantics(tester),
        isNot(contains('Preparing narration.')),
      );
      await tester.tap(find.byKey(const Key('book-narration-play-pause')));
      // Broadcast-stream cancellation completes outside the widget fake clock.
      await tester.runAsync(() => Future<void>.delayed(Duration.zero));
      await tester.pumpAndSettle();
      expect(find.bySemanticsLabel('Pause'), findsOneWidget);
      expect(setup.player.loads, 2);
      expect(setup.repository.preparations, prepared);
      expect(find.textContaining('device voice'), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
    },
  );

  testWidgets(
    'audio-only next clip clears the previous synchronized timing claim',
    (tester) async {
      final setup = await mountProductionTrack(tester);
      expect(narrationSemantics(tester), contains('Word synchronized.'));
      expect(setup.player.sources.length, greaterThan(1));
      await setup.player.seek(Duration.zero, index: 1);
      await tester.pump();
      expect(narrationSemantics(tester), isNot(contains('Word synchronized.')));
      expect(
        narrationSemantics(tester),
        contains('Text highlighting unavailable.'),
      );
      expect(find.bySemanticsLabel('Pause'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
    },
  );

  testWidgets('Gemini audio-only WAV plays without guessing text highlights', (
    tester,
  ) async {
    final setup = await mountProductionTrack(tester, audioOnly: true);
    expect(find.bySemanticsLabel('Pause'), findsOneWidget);
    expect(
      narrationSemantics(tester),
      contains('Text highlighting unavailable.'),
    );
    expect(narrationSemantics(tester), isNot(contains('synchronized')));
    await setup.player.seek(const Duration(seconds: 5));
    await tester.pump();
    expect(
      find.byWidgetPredicate(
        (widget) =>
            widget is RichText && _containsNarrationHighlight(widget.text),
      ),
      findsNothing,
    );
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
  });

  testWidgets(
    'pause keeps the current sentence, progress and durable resume offset',
    (tester) async {
      final checkpoints = _MemoryBookNarrationCheckpointStore();
      final setup = await mountProductionTrack(
        tester,
        audioOnly: true,
        checkpointStore: checkpoints,
      );
      final remote = ProviderScope.containerOf(
        tester.element(find.byType(BookReaderScreen)),
      ).read(bookNarrationRemoteControllerProvider);
      setup.player.repeatedIndexOnPause = 0;
      await setup.player.seek(const Duration(seconds: 15));
      await tester.pump();
      final progress = remote.progress;
      expect(progress, greaterThan(0));
      expect(
        narrationSemantics(tester),
        contains('Speed belongs to the first category'),
      );

      await tester.tap(find.byKey(const Key('book-narration-play-pause')));
      await tester.pumpAndSettle();
      expect(find.bySemanticsLabel('Play'), findsOneWidget);
      expect(
        narrationSemantics(tester),
        contains('Speed belongs to the first category'),
      );
      expect(remote.progress, progress);
      final saved = checkpoints.values['book-1']!;
      expect(saved.segmentIndex, 1);
      expect(saved.characterOffset, greaterThan(0));
      expect(
        setup.repository.lastCursorJson?['narrationSegment'],
        saved.segmentIndex,
      );
      expect(
        setup.repository.lastCursorJson?['narrationCharacterOffset'],
        saved.characterOffset,
      );

      await tester.tap(find.byKey(const Key('book-narration-play-pause')));
      await tester.pumpAndSettle();
      expect(find.bySemanticsLabel('Pause'), findsOneWidget);
      expect(remote.progress, progress);
      expect(setup.player.position, const Duration(seconds: 15));
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
    },
  );

  testWidgets(
    'an unprepared far seek reports failure and keeps manual retry available',
    (tester) async {
      final setup = await mountProductionTrack(tester, audioOnly: true);
      final remote = ProviderScope.containerOf(
        tester.element(find.byType(BookReaderScreen)),
      ).read(bookNarrationRemoteControllerProvider);
      setup.repository.failPreparation = true;
      await tester.runAsync(() => remote.seek(1));
      await tester.pumpAndSettle();
      expect(
        find.text('Couldn’t move the narration. Try again.'),
        findsOneWidget,
      );
      expect(find.bySemanticsLabel('Play'), findsOneWidget);
      expect(tester.takeException(), isNull);

      setup.repository.failPreparation = false;
      await tester.tap(find.byKey(const Key('book-narration-play-pause')));
      await tester.runAsync(() => Future<void>.delayed(Duration.zero));
      await tester.pumpAndSettle();
      expect(find.bySemanticsLabel('Pause'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
    },
  );

  testWidgets(
    'pausing a pending far seek prevents late audio from restarting',
    (tester) async {
      final setup = await mountProductionTrack(tester, audioOnly: true);
      final remote = ProviderScope.containerOf(
        tester.element(find.byType(BookReaderScreen)),
      ).read(bookNarrationRemoteControllerProvider);
      final pending = Completer<BookNarrationAudio>();
      setup.repository.pendingPreparation = pending;
      final plays = setup.player.plays;
      var seekFinished = false;
      unawaited(remote.seek(1).then((_) => seekFinished = true));
      await tester.runAsync(() => Future<void>.delayed(Duration.zero));
      await tester.pump();
      expect(remote.preparing, isTrue);
      unawaited(remote.toggle());
      await tester.pump();
      await tester.runAsync(() => Future<void>.delayed(Duration.zero));
      await tester.pump();
      pending.complete(
        BookNarrationAudio(
          audioUri: Uri.parse('https://audio.example.test/late.wav'),
          style: 'expressive',
          voice: 'Sulafat',
          provider: 'gemini',
          duration: const Duration(seconds: 20),
          alignment: const [],
          isAiGenerated: true,
        ),
      );
      await tester.pump();
      await tester.runAsync(() => Future<void>.delayed(Duration.zero));
      await tester.pumpAndSettle();
      expect(seekFinished, isTrue);
      expect(setup.player.plays, plays);
      expect(setup.player.playing, isFalse);
      expect(find.bySemanticsLabel('Play'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
    },
  );

  testWidgets('an obsolete far-seek failure cannot interrupt a newer track', (
    tester,
  ) async {
    final setup = await mountProductionTrack(
      tester,
      audioOnly: true,
      singleChapter: true,
    );
    final remote = ProviderScope.containerOf(
      tester.element(find.byType(BookReaderScreen)),
    ).read(bookNarrationRemoteControllerProvider);
    final pending = Completer<BookNarrationAudio>();
    setup.repository.pendingPreparation = pending;
    var firstSeekFinished = false;
    unawaited(remote.seek(1).then((_) => firstSeekFinished = true));
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    await tester.pump();
    expect(remote.preparing, isTrue);

    setup.repository.pendingPreparation = null;
    unawaited(remote.seek(0));
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    await tester.pumpAndSettle();
    expect(find.bySemanticsLabel('Pause'), findsOneWidget);

    pending.completeError(StateError('Obsolete preparation failed'));
    await tester.pump();
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    await tester.pumpAndSettle();
    expect(firstSeekFinished, isTrue);
    expect(setup.player.playing, isTrue);
    expect(find.bySemanticsLabel('Pause'), findsOneWidget);
    expect(find.text('Couldn’t move the narration. Try again.'), findsNothing);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
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

    expect(find.text('CHAPTER 1'), findsOneWidget);
    expect(find.text('Chapter 1 of 3'), findsOneWidget);
    expect(find.text('Decision Systems'), findsWidgets);
    expect(find.byType(SelectionArea), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.tap(find.bySemanticsLabel('Reading settings'));
    await tester.pumpAndSettle();
    expect(find.text('Reading settings'), findsOneWidget);
    expect(find.text('Sepia'), findsOneWidget);
    expect(tester.takeException(), isNull);
    Navigator.of(tester.element(find.text('Sepia'))).pop();
    await tester.pumpAndSettle();

    await tester.tap(find.bySemanticsLabel('Book menu'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Contents'));
    await tester.pumpAndSettle();
    expect(find.text('Contents'), findsOneWidget);
    expect(find.text('Attention Loops'), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.tap(find.text('Attention Loops'));
    await tester.pumpAndSettle();
    expect(find.text('CHAPTER 2'), findsOneWidget);
    final next = find.byKey(const ValueKey('book-chapter-next-1'));
    await tester.ensureVisible(next);
    await tester.pumpAndSettle();
    expect(find.text('Next: Chapter 3'), findsOneWidget);
    await tester.tap(next);
    await tester.pumpAndSettle();
    expect(find.text('CHAPTER 3'), findsOneWidget);
    expect(find.text('Finish book'), findsOneWidget);
    await tester.tap(find.bySemanticsLabel('Book menu'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Notes & highlights · 0'));
    await tester.pumpAndSettle();
    expect(find.text('Notes & highlights'), findsOneWidget);
    expect(
      find.text(
        'Tap any paragraph to highlight it or add a note. They’re saved to '
        'this book.',
      ),
      findsOneWidget,
    );
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

    expect(find.text('CHAPTER 1'), findsOneWidget);
    expect(find.text('GLOBAL SHELL NAV'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('listen follows narration with sentence and word highlighting', (
    tester,
  ) async {
    _holdWavesStill(tester);
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
    expect(find.bySemanticsLabel('Play'), findsOneWidget);

    // Speed and style live in the full player (1× → 1.25× → 1.5×).
    await _openPlayer(tester);
    final speed = find.byKey(const Key('book-narration-speed'));
    await tester.ensureVisible(speed);
    await tester.pumpAndSettle();
    await tester.tap(speed);
    await tester.pumpAndSettle();
    await tester.tap(speed);
    await tester.pumpAndSettle();
    expect(narrator.speeds.last, 1.5);
    expect(find.descendant(of: speed, matching: find.text('1.5×')), findsOne);

    await tester.tap(find.bySemanticsLabel('More'));
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

    // Forward 15 s moves the narration on to a later sentence.
    await tester.tap(find.bySemanticsLabel('Forward 15 seconds'));
    await tester.pumpAndSettle();
    await tester.tap(find.bySemanticsLabel('Back'));
    await tester.pumpAndSettle();
    final controls = tester.widget<Semantics>(
      find.byWidgetPredicate(
        (widget) =>
            widget is Semantics &&
            widget.properties.label == 'Audiobook controls',
      ),
    );
    expect(controls.properties.value, isNot(contains(firstSentence)));
    expect(controls.properties.value, contains('Current passage:'));
    expect(tester.takeException(), isNull);
  });

  testWidgets('narration keeps playing while another tab is selected', (
    tester,
  ) async {
    _holdWavesStill(tester);
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
    _holdWavesStill(tester);
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
    _holdWavesStill(tester);
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
    expect(find.bySemanticsLabel('Pause'), findsOneWidget);
    expect(resumedNarrator.stopCalls, 0);
    const firstSentence =
        'A useful decision starts by separating a reversible choice from an irreversible one.';
    expect(resumedNarrator.spokenTexts, [firstSentence.substring(7)]);

    await _stopFromPlayer(tester);
    expect(activeResumes.values['local'], isNull);
    expect(resumedNarrator.stopCalls, greaterThanOrEqualTo(1));
    expect(tester.takeException(), isNull);
  });

  testWidgets('continuous word progress reaches durable storage periodically', (
    tester,
  ) async {
    _holdWavesStill(tester);
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
    _holdWavesStill(tester);
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
      // The real sheet path on a small phone with the keyboard up.
      tester.view.physicalSize = const Size(320, 568);
      tester.view.devicePixelRatio = 1;
      tester.view.viewInsets = const FakeViewPadding(bottom: 260);
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetViewInsets);

      ContentHighlight? returnedNote;
      String? submittedText;
      var saveCalls = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => FilledButton(
                onPressed: () async {
                  returnedNote = await showV3Sheet<ContentHighlight>(
                    context,
                    title: 'Add a note',
                    builder: (sheetContext) => BookNoteComposerSheet(
                      quote: 'A reversible choice rewards speed.',
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
                child: const Text('Open composer'),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Open composer'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.text('Add a note'), findsOneWidget);
      // The note field takes focus as the sheet opens.
      expect(
        tester.widget<EditableText>(find.byType(EditableText)).focusNode.hasFocus,
        isTrue,
      );
      await tester.enterText(
        find.byType(TextField),
        'Compare reversibility first.',
      );
      // "Save note" enables once the note has text (v3 design).
      await tester.pump();
      await tester.ensureVisible(find.text('Save note'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Save note'));
      await tester.pump();
      // The field locks while the note saves.
      expect(tester.widget<TextField>(find.byType(TextField)).enabled, isFalse);
      await tester.pumpAndSettle();

      expect(saveCalls, 1);
      expect(submittedText, 'Compare reversibility first.');
      expect(returnedNote?.id, 'note-1');
      expect(find.text('Open composer'), findsOneWidget);
      expect(find.text('Add a note'), findsNothing);
      expect(tester.takeException(), isNull);

      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    },
  );
  for (final overlap in [false, true]) {
    testWidgets(
      'reader swipe saves position and stops audio; pending button=$overlap',
      (tester) async {
    _holdWavesStill(tester);
        tester.view.physicalSize = const Size(390, 844);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final repository = _FakeContentResourcesRepository();
        final narrator = _FakeBookNarrator();
        final checkpoints = _MemoryBookNarrationCheckpointStore();
        final resumes = _MemoryActiveBookNarrationResumeStore();
        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              contentResourcesRepositoryProvider.overrideWithValue(repository),
            ],
            child: MaterialApp(
              theme: ThemeData(platform: TargetPlatform.iOS),
              home: Scaffold(
                body: Builder(
                  builder: (context) => TextButton(
                    onPressed: () => Navigator.of(context).push(
                      CmpysPageRoute<void>(
                        builder: (context) => Scaffold(
                          body: TextButton(
                            child: const Text('Open book'),
                            onPressed: () => Navigator.of(context).push(
                              CmpysPageRoute<void>(
                                builder: (_) => BookReaderScreen(
                                  resourceId: 'book-1',
                                  fallbackTitle: 'Decision Systems',
                                  narrator: narrator,
                                  checkpointStore: checkpoints,
                                  activeResumeStore: resumes,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                    child: const Text('Open library'),
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.tap(find.text('Open library'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Open book'));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('book-listen-button')));
        await tester.pumpAndSettle();
        narrator.emitProgress(start: 7, end: 13, word: 'decision');
        await tester.pump();

        // Cancelling the edge gesture must not stop playback or clear its resume.
        final gesture = await tester.startGesture(const Offset(1, 150));
        await gesture.moveBy(const Offset(60, 0));
        await tester.pump(const Duration(milliseconds: 400));
        await gesture.up();
        await tester.pumpAndSettle();
        expect(narrator.stopCalls, 0);
        expect(find.byType(BookReaderScreen), findsOneWidget);

        if (overlap) {
          checkpoints.pendingWrite = Completer<void>();
          await tester.tap(find.bySemanticsLabel('Back'));
          await tester.pump();
        }
        await tester.dragFrom(const Offset(1, 150), const Offset(340, 0));
        await tester.pumpAndSettle();
        checkpoints.pendingWrite?.complete();
        await tester.pumpAndSettle();
        expect(find.text('Open book'), findsOneWidget);
        expect(find.text('Open library'), findsNothing);
        expect(narrator.stopCalls, greaterThan(0));
        expect(checkpoints.values['book-1']?.characterOffset, 7);
        expect(repository.lastCursorJson?['narrationCharacterOffset'], 7);
        expect(resumes.values['local'], isNull);
        expect(tester.takeException(), isNull);
      },
    );
  }

  group('E3 narration follow-ups', () {
    Future<
      ({ProviderContainer container, _FakeBookNarrator narrator})
    >
    mountReader(
      WidgetTester tester, {
      ContentResourcesRepository? repository,
      BookNarrationCheckpointStore? checkpointStore,
      bool startNarrationOnOpen = false,
      bool autoplayOnRestore = false,
    }) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      _holdWavesStill(tester);
      final narrator = _FakeBookNarrator();
      final container = ProviderContainer(
        overrides: [
          contentResourcesRepositoryProvider.overrideWithValue(
            repository ?? _FakeContentResourcesRepository(),
          ),
        ],
      );
      addTearDown(container.dispose);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            home: BookReaderScreen(
              resourceId: 'book-1',
              fallbackTitle: 'Fallback',
              narrator: narrator,
              checkpointStore:
                  checkpointStore ?? _MemoryBookNarrationCheckpointStore(),
              activeResumeStore: _MemoryActiveBookNarrationResumeStore(),
              startNarrationOnOpen: startNarrationOnOpen,
              autoplayOnRestore: autoplayOnRestore,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      return (container: container, narrator: narrator);
    }

    testWidgets('Listen on a never-narrated book starts narration', (
      tester,
    ) async {
      final setup = await mountReader(tester, startNarrationOnOpen: true);
      const firstSentence =
          'A useful decision starts by separating a reversible choice from '
          'an irreversible one.';
      expect(setup.narrator.spokenTexts, [firstSentence]);
      final remote = setup.container.read(
        bookNarrationRemoteControllerProvider,
      );
      expect(remote.active, isTrue);
      expect(remote.playing, isTrue);
      // The dock and the full player know which book is playing.
      expect(remote.resourceId, 'book-1');
      expect(remote.title, 'Decision Systems');
      expect(remote.author, 'A. Author');
      expect(remote.chapterIndex, 0);
      expect(remote.chapterTitle, 'Decision Systems');
      expect(remote.duration, greaterThan(Duration.zero));
      expect(find.byKey(const Key('book-narration-player')), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
    });

    testWidgets('the cold-start restore alone still needs a checkpoint', (
      tester,
    ) async {
      final setup = await mountReader(tester, autoplayOnRestore: true);
      expect(setup.narrator.spokenTexts, isEmpty);
      expect(find.byKey(const Key('book-listen-button')), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
    });

    testWidgets('the approximate caption stays while the stream buffers', (
      tester,
    ) async {
      final setup = await mountProductionTrack(tester, audioOnly: true);
      const caption = 'Position follows audio approximately';
      expect(find.textContaining(caption), findsOneWidget);
      setup.player.emitState(ProcessingState.buffering);
      await tester.pump();
      expect(narrationSemantics(tester), contains('Preparing narration.'));
      expect(find.textContaining(caption), findsOneWidget);
      setup.player.emitState(ProcessingState.ready);
      await tester.pump();
      expect(find.textContaining(caption), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
    });

    testWidgets('the narrated view and both voices get plain quotes and '
        'ampersands, with the highlight aligned', (tester) async {
      final setup = await mountReader(
        tester,
        repository: _EntityContentResourcesRepository(),
      );
      await tester.tap(find.byKey(const Key('book-listen-button')));
      await tester.pumpAndSettle();
      // v4 parses without HTML escaping: the voice is sent plain text.
      const sentence = 'He said "hi" & left.';
      expect(setup.narrator.spokenTexts, [sentence]);
      expect(setup.narrator.spokenTexts.single, isNot(contains('&quot;')));

      RichText paragraph() => tester.widget<RichText>(
        find.byWidgetPredicate(
          (widget) =>
              widget is RichText &&
              widget.text.toPlainText().startsWith('He said'),
        ),
      );
      String highlighted() {
        final words = <String>[];
        paragraph().text.visitChildren((span) {
          if (span is TextSpan &&
              span.style?.backgroundColor == AppColors.ember) {
            words.add(span.text ?? '');
          }
          return true;
        });
        return words.join();
      }

      expect(
        paragraph().text.toPlainText(),
        'He said "hi" & left. Then more & more.',
      );
      setup.narrator.emitProgress(start: 8, end: 12, word: '"hi"');
      await tester.pump();
      expect(highlighted(), '"hi"');
      setup.narrator.emitProgress(start: 13, end: 14, word: '&');
      await tester.pump();
      expect(highlighted(), '&');
      // The dock's spoken summary carries no entities either.
      final controls = tester.widget<Semantics>(
        find.byWidgetPredicate(
          (widget) =>
              widget is Semantics &&
              widget.properties.label == 'Audiobook controls',
        ),
      );
      expect(controls.properties.value, contains(sentence));
      expect(controls.properties.value, isNot(contains('&amp;')));
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
    });

    testWidgets('the expressive voice is sent chunks without entities', (
      tester,
    ) async {
      final setup = await mountProductionTrack(
        tester,
        repository: _EntityTrackContentResourcesRepository(),
      );
      final texts = (setup.repository as _EntityTrackContentResourcesRepository)
          .texts;
      expect(texts, isNotEmpty);
      expect(texts.first, startsWith('He said "hi" & left.'));
      for (final text in texts) {
        expect(text, isNot(contains(RegExp('&(quot|amp|lt|gt|#39);'))));
      }
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
    });

    testWidgets('track voice: ±15 s and seek land mid-sentence, and a skip '
        'into the next chapter keeps its offset', (tester) async {
      final setup = await mountProductionTrack(
        tester,
        audioOnly: true,
        repository: _LongTrackContentResourcesRepository(),
      );
      final remote = ProviderScope.containerOf(
        tester.element(find.byType(BookReaderScreen)),
      ).read(bookNarrationRemoteControllerProvider);
      expect(remote.chapterIndex, 0);
      expect(setup.player.playing, isTrue);
      // Two chapters of one long sentence each: 300 + 450 characters.
      expect(remote.duration, const Duration(milliseconds: 50000));
      final start = remote.elapsed;

      // About 15 s each way: the voice's own position estimate can move the
      // marker by a character or two (~0.1 s) after the seek.
      await _openPlayer(tester);
      await tester.tap(find.bySemanticsLabel('Forward 15 seconds'));
      await tester.pumpAndSettle();
      expect(remote.chapterIndex, 0);
      expect(
        (remote.elapsed - start).inMilliseconds,
        inInclusiveRange(14000, 16000),
      );
      // Inside the sentence's clip (20 s), not at its start or end.
      expect(setup.player.position, greaterThan(const Duration(seconds: 10)));
      expect(setup.player.position, lessThan(const Duration(seconds: 19)));

      // The next 15 s crosses into chapter 2, mid-sentence there. The
      // position holds while the native seek is still in flight (no
      // position from the player yet).
      final beforeCrossing = remote.elapsed;
      final seekGate = Completer<void>();
      setup.player.nextSeekGate = seekGate;
      await tester.tap(find.bySemanticsLabel('Forward 15 seconds'));
      await tester.pump();
      await tester.pump();
      expect(remote.chapterIndex, 1);
      expect(
        (remote.elapsed - beforeCrossing).inMilliseconds,
        inInclusiveRange(14000, 16000),
      );
      seekGate.complete();
      await tester.pumpAndSettle();
      expect(remote.chapterIndex, 1);
      expect(
        (remote.elapsed - beforeCrossing).inMilliseconds,
        inInclusiveRange(14000, 16000),
      );
      expect(setup.player.position, greaterThan(const Duration(seconds: 3)));
      expect(setup.player.position, lessThan(const Duration(seconds: 19)));

      // Back 15 s returns across the boundary.
      final beforeBack = remote.elapsed;
      await tester.tap(find.bySemanticsLabel('Back 15 seconds'));
      await tester.pumpAndSettle();
      expect(remote.chapterIndex, 0);
      expect(
        (beforeBack - remote.elapsed).inMilliseconds,
        inInclusiveRange(14000, 16000),
      );

      // The seek bar lands mid-sentence on the same timeline.
      final bar = tester.getRect(find.byKey(BookNarrationFullPlayer.seekKey));
      await tester.tapAt(Offset(bar.left + bar.width * .8, bar.center.dy));
      await tester.pumpAndSettle();
      expect(remote.chapterIndex, 1);
      expect(
        (remote.elapsed - remote.duration * .8).inMilliseconds.abs(),
        lessThan(1000),
      );
      expect(setup.player.position, greaterThan(const Duration(seconds: 10)));
      expect(setup.player.position, lessThan(const Duration(seconds: 19)));
      expect(setup.player.playing, isTrue);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
    });

    testWidgets('±15 s from sentence 8 of 10 moves one 15 s span each way', (
      tester,
    ) async {
      final checkpoints = _MemoryBookNarrationCheckpointStore();
      checkpoints.values['book-1'] = const BookNarrationCheckpoint(
        chapterIndex: 0,
        segmentIndex: 7,
        characterOffset: 0,
        updatedAtEpochMs: 1,
        textVersion: 4,
      );
      final setup = await mountReader(
        tester,
        repository: _TenSentenceContentResourcesRepository(),
        checkpointStore: checkpoints,
        startNarrationOnOpen: true,
      );
      final remote = setup.container.read(
        bookNarrationRemoteControllerProvider,
      );
      expect(setup.narrator.spokenTexts.last, startsWith('Line 7 '));
      final start = remote.elapsed;
      // 10 sentences of ~98 characters at 15 a second: ~65 s in all.
      expect(remote.duration.inSeconds, inInclusiveRange(60, 70));

      await _openPlayer(tester);
      await tester.tap(find.bySemanticsLabel('Forward 15 seconds'));
      await tester.pumpAndSettle();
      final forward = remote.elapsed - start;
      // Lands on the word there: a few characters short of 15 s at most.
      expect(forward.inMilliseconds, inInclusiveRange(14400, 15000));
      expect(setup.narrator.spokenTexts.last, startsWith('abc'));
      expect(remote.playing, isTrue);

      final afterForward = remote.elapsed;
      await tester.tap(find.bySemanticsLabel('Back 15 seconds'));
      await tester.pumpAndSettle();
      final back = afterForward - remote.elapsed;
      expect(back.inMilliseconds, inInclusiveRange(15000, 15600));

      // At the very start, Back does nothing more than clamp.
      await tester.tap(find.bySemanticsLabel('Back 15 seconds'));
      await tester.pumpAndSettle();
      await tester.tap(find.bySemanticsLabel('Back 15 seconds'));
      await tester.pumpAndSettle();
      await tester.tap(find.bySemanticsLabel('Back 15 seconds'));
      await tester.pumpAndSettle();
      await tester.tap(find.bySemanticsLabel('Back 15 seconds'));
      await tester.pumpAndSettle();
      expect(remote.elapsed, Duration.zero);
      expect(setup.narrator.spokenTexts.last, startsWith('Line 0 '));

      // The seek bar uses the same timeline: 50 % is half the book's time.
      final bar = tester.getRect(find.byKey(BookNarrationFullPlayer.seekKey));
      await tester.tapAt(Offset(bar.left + bar.width / 2, bar.center.dy));
      await tester.pumpAndSettle();
      expect(
        (remote.elapsed - remote.duration * .5).inMilliseconds.abs(),
        lessThan(600),
      );
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
    });
  });
}

/// Two chapters, each one long sentence (300 and 450 characters), so 15 s
/// (225 characters) lands inside a sentence.
class _LongTrackContentResourcesRepository
    extends _TrackContentResourcesRepository {
  static String sentence(String first, int length) {
    final words = StringBuffer(first);
    while (words.length < length - 4) {
      words.write(' abc');
    }
    while (words.length < length - 1) {
      words.write('x');
    }
    return '$words.';
  }

  @override
  Future<ContentResource> getResource(String resourceId) async =>
      ContentResource(
        id: 'book-1',
        kind: 'llm_book_summary',
        canonicalKey: 'book:long',
        title: 'Long',
        licenseStatus: 'llm_summary',
        isSaved: false,
        progressPercent: 0,
        contentMarkdown:
            '## One\n\n${sentence('Alpha', 300)}\n\n'
            '## Two\n\n${sentence('Beta', 450)}\n',
      );
}

class _TenSentenceContentResourcesRepository
    extends _FakeContentResourcesRepository {
  static String sentence(int index) {
    final words = StringBuffer('Line $index');
    while (words.length < 96) {
      words.write(' abc');
    }
    return '$words.';
  }

  @override
  Future<ContentResource> getResource(String resourceId) async =>
      ContentResource(
        id: 'book-1',
        kind: 'llm_book_summary',
        canonicalKey: 'book:ten',
        title: 'Ten',
        licenseStatus: 'llm_summary',
        isSaved: false,
        progressPercent: 0,
        contentMarkdown:
            '## Ten\n\n${List.generate(10, sentence).join('\n\n')}\n',
      );
}

class _EntityTrackContentResourcesRepository
    extends _TrackContentResourcesRepository {
  final List<String> texts = [];

  @override
  Future<ContentResource> getResource(String resourceId) async =>
      const ContentResource(
        id: 'book-1',
        kind: 'llm_book_summary',
        canonicalKey: 'book:entities',
        title: 'Entities',
        licenseStatus: 'llm_summary',
        isSaved: false,
        progressPercent: 0,
        contentMarkdown:
            '## Quotes\n\nHe said "hi" & left. Then more & more.\n\n'
            '## Next\n\nA <b>bold</b> "move" & a 5 > 3 claim.\n',
      );

  @override
  Future<BookNarrationAudio> prepareNarration(
    String resourceId, {
    required String text,
    required String style,
    String? narratorProfile,
  }) {
    texts.add(text);
    return super.prepareNarration(
      resourceId,
      text: text,
      style: style,
      narratorProfile: narratorProfile,
    );
  }
}

class _EntityContentResourcesRepository
    extends _FakeContentResourcesRepository {
  @override
  Future<ContentResource> getResource(String resourceId) async =>
      const ContentResource(
        id: 'book-1',
        kind: 'llm_book_summary',
        canonicalKey: 'book:entities',
        title: 'Entities',
        licenseStatus: 'llm_summary',
        isSaved: false,
        progressPercent: 0,
        contentMarkdown: '## Quotes\n\nHe said "hi" & left. Then more & more.\n',
      );
}
