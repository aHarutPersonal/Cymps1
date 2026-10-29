import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:markdown/markdown.dart' as md;

import '../../../app/design_tokens.dart';
import '../../../core/network/api_error.dart';
import '../../../core/ui/motion/motion_config.dart';
import '../../../core/ui/motion/page_transition.dart';
import '../../../core/ui/app_shell.dart';
import '../../../core/ui/cmpys/cmpys_markdown.dart';
import '../../../core/ui/cmpys/learning_comparison_view.dart';
import '../../../core/ui/cmpys/learning_diagram_view.dart';
import '../../../core/ui/v3/v3.dart';
import '../../auth/controllers/session_controller.dart';
import '../../cmpys/state/cmpys_store.dart';
import '../../cmpys/state/reader_settings.dart';
import '../../session/data/content_resources_repository.dart';
import '../../session/models/content_resource.dart';
import '../models/plan_models.dart';
import '../state/book_narration_remote_controller.dart';
import 'book_narration.dart';
import 'book_narration_checkpoint.dart';
import 'book_narration_dock.dart';
import 'material_web_screen.dart';
import 'reader_settings_sheet.dart';
import '../../../core/ui/narration_dock_page.dart';

/// Full-screen, chaptered reading experience for shared book resources.
///
/// The reader intentionally owns progress, table-of-contents navigation,
/// typography controls, bookmarks, text selection, highlights, and notes. It
/// remains separate from plan-item details so the same book can be resumed
/// from the reading library later.
class BookReaderScreen extends ConsumerStatefulWidget {
  const BookReaderScreen({
    super.key,
    required this.resourceId,
    required this.fallbackTitle,
    this.fallbackSourceUrl,
    this.narrator,
    this.checkpointStore,
    this.activeResumeStore,
    this.autoplayOnRestore = false,
    this.startNarrationOnOpen = false,
    this.shellBranchIndex = 1,
  });

  /// Key on the top chrome's slide, which hides on scroll-down (tests).
  @visibleForTesting
  static const chromeKey = ValueKey('book-reader-chrome');

  /// Key on the Listen button's slide, which hides with the chrome (tests).
  @visibleForTesting
  static const listenKey = ValueKey('book-reader-listen');

  /// Key on a paragraph's note glyph (tests).
  @visibleForTesting
  static const noteGlyphKey = ValueKey('book-paragraph-note');

  final String resourceId;
  final String fallbackTitle;
  final String? fallbackSourceUrl;
  final BookNarrator? narrator;
  final BookNarrationCheckpointStore? checkpointStore;
  final ActiveBookNarrationResumeStore? activeResumeStore;

  /// One-shot intent supplied only by the authenticated cold-start route.
  final bool autoplayOnRestore;

  /// One-shot intent from a "Listen" button (library, Today): start narration
  /// once the book loads, from its saved position or, for a book never
  /// narrated, from the start of the current chapter.
  final bool startNarrationOnOpen;

  /// Stateful-shell branch that owns this reader (Plan by default).
  final int shellBranchIndex;

  @override
  ConsumerState<BookReaderScreen> createState() => _BookReaderScreenState();
}

class _BookReaderScreenState extends ConsumerState<BookReaderScreen>
    with WidgetsBindingObserver {
  PageController _pageController = PageController();
  late final BookNarrator _narrator;
  late final BookNarrationCheckpointStore _checkpointStore;
  late final ActiveBookNarrationResumeStore _activeResumeStore;
  late final String _resumeOwnerId;
  late final String _checkpointStorageId;
  ContentResource? _resource;
  List<BookChapter> _chapters = const [];
  List<BookNarrationDocument> _narrationDocuments = const [];
  List<ContentHighlight> _notes = const [];
  int _chapterIndex = 0;
  String? _selectedQuote;
  int? _selectedParagraph;
  _PopoverAnchor? _popoverAnchor;
  bool _marking = false;
  final _chromeVisible = ValueNotifier<bool>(true);
  double _lastScrollY = 0;
  bool _userScroll = false;
  final _popover = OverlayPortalController();
  final Object _popoverGroup = Object();
  final Map<int, List<BookReaderParagraph>> _markdownParagraphs = {};
  final _narrationParagraphs = Expando<List<BookReaderParagraph>>(
    'narration paragraphs',
  );
  List<ContentHighlight>? _marksNotes;
  final Map<List<BookReaderParagraph>, List<_ParagraphMark?>> _marksCache =
      Map.identity();
  bool _loading = true;
  bool _savingBook = false;
  String? _error;

  bool _narrationVisible = false;
  bool _narrationPlaying = false;
  bool _narrationPreparing = false;
  bool _narrationFinished = false;
  bool _narratorReady = false;
  bool _narrationTrackReady = false;
  bool _narrationChangingChapter = false;
  bool _deviceFallbackAnnounced = false;
  int _narrationRun = 0;
  int? _narrationTrackSessionId;
  int? _narrationSegmentIndex;
  int _narrationWordStart = 0;
  int _narrationWordEnd = 0;
  int _narrationResumeOffset = 0;
  int _speechBaseOffset = 0;
  double _narrationSpeed = 1;
  BookNarrationStyle _narrationStyle = BookNarrationStyle.expressive;
  BookNarrationVoiceKind _narrationVoice = BookNarrationVoiceKind.expressiveAi;
  BookNarrationAlignmentGranularity _narrationAlignmentGranularity =
      BookNarrationAlignmentGranularity.none;
  String _narrationProvider = '';
  String _narrationModel = '';
  String _narrationVoiceLabel = 'Expressive narrator';
  String _narrationDisclosure = 'AI-generated voice · not the real person';
  String _activeIdolName = '';
  final Map<String, GlobalKey> _narrationBlockKeys = {};
  Timer? _narrationCheckpointTimer;
  BookNarrationCheckpoint? _lastNarrationCheckpoint;
  Future<void> _checkpointWrite = Future<void>.value();
  Future<void> _progressWrite = Future<void>.value();
  final Object _remoteDockOwner = Object();
  bool _remoteDockAttached = false;
  late final BookNarrationRemoteController _remoteDockController;
  bool _autoplayOnRestoreConsumed = false;
  bool _startOnOpenConsumed = false;
  Duration _narrationListenDuration = Duration.zero;

  /// Narration characters in each chapter. Characters are the one timeline
  /// the player's clock, progress, seek and ±15 s share (15 a second at 1×).
  List<int> _narrationChapterCharacters = const [];
  bool _leavingReader = false;
  bool _readerPopped = false;

  ContentResourcesRepository get _repository =>
      ref.read(contentResourcesRepositoryProvider);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _checkpointStore =
        widget.checkpointStore ??
        const SharedPreferencesBookNarrationCheckpointStore();
    final authenticatedOwnerId = ref.read(currentUserProvider)?.id.trim() ?? '';
    _resumeOwnerId = authenticatedOwnerId.isEmpty
        ? 'local'
        : authenticatedOwnerId;
    _checkpointStorageId = authenticatedOwnerId.isEmpty
        ? widget.resourceId
        : '$authenticatedOwnerId::${widget.resourceId}';
    _activeResumeStore =
        widget.activeResumeStore ??
        const SharedPreferencesActiveBookNarrationResumeStore();
    _remoteDockController = ref.read(bookNarrationRemoteControllerProvider);
    final idol = ref.read(cmpysStoreProvider).idol;
    _activeIdolName = idol.id == 'mentor-placeholder' ? '' : idol.name.trim();
    final narratorProfile =
        idol.id == 'buffett' ||
            idol.name.trim().toLowerCase() == 'warren buffett'
        ? 'seasoned_mentor'
        : 'expressive_narrator';
    if (narratorProfile == 'seasoned_mentor') {
      _narrationVoiceLabel = 'Seasoned mentor';
    }
    _narrationDisclosure = _activeIdolName.isEmpty
        ? 'AI-generated voice · not the real person'
        : 'AI voice · not $_activeIdolName';
    _narrator =
        widget.narrator ??
        AdaptiveBookNarrator(
          expressive: ExpressiveBookNarrator(
            repository: _repository,
            resourceId: widget.resourceId,
            narratorProfile: narratorProfile,
          ),
          device: SystemBookNarrator(),
        );
    _narrator.setProgressHandler(_onNarrationProgress);
    _narrator.setErrorHandler(_onNarrationError);
    if (_narrator case final BookNarrationTrackController controller) {
      controller.setTrackHandler(_onNarrationTrackEvent);
    }
    if (_narrator case final BookNarrationStyleController controller) {
      _narrationStyle = controller.style;
      _narrationVoice = controller.voiceKind;
      controller.setVoiceHandler(_onNarrationVoiceChanged);
    }
    _load();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _chromeVisible.dispose();
    if (_remoteDockAttached) {
      _remoteDockController.release(_remoteDockOwner);
      _remoteDockAttached = false;
    }
    _narrationCheckpointTimer?.cancel();
    final finalCheckpoint = _captureNarrationCheckpoint();
    if (finalCheckpoint != null) {
      unawaited(_queueNarrationCheckpointWrite(finalCheckpoint));
    }
    _narrationRun++;
    _narrator.setProgressHandler(null);
    _narrator.setErrorHandler(null);
    if (_narrator case final BookNarrationTrackController controller) {
      controller.setTrackHandler(null);
    }
    if (_narrator case final BookNarrationStyleController controller) {
      controller.setVoiceHandler(null);
    }
    unawaited(_narrator.dispose());
    _pageController.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached ||
        state == AppLifecycleState.hidden) {
      unawaited(_flushNarrationCheckpoint());
    }
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final results = await Future.wait<dynamic>([
        _repository.getResource(widget.resourceId),
        _repository
            .listHighlights(widget.resourceId)
            .catchError((_) => <ContentHighlight>[]),
        _readNarrationCheckpoint(),
        _readActiveResume(),
      ]);
      final resource = results[0] as ContentResource;
      final notes = results[1] as List<ContentHighlight>;
      final localCheckpoint = results[2] as BookNarrationCheckpoint?;
      final activeResume = results[3] as ActiveBookNarrationResume?;
      final cursor = resource.cursorJson;
      final serverCheckpoint = _checkpointFromCursor(cursor);
      final activeCheckpoint = activeResume?.resourceId == widget.resourceId
          ? activeResume?.checkpoint
          : null;
      final savedCheckpoint = _newestCheckpoint([
        localCheckpoint,
        serverCheckpoint,
        activeCheckpoint,
      ]);
      final savedStyle = BookNarrationStyle.values.where(
        (style) => style.apiName == cursor?['narrationStyle']?.toString(),
      );
      final narrationStyle = savedStyle.isEmpty
          ? _narrationStyle
          : savedStyle.first;
      final narrationSpeed = switch (cursor?['narrationSpeed']) {
        final num speed
            when const [0.75, 1.0, 1.25, 1.5, 2.0].contains(speed.toDouble()) =>
          speed.toDouble(),
        _ => _narrationSpeed,
      };
      if (_narrator case final BookNarrationStyleController controller) {
        await controller.setStyle(narrationStyle);
      }
      final markdown = resource.contentMarkdown?.trim() ?? '';
      final chapters = markdown.isEmpty
          ? <BookChapter>[]
          : splitBookChapters(resource.contentMarkdown!);
      final narrationDocuments = chapters
          .map(
            (chapter) => BookNarrationDocument.fromMarkdown(chapter.markdown),
          )
          .toList(growable: false);
      var initialChapter =
          savedCheckpoint?.chapterIndex ??
          (resource.cursorJson?['chapter'] as num?)?.toInt();
      if (initialChapter == null && chapters.isNotEmpty) {
        initialChapter = ((resource.progressPercent / 100) * chapters.length)
            .floor();
      }
      initialChapter = chapters.isEmpty
          ? 0
          : (initialChapter ?? 0).clamp(0, chapters.length - 1).toInt();
      final restoredCheckpoint = _validatedCheckpoint(
        savedCheckpoint,
        documents: narrationDocuments,
      );
      if (restoredCheckpoint != null) {
        initialChapter = restoredCheckpoint.chapterIndex;
      }

      if (!mounted) return;
      _pageController.dispose();
      _pageController = PageController(initialPage: initialChapter);
      setState(() {
        _resource = resource;
        _chapters = chapters;
        _narrationDocuments = narrationDocuments;
        _narrationListenDuration = estimateBookNarrationDuration(
          narrationDocuments,
        );
        _narrationChapterCharacters = [
          for (final document in narrationDocuments)
            document.segments.fold<int>(
              0,
              (total, segment) => total + segment.text.length,
            ),
        ];
        _narrationBlockKeys.clear();
        _markdownParagraphs.clear();
        _notes = notes;
        _chapterIndex = initialChapter!;
        _narrationStyle = narrationStyle;
        _narrationSpeed = narrationSpeed;
        _lastNarrationCheckpoint = restoredCheckpoint;
        _narrationVisible = restoredCheckpoint != null;
        _narrationSegmentIndex = restoredCheckpoint?.segmentIndex;
        _narrationResumeOffset = restoredCheckpoint?.characterOffset ?? 0;
        _loading = false;
      });
      _syncRemoteDock();
      final startOnOpen =
          widget.startNarrationOnOpen &&
          !_startOnOpenConsumed &&
          chapters.isNotEmpty;
      if (startOnOpen ||
          (widget.autoplayOnRestore &&
              restoredCheckpoint != null &&
              !_autoplayOnRestoreConsumed)) {
        _autoplayOnRestoreConsumed = true;
        _startOnOpenConsumed = true;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted && !_narrationPlaying && !_narrationPreparing) {
            unawaited(_playNarration());
          }
        });
      }
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = switch (error) {
          ApiError(statusCode: 404) =>
            'This book guide is not available for reading right now.',
          ApiError(statusCode: 401) =>
            'Please sign in again to open this book.',
          NetworkError() || TimeoutError() =>
            'Couldn’t open this book. Check your connection and try again.',
          _ => 'Couldn’t open this book right now. Please try again.',
        };
      });
    }
  }

  Future<BookNarrationCheckpoint?> _readNarrationCheckpoint() async {
    try {
      return await _checkpointStore.read(_checkpointStorageId);
    } catch (_) {
      return null;
    }
  }

  Future<ActiveBookNarrationResume?> _readActiveResume() async {
    try {
      return await _activeResumeStore.read(_resumeOwnerId);
    } catch (_) {
      return null;
    }
  }

  BookNarrationCheckpoint? _newestCheckpoint(
    Iterable<BookNarrationCheckpoint?> checkpoints,
  ) {
    BookNarrationCheckpoint? newest;
    for (final checkpoint in checkpoints) {
      if (checkpoint != null &&
          (newest == null ||
              checkpoint.updatedAtEpochMs >= newest.updatedAtEpochMs)) {
        newest = checkpoint;
      }
    }
    return newest;
  }

  BookNarrationCheckpoint? _checkpointFromCursor(Map<String, dynamic>? cursor) {
    if (cursor == null) return null;
    return BookNarrationCheckpoint.tryFromJson({
      'chapterIndex': cursor['narrationChapter'],
      'segmentIndex': cursor['narrationSegment'],
      'characterOffset': cursor['narrationCharacterOffset'],
      'updatedAtEpochMs': cursor['narrationUpdatedAtEpochMs'],
      'textVersion': cursor['narrationTextVersion'],
    });
  }

  BookNarrationCheckpoint? _validatedCheckpoint(
    BookNarrationCheckpoint? checkpoint, {
    required List<BookNarrationDocument> documents,
  }) {
    if (checkpoint == null || documents.isEmpty) return null;
    final chapterIndex = checkpoint.chapterIndex
        .clamp(0, documents.length - 1)
        .toInt();
    final document = documents[chapterIndex];
    if (document.segments.isEmpty) return null;
    final position = checkpoint.textVersion < BookNarrationDocument.textVersion
        ? document.remapLegacyPosition(
            checkpoint.segmentIndex,
            checkpoint.characterOffset,
            textVersion: checkpoint.textVersion,
          )
        : (checkpoint.segmentIndex, checkpoint.characterOffset);
    final segmentIndex = position.$1
        .clamp(0, document.segments.length - 1)
        .toInt();
    final segment = document.segments[segmentIndex];
    return BookNarrationCheckpoint(
      chapterIndex: chapterIndex,
      segmentIndex: segmentIndex,
      textVersion: BookNarrationDocument.textVersion,
      characterOffset: position.$2.clamp(0, segment.text.length).toInt(),
      updatedAtEpochMs: checkpoint.updatedAtEpochMs,
    );
  }

  int get _narrationTotalCharacters =>
      _narrationChapterCharacters.fold<int>(0, (total, count) => total + count);

  /// Where narration is, in characters from the start of the book.
  int get _narrationCharacterPosition {
    if (_narrationDocuments.isEmpty) return 0;
    final chapter = _chapterIndex
        .clamp(0, _narrationDocuments.length - 1)
        .toInt();
    var position = 0;
    for (var index = 0; index < chapter; index++) {
      position += _narrationChapterCharacters[index];
    }
    final segments = _narrationDocuments[chapter].segments;
    if (segments.isEmpty) return position;
    final segmentIndex = (_narrationSegmentIndex ?? 0)
        .clamp(0, segments.length - 1)
        .toInt();
    for (var index = 0; index < segmentIndex; index++) {
      position += segments[index].text.length;
    }
    return position +
        _narrationResumeOffset
            .clamp(0, segments[segmentIndex].text.length)
            .toInt();
  }

  /// The sentence and word start at [characters] into the book. The end of
  /// the book maps to the start of its last sentence.
  (int, int, int)? _narrationPositionAt(int characters) {
    var remaining = characters;
    (int, int, int)? last;
    for (var chapter = 0; chapter < _narrationDocuments.length; chapter++) {
      final segments = _narrationDocuments[chapter].segments;
      if (segments.isEmpty) continue;
      last = (chapter, segments.length - 1, 0);
      if (remaining >= _narrationChapterCharacters[chapter]) {
        remaining -= _narrationChapterCharacters[chapter];
        continue;
      }
      for (var index = 0; index < segments.length; index++) {
        final text = segments[index].text;
        if (remaining < text.length) {
          var offset = remaining < 0 ? 0 : remaining;
          // Start on a word, so a voice never begins mid-word.
          while (offset > 0 && text[offset - 1].trim().isNotEmpty) {
            offset--;
          }
          return (chapter, index, offset);
        }
        remaining -= text.length;
      }
    }
    return last;
  }

  /// Progress on the character timeline (the dock hairline, the seek bar).
  double get _narrationOverallProgress {
    final total = _narrationTotalCharacters;
    if (total == 0) return 0;
    return (_narrationCharacterPosition / total).clamp(0.0, 1.0);
  }

  String get _narrationSemanticText {
    final segmentText = _currentNarrationSegment?.text.trim();
    final status = _narrationPreparing
        ? 'Preparing narration.'
        : _narrationPlaying
        ? 'Playing.'
        : 'Paused.';
    final passage = segmentText == null || segmentText.isEmpty
        ? ''
        : ' Current passage: $segmentText';
    final provider = _narrationProvider.trim().isEmpty
        ? ''
        : ' Provider: ${_narrationProvider.trim()}.';
    final model = _narrationModel.trim().isEmpty
        ? ''
        : ' Model: ${_narrationModel.trim()}.';
    final tracking = switch (_narrationAlignmentGranularity) {
      BookNarrationAlignmentGranularity.word => ' Word synchronized.',
      BookNarrationAlignmentGranularity.phrase => ' Phrase synchronized.',
      BookNarrationAlignmentGranularity.sentence => ' Sentence synchronized.',
      BookNarrationAlignmentGranularity.none =>
        _narrationProvider.isEmpty ? '' : ' Text highlighting unavailable.',
    };
    return '$status$passage Voice: $_narrationVoiceLabel. '
        '$_narrationDisclosure.$provider$model$tracking';
  }

  void _syncRemoteDock() {
    if (!mounted) return;
    final remote = _remoteDockController;
    if (!_narrationVisible || _chapters.isEmpty) {
      if (_remoteDockAttached) {
        remote.release(_remoteDockOwner);
        _remoteDockAttached = false;
      }
      return;
    }
    if (!_remoteDockAttached) {
      remote.attach(
        ownerToken: _remoteDockOwner,
        onToggle: _toggleNarration,
        onPrevious: () => _skipNarration(-1),
        onNext: () => _skipNarration(1),
        onSeek: _seekNarrationProgress,
        onStyleChanged: _changeNarrationStyle,
        onSpeedChanged: _changeNarrationSpeed,
        onStop: _closeNarration,
        onReplaced: _retireNarration,
        active: true,
        playing: _narrationPlaying,
        preparing: _narrationPreparing,
        progress: _narrationOverallProgress,
        semanticText: _narrationSemanticText,
        style: _narrationStyle,
        speed: _narrationSpeed,
        branchIndex: widget.shellBranchIndex,
        onChapters: _showContents,
        onSkip: _skipNarrationTime,
        resourceId: widget.resourceId,
        title: _narrationTitle,
        author: _resource?.authorOrCreator ?? '',
        chapterIndex: _chapterIndex,
        chapterTitle: _narrationChapterTitle,
        duration: _narrationListenDuration,
      );
      _remoteDockAttached = true;
      return;
    }
    remote.update(
      ownerToken: _remoteDockOwner,
      active: true,
      playing: _narrationPlaying,
      preparing: _narrationPreparing,
      progress: _narrationOverallProgress,
      semanticText: _narrationSemanticText,
      style: _narrationStyle,
      speed: _narrationSpeed,
      branchIndex: widget.shellBranchIndex,
      title: _narrationTitle,
      author: _resource?.authorOrCreator ?? '',
      chapterIndex: _chapterIndex,
      chapterTitle: _narrationChapterTitle,
      duration: _narrationListenDuration,
    );
  }

  String get _narrationTitle {
    final title = _resource?.title.trim() ?? '';
    return title.isEmpty ? widget.fallbackTitle : title;
  }

  String get _narrationChapterTitle =>
      _chapterIndex >= 0 && _chapterIndex < _chapters.length
      ? _chapters[_chapterIndex].title
      : '';

  int get _progressPercent {
    if (_chapters.isEmpty) return 0;
    return ((_chapterIndex / _chapters.length) * 100).round();
  }

  Future<void> _persistProgress({bool completed = false}) async {
    if (_chapters.isEmpty) return;
    final progress = completed ? 100 : _progressPercent;
    final chapterIndex = _chapterIndex.clamp(0, _chapters.length - 1).toInt();
    final checkpoint =
        _lastNarrationCheckpoint ?? _captureNarrationCheckpoint();
    final cursor = <String, dynamic>{
      ...?_resource?.cursorJson,
      'chapter': chapterIndex,
      'chapterTitle': _chapters[chapterIndex].title,
      'narrationStyle': _narrationStyle.apiName,
      'narrationSpeed': _narrationSpeed,
      if (checkpoint != null) ...{
        'narrationChapter': checkpoint.chapterIndex,
        'narrationSegment': checkpoint.segmentIndex,
        'narrationCharacterOffset': checkpoint.characterOffset,
        'narrationUpdatedAtEpochMs': checkpoint.updatedAtEpochMs,
        'narrationTextVersion': checkpoint.textVersion,
      },
    };
    final repository = _repository;
    _progressWrite = _progressWrite.then((_) async {
      try {
        await repository.updateProgress(
          widget.resourceId,
          progressPercent: progress,
          completed: completed,
          cursorJson: cursor,
        );
      } catch (_) {
        // Reading must remain uninterrupted when a background sync misses.
      }
    });
    await _progressWrite;
  }

  BookNarrationCheckpoint? _captureNarrationCheckpoint() {
    if (_narrationDocuments.isEmpty) return null;
    final chapterIndex = _chapterIndex
        .clamp(0, _narrationDocuments.length - 1)
        .toInt();
    final document = _narrationDocuments[chapterIndex];
    final currentSegment = _narrationSegmentIndex;
    if (document.segments.isEmpty || currentSegment == null) return null;
    final segmentIndex = currentSegment
        .clamp(0, document.segments.length - 1)
        .toInt();
    final segment = document.segments[segmentIndex];
    return BookNarrationCheckpoint(
      chapterIndex: chapterIndex,
      segmentIndex: segmentIndex,
      characterOffset: _narrationResumeOffset
          .clamp(0, segment.text.length)
          .toInt(),
      updatedAtEpochMs: DateTime.now().millisecondsSinceEpoch,
      textVersion: BookNarrationDocument.textVersion,
    );
  }

  void _scheduleNarrationCheckpoint() {
    // Throttle instead of debounce: word-level progress can arrive faster than
    // the persistence interval, but continuous playback must still reach disk.
    if (_narrationCheckpointTimer?.isActive ?? false) return;
    _narrationCheckpointTimer = Timer(const Duration(milliseconds: 600), () {
      _narrationCheckpointTimer = null;
      unawaited(_flushNarrationCheckpoint());
    });
  }

  Future<void> _queueNarrationCheckpointWrite(
    BookNarrationCheckpoint checkpoint, {
    bool includeActiveResume = true,
    bool? wasPlaying,
  }) {
    final activeResume =
        includeActiveResume &&
            !_leavingReader &&
            _narrationVisible &&
            !_narrationFinished
        ? ActiveBookNarrationResume(
            ownerId: _resumeOwnerId,
            resourceId: widget.resourceId,
            fallbackTitle: (_resource?.title.trim().isNotEmpty ?? false)
                ? _resource!.title
                : widget.fallbackTitle,
            branchIndex: widget.shellBranchIndex,
            checkpoint: checkpoint,
            wasPlaying:
                wasPlaying ?? (_narrationPlaying || _narrationPreparing),
            updatedAtEpochMs: checkpoint.updatedAtEpochMs,
          )
        : null;
    _checkpointWrite = _checkpointWrite.then((_) async {
      try {
        await _checkpointStore.write(_checkpointStorageId, checkpoint);
      } catch (_) {
        // Backend sync remains a fallback when local persistence is unavailable.
      }
      if (activeResume != null) {
        try {
          await _activeResumeStore.write(activeResume);
        } catch (_) {
          // The per-book checkpoint remains usable when active routing fails.
        }
      }
    });
    return _checkpointWrite;
  }

  Future<void> _clearActiveResume() {
    _checkpointWrite = _checkpointWrite.then((_) async {
      try {
        await _activeResumeStore.clear(_resumeOwnerId);
      } catch (_) {
        // Explicit stop still ends audio even if local route cleanup fails.
      }
    });
    return _checkpointWrite;
  }

  Future<void> _finishNarrationResume() async {
    await _flushNarrationCheckpoint(includeActiveResume: false);
    await _clearActiveResume();
  }

  Future<void> _flushNarrationCheckpoint({
    bool syncRemote = false,
    bool includeActiveResume = true,
    bool? wasPlaying,
  }) async {
    _narrationCheckpointTimer?.cancel();
    _narrationCheckpointTimer = null;
    final checkpoint = _captureNarrationCheckpoint();
    if (checkpoint == null) return;
    _lastNarrationCheckpoint = checkpoint;
    await _queueNarrationCheckpointWrite(
      checkpoint,
      includeActiveResume: includeActiveResume,
      wasPlaying: wasPlaying,
    );
    if (syncRemote) unawaited(_persistProgress());
  }

  BookNarrationDocument? get _currentNarrationDocument {
    if (_chapterIndex < 0 || _chapterIndex >= _narrationDocuments.length) {
      return null;
    }
    return _narrationDocuments[_chapterIndex];
  }

  BookNarrationSegment? get _currentNarrationSegment {
    final document = _currentNarrationDocument;
    final index = _narrationSegmentIndex;
    if (document == null ||
        index == null ||
        index < 0 ||
        index >= document.segments.length) {
      return null;
    }
    return document.segments[index];
  }

  void _onNarrationProgress(int start, int end, String _) {
    if (!mounted || !_narrationPlaying) return;
    final segment = _currentNarrationSegment;
    if (segment == null) return;
    final wordStart = (_speechBaseOffset + start)
        .clamp(0, segment.text.length)
        .toInt();
    final wordEnd = (_speechBaseOffset + end)
        .clamp(wordStart, segment.text.length)
        .toInt();
    setState(() {
      _narrationWordStart = wordStart;
      _narrationWordEnd = wordEnd;
      // Pause/resume repeats the current word instead of dropping a syllable.
      if (wordEnd > wordStart) _narrationResumeOffset = wordStart;
    });
    _scheduleNarrationCheckpoint();
    _syncRemoteDock();
  }

  void _onNarrationTrackEvent(BookNarrationTrackEvent event) {
    if (!mounted || event.sessionId != _narrationTrackSessionId) return;
    if (event.chapterIndex < 0 ||
        event.chapterIndex >= _narrationDocuments.length) {
      return;
    }
    final document = _narrationDocuments[event.chapterIndex];
    if (event.segmentIndex < 0 ||
        event.segmentIndex >= document.segments.length) {
      return;
    }

    final chapterChanged = event.chapterIndex != _chapterIndex;
    final segmentChanged =
        chapterChanged || event.segmentIndex != _narrationSegmentIndex;
    final audio = event.audio;
    setState(() {
      _chapterIndex = event.chapterIndex;
      _narrationSegmentIndex = event.segmentIndex;
      if (segmentChanged) _narrationResumeOffset = 0;
      if (event.alignmentGranularity !=
          BookNarrationAlignmentGranularity.none) {
        _narrationAlignmentGranularity = event.alignmentGranularity;
      }
      if (audio != null) {
        // A new audio-only clip must clear timing claims from the prior clip.
        _narrationAlignmentGranularity = audio.alignmentGranularity;
        _narrationProvider = audio.provider;
        _narrationModel = audio.model;
        final profileLabel = audio.narratorProfileLabel.trim();
        final voiceLabel = audio.voiceDisplayName.trim();
        if (profileLabel.isNotEmpty) {
          _narrationVoiceLabel = profileLabel;
        } else if (audio.narratorProfile == 'seasoned_mentor') {
          _narrationVoiceLabel = 'Seasoned mentor';
        } else if (voiceLabel.isNotEmpty) {
          _narrationVoiceLabel = voiceLabel;
        }
        if (_activeIdolName.isEmpty && audio.disclosure.trim().isNotEmpty) {
          _narrationDisclosure = audio.disclosure.trim();
        }
      }

      switch (event.phase) {
        case BookNarrationPlaybackPhase.preparing:
        case BookNarrationPlaybackPhase.buffering:
          _narrationPreparing = true;
          _narrationWordStart = 0;
          _narrationWordEnd = 0;
          break;
        case BookNarrationPlaybackPhase.playing:
          _narrationPreparing = false;
          _narrationPlaying = true;
          _narrationFinished = false;
          _narrationWordStart = event.highlightStart ?? 0;
          _narrationWordEnd = event.highlightEnd ?? 0;
          if ((event.resumeCharacterOffset ?? event.highlightStart)
              case final offset?) {
            _narrationResumeOffset = offset;
          }
          break;
        case BookNarrationPlaybackPhase.paused:
          _narrationPreparing = false;
          _narrationPlaying = false;
          _narrationWordStart = 0;
          _narrationWordEnd = 0;
          if ((event.resumeCharacterOffset ?? event.highlightStart)
              case final offset?) {
            _narrationResumeOffset = offset;
          }
          break;
        case BookNarrationPlaybackPhase.completed:
          _narrationPreparing = false;
          _narrationPlaying = false;
          _narrationFinished = true;
          _narrationTrackReady = false;
          _narrationWordStart = 0;
          _narrationWordEnd = 0;
          break;
      }
    });
    _scheduleNarrationCheckpoint();
    _syncRemoteDock();

    if (chapterChanged) {
      _narrationChangingChapter = true;
      unawaited(
        _pageController
            .animateToPage(
              event.chapterIndex,
              duration: const Duration(milliseconds: 280),
              curve: Curves.easeOutCubic,
            )
            .whenComplete(() => _narrationChangingChapter = false),
      );
      unawaited(_persistProgress());
    }
    if (segmentChanged) _revealNarrationSegment();
    if (event.phase == BookNarrationPlaybackPhase.completed) {
      unawaited(_finishNarrationResume());
      _toast('You’ve reached the end of the book.');
    }
  }

  void _onNarrationError(Object error) {
    if (!mounted || (!_narrationPlaying && !_narrationPreparing)) return;
    _narrationRun++;
    _narrationTrackSessionId = null;
    _narrationTrackReady = false;
    setState(() {
      _narrationPlaying = false;
      _narrationPreparing = false;
    });
    if (_narrator case final BookNarrationTrackController controller) {
      unawaited(controller.pauseTrack().catchError((_) {}));
    }
    _syncRemoteDock();
    unawaited(_flushNarrationCheckpoint(wasPlaying: false));
    _toast(_narrationFailureMessage(error));
  }

  String _narrationFailureMessage(Object error) {
    return switch (classifyBookNarrationFailure(error)) {
      BookNarrationFailureKind.network || BookNarrationFailureKind.timeout =>
        'Narration paused. Check your connection and try again.',
      BookNarrationFailureKind.rateLimited =>
        'Narration is busy right now. Try again in a moment.',
      BookNarrationFailureKind.service =>
        'Expressive narration is temporarily unavailable. Try again shortly.',
      BookNarrationFailureKind.authentication =>
        'Your session expired. Sign in again to listen.',
      BookNarrationFailureKind.content =>
        'This passage couldn’t be prepared for narration.',
      BookNarrationFailureKind.audio =>
        'Narration audio couldn’t be loaded. Try again.',
      BookNarrationFailureKind.invalidResponse =>
        'Narration returned an invalid audio response. Try again.',
      BookNarrationFailureKind.unknown =>
        'Narration couldn’t start. Try again.',
    };
  }

  void _onNarrationVoiceChanged(BookNarrationVoiceKind voice) {
    if (!mounted || _narrationVoice == voice) return;
    setState(() => _narrationVoice = voice);
    if (voice == BookNarrationVoiceKind.device && !_deviceFallbackAnnounced) {
      _deviceFallbackAnnounced = true;
      _toast('Expressive voice is offline. Continuing with the device voice.');
    }
  }

  Future<void> _toggleNarration() async {
    if (_narrationPlaying || _narrationPreparing) {
      await _pauseNarration();
      return;
    }
    await _playNarration();
  }

  Future<void> _playNarration() async {
    final document = _currentNarrationDocument;
    if (document == null || document.segments.isEmpty) {
      _toast('There’s no readable text in this chapter.');
      return;
    }

    final trackController = _narrator is BookNarrationTrackController
        ? _narrator as BookNarrationTrackController
        : null;
    final resumeLoadedTrack =
        trackController != null &&
        _narrationTrackReady &&
        _narrationTrackSessionId != null &&
        !_narrationFinished;
    final run = resumeLoadedTrack ? _narrationTrackSessionId! : ++_narrationRun;
    if (!resumeLoadedTrack && trackController != null) {
      _narrationTrackSessionId = run;
    }
    var segmentIndex = _narrationSegmentIndex;
    if (_narrationFinished ||
        segmentIndex == null ||
        segmentIndex >= document.segments.length) {
      segmentIndex = 0;
      _narrationResumeOffset = 0;
    }
    setState(() {
      _narrationVisible = true;
      _narrationPreparing = true;
      _narrationFinished = false;
      _narrationSegmentIndex = segmentIndex;
    });
    _syncRemoteDock();
    unawaited(_flushNarrationCheckpoint(wasPlaying: false));

    try {
      if (!_narratorReady) {
        await _narrator.initialize(speed: _narrationSpeed);
        _narratorReady = true;
      } else {
        await _narrator.setSpeed(_narrationSpeed);
      }
    } catch (_) {
      if (!mounted || run != _narrationRun) return;
      setState(() => _narrationPreparing = false);
      _syncRemoteDock();
      _toast('Narration isn’t available on this device.');
      return;
    }

    if (!mounted || run != _narrationRun) return;
    if (trackController != null) {
      try {
        if (!resumeLoadedTrack) {
          await trackController.loadTrack(
            sessionId: run,
            chapters: _narrationDocuments,
            initialChapterIndex: _chapterIndex,
            initialSegmentIndex: segmentIndex,
            initialCharacterOffset: _narrationResumeOffset,
          );
          if (!mounted || run != _narrationTrackSessionId) return;
          _narrationTrackReady = true;
        }
        setState(() {
          _narrationPreparing = false;
          _narrationPlaying = true;
          _narrationFinished = false;
        });
        _syncRemoteDock();
        unawaited(_flushNarrationCheckpoint(wasPlaying: true));
        await trackController.playTrack();
      } catch (error) {
        if (!mounted || run != _narrationTrackSessionId) return;
        _narrationTrackReady = false;
        setState(() {
          _narrationPlaying = false;
          _narrationPreparing = false;
        });
        _syncRemoteDock();
        unawaited(_flushNarrationCheckpoint(wasPlaying: false));
        _toast(_narrationFailureMessage(error));
      }
      return;
    }
    setState(() {
      _narrationPreparing = false;
      _narrationPlaying = true;
    });
    _syncRemoteDock();
    unawaited(_flushNarrationCheckpoint(wasPlaying: true));
    await _runNarration(run);
  }

  Future<void> _runNarration(int run) async {
    while (mounted && run == _narrationRun && _narrationPlaying) {
      final document = _currentNarrationDocument;
      if (document == null || document.segments.isEmpty) {
        if (!await _advanceNarrationChapter(run)) return;
        continue;
      }

      var segmentIndex = _narrationSegmentIndex ?? 0;
      if (segmentIndex >= document.segments.length) {
        if (!await _advanceNarrationChapter(run)) return;
        continue;
      }

      final segment = document.segments[segmentIndex];
      var offset = _narrationResumeOffset.clamp(0, segment.text.length).toInt();
      while (offset < segment.text.length &&
          segment.text[offset].trim().isEmpty) {
        offset++;
      }
      if (offset >= segment.text.length) {
        setState(() {
          _narrationSegmentIndex = segmentIndex + 1;
          _narrationResumeOffset = 0;
        });
        continue;
      }

      _speechBaseOffset = offset;
      setState(() {
        _narrationSegmentIndex = segmentIndex;
        _narrationWordStart = offset;
        _narrationWordEnd = offset;
      });
      _revealNarrationSegment();
      _prefetchUpcomingNarration(document, segmentIndex);

      try {
        await _narrator.speak(segment.text.substring(offset));
      } catch (_) {
        if (!mounted || run != _narrationRun) return;
        setState(() => _narrationPlaying = false);
        _syncRemoteDock();
        unawaited(_flushNarrationCheckpoint(wasPlaying: false));
        _toast('Narration paused. Try playing it again.');
        return;
      }
      if (!mounted || run != _narrationRun || !_narrationPlaying) return;

      segmentIndex++;
      setState(() {
        _narrationSegmentIndex = segmentIndex;
        _narrationResumeOffset = 0;
        _narrationWordStart = 0;
        _narrationWordEnd = 0;
      });
    }
  }

  Future<bool> _advanceNarrationChapter(int run) async {
    if (_chapterIndex >= _narrationDocuments.length - 1) {
      if (!mounted || run != _narrationRun) return false;
      final lastDocument = _currentNarrationDocument;
      setState(() {
        _narrationPlaying = false;
        _narrationFinished = true;
        _narrationSegmentIndex =
            lastDocument == null || lastDocument.segments.isEmpty
            ? null
            : lastDocument.segments.length - 1;
        _narrationResumeOffset = 0;
      });
      _syncRemoteDock();
      unawaited(_finishNarrationResume());
      _toast('You’ve reached the end of the book.');
      return false;
    }

    _narrationChangingChapter = true;
    try {
      await _pageController.nextPage(
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOutCubic,
      );
    } finally {
      _narrationChangingChapter = false;
    }
    if (!mounted || run != _narrationRun) return false;
    setState(() {
      _narrationSegmentIndex = 0;
      _narrationResumeOffset = 0;
      _narrationWordStart = 0;
      _narrationWordEnd = 0;
    });
    return true;
  }

  Future<void> _pauseNarration() async {
    if (_narrator case final BookNarrationTrackController controller
        when _narrationTrackReady) {
      if (mounted) {
        setState(() {
          _narrationPlaying = false;
          _narrationPreparing = false;
          _narrationWordStart = 0;
          _narrationWordEnd = 0;
        });
        _syncRemoteDock();
      }
      try {
        await controller.pauseTrack();
      } catch (_) {}
      await _flushNarrationCheckpoint(syncRemote: true);
      return;
    }
    _narrationRun++;
    _narrationTrackSessionId = null;
    _narrationTrackReady = false;
    if (mounted) {
      setState(() {
        _narrationPlaying = false;
        _narrationPreparing = false;
        if (_narrationWordStart > 0) {
          _narrationResumeOffset = _narrationWordStart;
        }
      });
      _syncRemoteDock();
    }
    try {
      await _narrator.stop();
    } catch (_) {}
    await _flushNarrationCheckpoint(syncRemote: true);
  }

  Future<void> _closeNarration() async {
    _narrationCheckpointTimer?.cancel();
    _narrationCheckpointTimer = null;
    final checkpoint = _captureNarrationCheckpoint();
    if (checkpoint != null) _lastNarrationCheckpoint = checkpoint;
    _narrationRun++;
    _narrationTrackSessionId = null;
    _narrationTrackReady = false;
    if (mounted) {
      setState(() {
        _narrationVisible = false;
        _narrationPlaying = false;
        _narrationPreparing = false;
        _narrationFinished = false;
        _narrationSegmentIndex = null;
        _narrationResumeOffset = 0;
        _narrationWordStart = 0;
        _narrationWordEnd = 0;
        _narrationAlignmentGranularity = BookNarrationAlignmentGranularity.none;
        // The next track reports its own provider; until then nothing may
        // claim (or deny) word timing.
        _narrationProvider = '';
        _narrationModel = '';
      });
      _syncRemoteDock();
    }
    final stop = _narrator.stop().catchError((_) {});
    if (checkpoint != null) {
      await _queueNarrationCheckpointWrite(
        checkpoint,
        includeActiveResume: false,
      );
      unawaited(_persistProgress());
    }
    await _clearActiveResume();
    await stop;
  }

  Future<void> _retireNarration() async {
    _narrationCheckpointTimer?.cancel();
    _narrationCheckpointTimer = null;
    final checkpoint = _captureNarrationCheckpoint();
    if (checkpoint != null) _lastNarrationCheckpoint = checkpoint;
    _narrationRun++;
    _narrationTrackSessionId = null;
    _narrationTrackReady = false;
    if (mounted) {
      setState(() {
        _narrationVisible = false;
        _narrationPlaying = false;
        _narrationPreparing = false;
        _narrationFinished = false;
        _narrationSegmentIndex = null;
        _narrationResumeOffset = 0;
        _narrationWordStart = 0;
        _narrationWordEnd = 0;
        _narrationAlignmentGranularity = BookNarrationAlignmentGranularity.none;
        _narrationProvider = '';
        _narrationModel = '';
      });
      _syncRemoteDock();
    }
    final stop = _narrator.stop().catchError((_) {});
    if (checkpoint != null) {
      await _queueNarrationCheckpointWrite(
        checkpoint,
        includeActiveResume: false,
      );
    }
    await stop;
  }

  Future<void> _skipNarration(int direction) async {
    final currentDocument = _currentNarrationDocument;
    if (currentDocument == null || currentDocument.segments.isEmpty) return;
    var chapter = _chapterIndex;
    var segment = (_narrationSegmentIndex ?? 0) + direction;
    if (segment < 0 && chapter > 0) {
      chapter--;
      segment = _narrationDocuments[chapter].segments.length - 1;
    } else if (segment >= currentDocument.segments.length &&
        chapter < _narrationDocuments.length - 1) {
      chapter++;
      segment = 0;
    }
    await _seekNarrationTo(chapter, segment);
  }

  Future<void> _seekNarrationProgress(double progress) async {
    final total = _narrationTotalCharacters;
    if (total == 0) return;
    final target = _narrationPositionAt(
      (progress.clamp(0.0, 1.0) * total).round(),
    );
    if (target == null) return;
    await _seekNarrationTo(target.$1, target.$2, characterOffset: target.$3);
  }

  /// The full player's ±15 s: [delta] of the book's time at 1× converted to
  /// characters, landing on the word there. Clamped at the ends, where it
  /// does nothing; anywhere else it always moves.
  Future<void> _skipNarrationTime(Duration delta) async {
    final total = _narrationTotalCharacters;
    if (total == 0) return;
    final position = _narrationCharacterPosition;
    final characters =
        (delta.inMicroseconds /
                Duration.microsecondsPerSecond *
                bookNarrationCharactersPerSecond)
            .round();
    final target = (position + characters).clamp(0, total).toInt();
    if (target == position || characters == 0) return;
    final landing = _narrationPositionAt(target);
    if (landing == null) return;
    var landed = 0;
    for (var index = 0; index < landing.$1; index++) {
      landed += _narrationChapterCharacters[index];
    }
    final segments = _narrationDocuments[landing.$1].segments;
    for (var index = 0; index < landing.$2; index++) {
      landed += segments[index].text.length;
    }
    landed += landing.$3;
    // Forward past the last sentence's start: already at the end.
    if (characters > 0 && landed <= position) return;
    await _seekNarrationTo(landing.$1, landing.$2, characterOffset: landing.$3);
  }

  Future<void> _seekNarrationTo(
    int chapter,
    int segment, {
    int characterOffset = 0,
  }) async {
    if (_narrationDocuments.isEmpty) return;
    chapter = chapter.clamp(0, _narrationDocuments.length - 1).toInt();
    final targetDocument = _narrationDocuments[chapter];
    if (targetDocument.segments.isEmpty) return;
    segment = segment.clamp(0, targetDocument.segments.length - 1).toInt();
    final offset = characterOffset
        .clamp(0, targetDocument.segments[segment].text.length)
        .toInt();
    final continuePlaying = _narrationPlaying;

    if (_narrator case final BookNarrationTrackController controller
        when _narrationTrackReady) {
      if (!mounted) return;
      // Move the chapter here, with the sentence and offset: the track's
      // seek event then matches this position instead of reading as a
      // chapter change, which would reset the in-sentence offset to 0.
      final chapterChanged = chapter != _chapterIndex;
      setState(() {
        _narrationVisible = true;
        _narrationFinished = false;
        _chapterIndex = chapter;
        _narrationSegmentIndex = segment;
        _narrationResumeOffset = offset;
        _narrationWordStart = 0;
        _narrationWordEnd = 0;
      });
      _syncRemoteDock();
      // The page follows at once, as it does for a chapter the track reaches.
      if (chapterChanged) {
        _narrationChangingChapter = true;
        unawaited(
          _pageController
              .animateToPage(
                chapter,
                duration: const Duration(milliseconds: 280),
                curve: Curves.easeOutCubic,
              )
              .whenComplete(() => _narrationChangingChapter = false),
        );
        unawaited(_persistProgress());
      }
      var seekSessionId = _narrationTrackSessionId;
      try {
        try {
          await controller.seekToSentence(
            chapterIndex: chapter,
            segmentIndex: segment,
            characterOffset: offset,
          );
        } on RangeError {
          if (!mounted || seekSessionId != _narrationTrackSessionId) return;
          final sessionId = ++_narrationRun;
          _narrationTrackSessionId = sessionId;
          seekSessionId = sessionId;
          _narrationTrackReady = false;
          setState(() => _narrationPreparing = true);
          _syncRemoteDock();
          await controller.loadTrack(
            sessionId: sessionId,
            chapters: _narrationDocuments,
            initialChapterIndex: chapter,
            initialSegmentIndex: segment,
            initialCharacterOffset: offset,
          );
          if (!mounted || sessionId != _narrationTrackSessionId) return;
          _narrationTrackReady = true;
          if (continuePlaying) await controller.playTrack();
        }
      } catch (_) {
        if (!mounted || seekSessionId != _narrationTrackSessionId) return;
        setState(() {
          _narrationPreparing = false;
          _narrationPlaying = false;
          _narrationTrackReady = false;
        });
        _syncRemoteDock();
        unawaited(_flushNarrationCheckpoint(wasPlaying: false));
        _toast('Couldn’t move the narration. Try again.');
        return;
      }
      if (!mounted || seekSessionId != _narrationTrackSessionId) return;
      _revealNarrationSegment();
      _scheduleNarrationCheckpoint();
      return;
    }

    _narrationRun++;
    setState(() {
      _narrationPlaying = false;
      _narrationPreparing = false;
      _narrationFinished = false;
    });
    _syncRemoteDock();
    try {
      await _narrator.stop();
    } catch (_) {}

    if (chapter != _chapterIndex) {
      _narrationChangingChapter = true;
      try {
        await _pageController.animateToPage(
          chapter,
          duration: const Duration(milliseconds: 280),
          curve: Curves.easeOutCubic,
        );
      } finally {
        _narrationChangingChapter = false;
      }
    }
    if (!mounted) return;
    setState(() {
      _narrationVisible = true;
      _narrationSegmentIndex = segment;
      _narrationResumeOffset = offset;
      _narrationWordStart = 0;
      _narrationWordEnd = 0;
    });
    _syncRemoteDock();
    _revealNarrationSegment();
    _scheduleNarrationCheckpoint();
    if (continuePlaying) unawaited(_playNarration());
  }

  Future<void> _changeNarrationSpeed(double speed) async {
    if (_narrationSpeed == speed) return;
    if (_narrator is BookNarrationTrackController) {
      setState(() => _narrationSpeed = speed);
      _syncRemoteDock();
      try {
        await _narrator.setSpeed(speed);
      } catch (_) {
        if (mounted) _toast('Couldn’t change the listening speed.');
      }
      unawaited(_persistProgress());
      return;
    }
    final continuePlaying = _narrationPlaying;
    _narrationRun++;
    _narrationTrackSessionId = null;
    _narrationTrackReady = false;
    setState(() {
      _narrationSpeed = speed;
      _narrationPlaying = false;
      _narrationPreparing = false;
    });
    _syncRemoteDock();
    try {
      await _narrator.stop();
      if (_narratorReady) await _narrator.setSpeed(speed);
    } catch (_) {}
    unawaited(_persistProgress());
    if (continuePlaying && mounted) unawaited(_playNarration());
  }

  Future<void> _changeNarrationStyle(BookNarrationStyle style) async {
    if (_narrationStyle == style ||
        _narrator is! BookNarrationStyleController) {
      return;
    }
    final controller = _narrator as BookNarrationStyleController;
    final continuePlaying = _narrationPlaying;
    _narrationRun++;
    _narrationTrackSessionId = null;
    _narrationTrackReady = false;
    setState(() {
      _narrationStyle = style;
      _narrationVoice = BookNarrationVoiceKind.expressiveAi;
      _narrationPlaying = false;
      _narrationPreparing = continuePlaying;
    });
    _syncRemoteDock();
    try {
      await _narrator.stop();
      await controller.setStyle(style);
    } catch (_) {
      if (mounted) _toast('Couldn’t change the narration style.');
    }
    if (!mounted) return;
    setState(() => _narrationPreparing = false);
    _syncRemoteDock();
    unawaited(_persistProgress());
    if (continuePlaying) unawaited(_playNarration());
  }

  void _prefetchUpcomingNarration(
    BookNarrationDocument document,
    int currentIndex,
  ) {
    if (_narrator is! BookNarrationPreloader) return;
    final preloader = _narrator as BookNarrationPreloader;
    for (
      var index = currentIndex + 1;
      index < document.segments.length && index <= currentIndex + 2;
      index++
    ) {
      final text = document.segments[index].text;
      unawaited(() async {
        try {
          await preloader.prepare(text);
        } catch (_) {
          // Prefetch is opportunistic; speak() owns fallback and error UX.
        }
      }());
    }
  }

  GlobalKey _narrationBlockKey(int chapterIndex, int blockIndex) {
    return _narrationBlockKeys.putIfAbsent(
      '$chapterIndex-$blockIndex',
      GlobalKey.new,
    );
  }

  void _revealNarrationSegment() {
    final segment = _currentNarrationSegment;
    if (segment == null) return;
    final key = _narrationBlockKey(_chapterIndex, segment.blockIndex);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || key.currentContext == null) return;
      Scrollable.ensureVisible(
        key.currentContext!,
        alignment: 0.34,
        duration: const Duration(milliseconds: 260),
        curve: Curves.easeOutCubic,
      );
    });
  }

  void _onChapterChanged(int index) {
    final narrationControlled = _narrationChangingChapter;
    final continuePlaying = _narrationPlaying || _narrationPreparing;
    _selectParagraph(null);
    _lastScrollY = 0;
    _chromeVisible.value = true;
    setState(() {
      _chapterIndex = index;
      _selectedQuote = null;
      if (!narrationControlled && _narrationVisible) {
        _narrationSegmentIndex = 0;
        _narrationResumeOffset = 0;
        _narrationWordStart = 0;
        _narrationWordEnd = 0;
        _narrationPlaying = false;
        _narrationPreparing = false;
        _narrationFinished = false;
      }
    });
    if (!narrationControlled && _narrationVisible) {
      final run = ++_narrationRun;
      _narrationTrackSessionId = null;
      _narrationTrackReady = false;
      unawaited(_restartNarrationAfterChapterChange(continuePlaying, run));
      _scheduleNarrationCheckpoint();
    }
    _syncRemoteDock();
    unawaited(_persistProgress());
  }

  Future<void> _restartNarrationAfterChapterChange(
    bool continuePlaying,
    int run,
  ) async {
    try {
      await _narrator.stop();
    } catch (_) {}
    if (continuePlaying && mounted && run == _narrationRun) {
      unawaited(_playNarration());
    }
  }

  Future<void> _toggleSaved() async {
    if (_resource == null || _savingBook) return;
    final wasSaved = _resource!.isSaved;
    setState(() => _savingBook = true);
    try {
      if (wasSaved) {
        await _repository.unsaveResource(widget.resourceId);
      } else {
        await _repository.saveResource(widget.resourceId);
      }
      if (!mounted) return;
      final refreshed = await _repository.getResource(widget.resourceId);
      if (!mounted) return;
      setState(() => _resource = refreshed);
      _toast(
        wasSaved ? 'Removed from saved' : 'Book saved',
        icon: V3Icons.bookmark,
        success: true,
      );
    } catch (_) {
      if (mounted) _toast('Couldn’t update your library');
    } finally {
      if (mounted) setState(() => _savingBook = false);
    }
  }

  void _toast(
    String message, {
    V3Icons icon = V3Icons.alert,
    bool success = false,
  }) {
    if (!mounted) return;
    showV3Toast(
      context,
      message,
      icon: icon,
      tone: success ? V3ToastTone.success : V3ToastTone.warn,
    );
  }

  Future<void> _openNoteComposer(String selectedQuote) async {
    final quote = selectedQuote.trim();
    if (quote.isEmpty || _chapters.isEmpty) {
      _toast('Select a passage first');
      return;
    }

    // The selection toolbar is an overlay owned by SelectableRegion. Wait for
    // the frame that removes it before pushing another overlay route.
    await WidgetsBinding.instance.endOfFrame;
    if (!mounted) return;

    final chapterIndex = _chapterIndex;
    final chapterTitle = _chapters[chapterIndex].title;
    final created = await showV3Sheet<ContentHighlight>(
      context,
      title: 'Add a note',
      builder: (sheetContext) => BookNoteComposerSheet(
        quote: quote,
        onSave: (noteText) => _repository.createHighlight(
          widget.resourceId,
          locatorJson: {'chapter': chapterIndex, 'chapterTitle': chapterTitle},
          quoteText: _limited(quote, 5000),
          noteText: noteText,
        ),
      ),
    );
    if (!mounted || created == null) return;
    setState(() {
      _notes = [created, ..._notes];
      _selectedQuote = null;
    });
    _toast('Note saved to this book', icon: V3Icons.note, success: true);
  }

  String _limited(String value, int max) =>
      value.length <= max ? value : value.substring(0, max);

  Widget _selectionMenu(
    BuildContext context,
    SelectableRegionState selectionState,
  ) {
    return AdaptiveTextSelectionToolbar.buttonItems(
      anchors: selectionState.contextMenuAnchors,
      buttonItems: [
        ...selectionState.contextMenuButtonItems,
        ContextMenuButtonItem(
          label: 'Add note',
          onPressed: () {
            final quote = _selectedQuote?.trim() ?? '';
            selectionState.hideToolbar();
            selectionState.clearSelection();
            unawaited(_openNoteComposer(quote));
          },
        ),
      ],
    );
  }

  // ── paragraphs: Highlight / Note / Quote ──────────────────────────────────

  void _selectParagraph(int? index, {_PopoverAnchor? anchor}) {
    if (_selectedParagraph == index && anchor == null) return;
    setState(() {
      _selectedParagraph = index;
      _popoverAnchor = index == null ? null : anchor;
    });
    if (index == null) {
      _popover.hide();
    } else {
      _popover.show();
    }
  }

  void _toggleParagraph(int index, BuildContext paragraph, Offset globalTap) {
    if (_selectedParagraph == index) {
      _selectParagraph(null);
      return;
    }
    _selectParagraph(index, anchor: _anchorFor(paragraph, globalTap));
  }

  /// Where the actions may sit, in the overlay's coordinates: the tapped
  /// paragraph, the tap, and the visible band between the chrome (when
  /// shown) and the bottom bars.
  _PopoverAnchor? _anchorFor(BuildContext paragraph, Offset globalTap) {
    final overlay = Overlay.maybeOf(context)?.context.findRenderObject();
    final box = paragraph.findRenderObject();
    if (overlay is! RenderBox || box is! RenderBox || !box.attached) {
      return null;
    }
    Rect rectOf(RenderBox target) =>
        overlay.globalToLocal(target.localToGlobal(Offset.zero)) & target.size;
    final rect = rectOf(box);
    final viewport = Scrollable.maybeOf(paragraph)?.context.findRenderObject();
    final view = viewport is RenderBox && viewport.attached
        ? rectOf(viewport)
        : Offset.zero & overlay.size;
    final media = MediaQuery.of(context);
    final chrome = media.padding.top + (_chromeVisible.value ? 53 : 0);
    final bottomBars = AppShell.isWithinShell(context)
        ? AppShell.bottomNavClearance(context)
        : _narrationVisible
        ? 0.0
        : media.padding.bottom;
    var tapY = overlay.globalToLocal(globalTap).dy;
    // A semantics tap reports no position: use the paragraph's middle.
    if (tapY < rect.top || tapY > rect.bottom) tapY = rect.center.dy;
    return _PopoverAnchor(
      paragraph: rect,
      tapY: tapY,
      top: view.top + chrome + 8,
      bottom: view.bottom - bottomBars - 8,
    );
  }

  /// The paragraphs of the current chapter page, in the model it renders
  /// (narration blocks while the narration dock is up, Markdown blocks
  /// otherwise).
  List<BookReaderParagraph> _paragraphsFor(int chapterIndex) {
    if (_narrationVisible &&
        chapterIndex < _narrationDocuments.length &&
        _narrationDocuments[chapterIndex].blocks.isNotEmpty) {
      final document = _narrationDocuments[chapterIndex];
      // The narration text is plain (parsed without HTML escaping), so
      // highlights, notes and quotes keep the text the reading view shows.
      return _narrationParagraphs[document] ??= [
        for (final block in document.blocks)
          BookReaderParagraph(
            markdown: block.text,
            text: _normalizedQuote(block.text),
            tappable: _tappableNarrationBlock(block.kind),
          ),
      ];
    }
    return _markdownParagraphs.putIfAbsent(
      chapterIndex,
      () => bookReaderParagraphs(_chapters[chapterIndex].markdown),
    );
  }

  String? get _selectedParagraphText {
    final index = _selectedParagraph;
    if (index == null || _chapters.isEmpty) return null;
    final paragraphs = _paragraphsFor(_chapterIndex);
    if (index < 0 || index >= paragraphs.length) return null;
    final text = paragraphs[index].text;
    return text.isEmpty ? null : text;
  }

  /// How each paragraph of [chapterIndex] is marked by the book's highlights
  /// (the existing highlights API): a highlight or note whose quote is part
  /// of the paragraph.
  List<_ParagraphMark?> _marksFor(
    int chapterIndex,
    List<BookReaderParagraph> paragraphs,
  ) {
    // `_notes` is replaced, never mutated, so its identity keys the cache;
    // each paragraph list belongs to one chapter.
    if (!identical(_marksNotes, _notes)) {
      _marksNotes = _notes;
      _marksCache.clear();
    }
    return _marksCache[paragraphs] ??= _computeMarks(chapterIndex, paragraphs);
  }

  List<_ParagraphMark?> _computeMarks(
    int chapterIndex,
    List<BookReaderParagraph> paragraphs,
  ) {
    final marks = List<_ParagraphMark?>.filled(paragraphs.length, null);
    for (final note in _notes) {
      final chapter = (note.locatorJson?['chapter'] as num?)?.toInt();
      if (chapter != null && chapter != chapterIndex) continue;
      final quote = _normalizedQuote(note.quoteText ?? '');
      if (quote.isEmpty) continue;
      final hasNote = (note.noteText ?? '').trim().isNotEmpty;
      for (var index = 0; index < paragraphs.length; index++) {
        final text = paragraphs[index].text;
        if (text.isEmpty || !text.contains(quote)) continue;
        if (hasNote) {
          marks[index] = _ParagraphMark.note;
        } else {
          marks[index] ??= _ParagraphMark.highlight;
        }
        break;
      }
    }
    return marks;
  }

  Future<void> _highlightSelected() async {
    final quote = _selectedParagraphText;
    _selectParagraph(null);
    if (quote == null || _chapters.isEmpty || _marking) return;
    final chapterIndex = _chapterIndex;
    final paragraphs = _paragraphsFor(chapterIndex);
    final alreadyMarked = _marksFor(chapterIndex, paragraphs).indexed.any(
      (entry) => entry.$2 != null && paragraphs[entry.$1].text == quote,
    );
    if (alreadyMarked) {
      _toast('Highlighted', icon: V3Icons.highlight, success: true);
      return;
    }
    _marking = true;
    try {
      final created = await _repository.createHighlight(
        widget.resourceId,
        locatorJson: {
          'chapter': chapterIndex,
          'chapterTitle': _chapters[chapterIndex].title,
        },
        quoteText: _limited(quote, 5000),
      );
      if (!mounted) return;
      setState(() => _notes = [created, ..._notes]);
      _toast('Highlighted', icon: V3Icons.highlight, success: true);
    } catch (_) {
      if (mounted) _toast('Couldn’t save the highlight. Try again.');
    } finally {
      _marking = false;
    }
  }

  Future<void> _noteSelected() async {
    final quote = _selectedParagraphText;
    _selectParagraph(null);
    if (quote == null) return;
    await _openNoteComposer(quote);
  }

  Future<void> _quoteSelected() async {
    final quote = _selectedParagraphText;
    _selectParagraph(null);
    if (quote == null) return;
    // No quote/share action exists yet, so Quote copies the paragraph.
    await Clipboard.setData(ClipboardData(text: quote));
    if (mounted) _toast('Copied quote', icon: V3Icons.check, success: true);
  }

  Widget _popoverContent(BuildContext context) {
    final anchor = _popoverAnchor;
    if (anchor == null) return const SizedBox.shrink();
    Widget action(V3Icons icon, String label, VoidCallback onTap) =>
        V3Pressable(
          onTap: onTap,
          semanticLabel: label,
          focusRadius: BorderRadius.circular(10),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                V3Icon(icon, size: 14, color: Colors.white),
                const SizedBox(width: 5),
                Text(
                  label,
                  style: AppTypography.sans(
                    13,
                    FontWeight.w600,
                  ).copyWith(color: Colors.white),
                ),
              ],
            ),
          ),
        );
    return CustomSingleChildLayout(
      delegate: _PopoverLayout(anchor),
      child: TapRegion(
        groupId: _popoverGroup,
        onTapOutside: (_) => _selectParagraph(null),
        // Like the top bar, the pill scales its text at most 1.2×; on a
        // narrow phone the actions wrap, each keeping its 44 pt target.
        child: MediaQuery.withClampedTextScaling(
          maxScaleFactor: 1.2,
          child: V3Pop(
            key: ValueKey(_selectedParagraph),
            child: Container(
              key: const ValueKey('book-paragraph-actions'),
              padding: const EdgeInsets.all(4),
              decoration: BoxDecoration(
                color: AppColors.ink,
                borderRadius: BorderRadius.circular(14),
                boxShadow: const [
                  BoxShadow(
                    color: Color(0x4D000000),
                    blurRadius: 24,
                    offset: Offset(0, 10),
                  ),
                ],
              ),
              child: Wrap(
                alignment: WrapAlignment.center,
                spacing: 2,
                runSpacing: 2,
                children: [
                  action(
                    V3Icons.highlight,
                    'Highlight',
                    () => unawaited(_highlightSelected()),
                  ),
                  action(
                    V3Icons.note,
                    'Note',
                    () => unawaited(_noteSelected()),
                  ),
                  action(
                    V3Icons.quote,
                    'Quote',
                    () => unawaited(_quoteSelected()),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  // ── sheets ────────────────────────────────────────────────────────────────

  void _openOriginal() {
    final url = _resource?.originalReadingUrl;
    if (url == null) return;
    Navigator.of(context, rootNavigator: true).push(
      CmpysPageRoute<void>(
        builder: (_) => MaterialWebScreen(
          title: _resource!.title,
          url: url,
          access: AccessType.original,
        ),
      ),
    );
  }

  Future<void> _showMenu() async {
    final saved = _resource?.isSaved == true;
    final hasOriginal = _resource?.originalReadingUrl != null;
    // Inside the tab shell the reader is a pushed page (no tab bar), and
    // leaving it ends narration: the App menu switches tabs while the
    // reader stays mounted and keeps narrating.
    final openAppMenu = AppShell.appMenuOf(context);
    final action = await showV3Sheet<String>(
      context,
      builder: (sheetContext) {
        final rows = <(V3Icons, String, String)>[
          (V3Icons.list, 'Contents', 'contents'),
          (V3Icons.highlight, 'Notes & highlights · ${_notes.length}', 'notes'),
          (V3Icons.bookmark, saved ? 'Remove from saved' : 'Save book', 'save'),
          if (hasOriginal) (V3Icons.external, 'Read original book', 'original'),
          (V3Icons.type, 'Reading settings', 'settings'),
          if (openAppMenu != null) (V3Icons.home, 'App menu', 'app-menu'),
        ];
        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (final (index, (icon, label, value)) in rows.indexed)
              _sheetRow(
                first: index == 0,
                onTap: () => Navigator.of(sheetContext).pop(value),
                padding: 14,
                child: Row(
                  children: [
                    V3Icon(icon, size: 19, color: AppColors.ink2),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Text(
                        label,
                        style: AppTypography.sans(
                          15.5,
                          FontWeight.w500,
                        ).copyWith(color: AppColors.ink),
                      ),
                    ),
                  ],
                ),
              ),
          ],
        );
      },
    );
    if (!mounted) return;
    switch (action) {
      case 'contents':
        await _showContents();
      case 'notes':
        await _showNotes();
      case 'save':
        await _toggleSaved();
      case 'original':
        _openOriginal();
      case 'settings':
        await showReaderSettingsSheet(context);
      case 'app-menu':
        await openAppMenu?.call();
    }
  }

  Widget _sheetRow({
    required bool first,
    required VoidCallback onTap,
    required double padding,
    required Widget child,
  }) {
    return V3Pressable(
      onTap: onTap,
      pressedScale: 1,
      focusRadius: BorderRadius.circular(8),
      child: Container(
        padding: EdgeInsets.symmetric(vertical: padding),
        decoration: BoxDecoration(
          border: first
              ? null
              : const Border(top: BorderSide(color: AppColors.hair)),
        ),
        child: child,
      ),
    );
  }

  Future<void> _showContents() async {
    final current = _chapterIndex;
    final index = await showV3Sheet<int>(
      context,
      title: 'Contents',
      builder: (sheetContext) => Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var i = 0; i < _chapters.length; i++)
            _sheetRow(
              first: i == 0,
              onTap: () => Navigator.of(sheetContext).pop(i),
              padding: 13,
              child: Row(
                children: [
                  SizedBox(
                    width: 20,
                    child: Text(
                      '${i + 1}',
                      style: AppTypography.sans(12, FontWeight.w700)
                          .merge(AppTypography.tnum)
                          .copyWith(
                            color: i == current
                                ? AppColors.ember
                                : AppColors.ink3,
                          ),
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Text(
                      _chapters[i].title,
                      style: AppTypography.sans(
                        15,
                        i == current ? FontWeight.w600 : FontWeight.w500,
                      ).copyWith(color: AppColors.ink),
                    ),
                  ),
                  if (i < current)
                    const V3Icon(
                      V3Icons.check,
                      size: 15,
                      color: AppColors.sage2,
                    ),
                ],
              ),
            ),
        ],
      ),
    );
    if (index != null && mounted) _goToChapter(index);
  }

  void _goToChapter(int index) {
    if (!_pageController.hasClients) return;
    if (MotionConfig.enabled(context)) {
      unawaited(
        _pageController.animateToPage(
          index,
          duration: const Duration(milliseconds: 260),
          curve: Curves.easeOutCubic,
        ),
      );
    } else {
      _pageController.jumpToPage(index);
    }
  }

  Future<void> _showNotes() async {
    await showV3Sheet<void>(
      context,
      title: 'Notes & highlights',
      builder: (sheetContext) => StatefulBuilder(
        builder: (context, setSheetState) {
          if (_notes.isEmpty) {
            return Text(
              'Tap any paragraph to highlight it or add a note. They’re saved '
              'to this book.',
              style: AppTypography.sans(
                14,
              ).copyWith(color: AppColors.ink2, height: 1.5),
            );
          }
          return Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (final note in _notes)
                _noteRow(note, onDeleted: () => setSheetState(() {})),
            ],
          );
        },
      ),
    );
  }

  Widget _noteRow(ContentHighlight note, {required VoidCallback onDeleted}) {
    final isNote = (note.noteText ?? '').trim().isNotEmpty;
    final chapter = (note.locatorJson?['chapter'] as num?)?.toInt();
    final quote = _normalizedQuote(note.quoteText ?? '');
    final kind = isNote ? 'Note' : 'Highlight';
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12),
      decoration: const BoxDecoration(
        border: Border(top: BorderSide(color: AppColors.hair)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                V3Tag(
                  background: AppColors.goldSoft,
                  color: AppColors.gold2,
                  icon: isNote ? V3Icons.note : V3Icons.highlight,
                  child: Text(
                    chapter == null ? kind : '$kind · Ch. ${chapter + 1}',
                  ),
                ),
                if (quote.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Text(
                    '“${_excerpt(quote, 120)}”',
                    style: AppTypography.read(
                      14.5,
                    ).copyWith(color: AppColors.ink, height: 1.55),
                  ),
                ],
                if (isNote) ...[
                  const SizedBox(height: 6),
                  Text(
                    note.noteText!.trim(),
                    style: AppTypography.sans(
                      14,
                    ).copyWith(color: AppColors.ink2, height: 1.45),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: 8),
          V3IconButton(
            icon: V3Icons.trash,
            size: 36,
            color: AppColors.ink3,
            label: isNote ? 'Delete note' : 'Delete highlight',
            onPressed: () async {
              try {
                await _repository.deleteHighlight(widget.resourceId, note.id);
                if (!mounted) return;
                setState(
                  () => _notes = _notes.where((n) => n.id != note.id).toList(),
                );
                onDeleted();
              } catch (_) {}
            },
          ),
        ],
      ),
    );
  }

  Future<void> _next() async {
    if (_chapterIndex < _chapters.length - 1) {
      if (!MotionConfig.enabled(context)) {
        _pageController.jumpToPage(_chapterIndex + 1);
        return;
      }
      await _pageController.nextPage(
        duration: const Duration(milliseconds: 260),
        curve: Curves.easeOutCubic,
      );
      return;
    }
    await _closeNarration();
    await _persistProgress(completed: true);
    if (!mounted || _readerPopped) return;
    _toast('Book completed', icon: V3Icons.check, success: true);
    _leavingReader = true;
    Navigator.of(context).pop();
  }

  Future<void> _leaveReader({Object? result}) async {
    if (_leavingReader) return;
    _leavingReader = true;
    _narrationCheckpointTimer?.cancel();
    _narrationCheckpointTimer = null;
    final checkpoint = _captureNarrationCheckpoint();
    if (checkpoint != null) _lastNarrationCheckpoint = checkpoint;
    _narrationRun++;
    if (mounted) {
      setState(() {
        _narrationVisible = false;
        _narrationPlaying = false;
        _narrationPreparing = false;
      });
      _syncRemoteDock();
    }
    final stop = _narrator.stop().catchError((_) {});
    // Start progress sync before disposal; the write captures its repository.
    unawaited(_persistProgress());
    if (checkpoint != null) {
      await _queueNarrationCheckpointWrite(
        checkpoint,
        includeActiveResume: false,
      );
    }
    await _clearActiveResume();
    await stop;
    if (!mounted || _readerPopped) return;
    Navigator.of(context).pop(result);
  }

  // ── chrome ────────────────────────────────────────────────────────────────

  /// Design `onScroll`: the chrome hides on scroll-down and comes back on
  /// scroll-up or near the top; any scroll closes the paragraph actions.
  /// Only the reader's own scrolling moves the chrome: narration following
  /// the audio (`ensureVisible`) keeps the baseline but leaves it in place.
  bool _onScroll(ScrollNotification notification) {
    final vertical = notification.metrics.axis == Axis.vertical;
    if (notification is ScrollStartNotification && vertical) {
      _userScroll = notification.dragDetails != null;
      // Re-base on the offset the scroll starts from (a page restored from
      // PageStorage starts mid-chapter), so the first move can't flicker.
      _lastScrollY = notification.metrics.pixels;
    }
    if (notification is! ScrollUpdateNotification) return false;
    if (_selectedParagraph != null) _selectParagraph(null);
    if (!vertical) return false;
    final y = notification.metrics.pixels;
    if (!_userScroll) {
      _lastScrollY = y;
      return false;
    }
    if ((y - _lastScrollY).abs() > 6) {
      final show = y < _lastScrollY || y < 40;
      _lastScrollY = y;
      _chromeVisible.value = show;
    }
    return false;
  }

  Duration _motion(int milliseconds) => MotionConfig.enabled(context)
      ? Duration(milliseconds: milliseconds)
      : Duration.zero;

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(readerSettingsProvider);
    final theme = settings.theme;
    final dark = theme == ReaderTheme.dark;
    final title = (_resource?.title.trim().isNotEmpty ?? false)
        ? _resource!.title
        : widget.fallbackTitle;
    final ready = !_loading && _error == null;
    return NarrationDockPage(
      child: PopScope<Object?>(
        onPopInvokedWithResult: (didPop, result) {
          if (didPop) {
            _readerPopped = true;
            unawaited(_leaveReader(result: result));
          }
        },
        child: AnnotatedRegion<SystemUiOverlayStyle>(
          value: dark ? SystemUiOverlayStyle.light : SystemUiOverlayStyle.dark,
          child: Scaffold(
            backgroundColor: theme.bg,
            body: AnimatedContainer(
              duration: _motion(400),
              color: theme.bg,
              // Landscape: keep clear of the notch and rounded corners.
              child: SafeArea(
                top: false,
                bottom: false,
                child: ready
                    ? _reader(context, title, settings)
                    : Column(
                        children: [
                          V3TopBar(
                            onBack: () => unawaited(_leaveReader()),
                            dark: dark,
                            title: title,
                          ),
                          Expanded(
                            child: _loading
                                ? Center(
                                    child: V3Spinner(
                                      color: dark
                                          ? Colors.white
                                          : AppColors.ink,
                                    ),
                                  )
                                : _errorState(theme),
                          ),
                        ],
                      ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _reader(BuildContext context, String title, ReaderSettings settings) {
    final theme = settings.theme;
    final dark = theme == ReaderTheme.dark;
    final media = MediaQuery.of(context);
    final inShell = AppShell.isWithinShell(context);
    final dockBelow = _chapters.isNotEmpty && _narrationVisible && !inShell;
    final bottomClearance = inShell
        ? AppShell.bottomNavClearance(context)
        : dockBelow
        ? 0.0
        : media.padding.bottom;
    final fabBottom = inShell
        ? bottomClearance + 16
        : math.max(40.0, media.padding.bottom + 16);
    final showListen = !_narrationVisible && _chapters.isNotEmpty;
    final chrome = Positioned(
      left: 0,
      right: 0,
      top: 0,
      // Only the slide listens to the chrome flag, so a flip on scroll
      // doesn't rebuild the page.
      child: ValueListenableBuilder<bool>(
        valueListenable: _chromeVisible,
        builder: (context, visible, bar) => AnimatedSlide(
          key: BookReaderScreen.chromeKey,
          offset: visible ? Offset.zero : const Offset(0, -1),
          duration: _motion(400),
          curve: AppMotion.out,
          child: bar,
        ),
        child: AnimatedContainer(
          duration: _motion(400),
          decoration: BoxDecoration(
            color: theme.bg,
            border: Border(bottom: BorderSide(color: theme.hair)),
          ),
          child: V3TopBar(
            onBack: () => unawaited(_leaveReader()),
            dark: dark,
            title: title,
            sub: _chapters.isEmpty
                ? null
                : 'Chapter ${_chapterIndex + 1} of ${_chapters.length}',
            right: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                V3IconButton(
                  icon: V3Icons.type,
                  dark: dark,
                  label: 'Reading settings',
                  onPressed: () => unawaited(showReaderSettingsSheet(context)),
                ),
                const SizedBox(width: 8),
                V3IconButton(
                  icon: V3Icons.more,
                  dark: dark,
                  label: 'Book menu',
                  onPressed: () => unawaited(_showMenu()),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    final listen = Positioned(
      right: 20,
      bottom: fabBottom,
      child: ValueListenableBuilder<bool>(
        valueListenable: _chromeVisible,
        builder: (context, visible, button) => AnimatedSlide(
          key: BookReaderScreen.listenKey,
          offset: visible ? Offset.zero : Offset(0, (fabBottom + 68) / 52),
          duration: _motion(450),
          curve: AppMotion.out,
          child: button,
        ),
        child: V3Pressable(
          key: const Key('book-listen-button'),
          semanticLabel: 'Listen',
          onTap: () => unawaited(_toggleNarration()),
          child: Container(
            height: 52,
            padding: const EdgeInsets.fromLTRB(16, 0, 20, 0),
            decoration: BoxDecoration(
              color: AppColors.ink,
              borderRadius: BorderRadius.circular(99),
              boxShadow: const [
                BoxShadow(
                  color: Color(0x40000000),
                  blurRadius: 30,
                  offset: Offset(0, 12),
                ),
              ],
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const V3Icon(V3Icons.headphones, size: 19, color: Colors.white),
                const SizedBox(width: 8),
                Text(
                  'Listen',
                  style: AppTypography.sans(
                    15,
                    FontWeight.w600,
                  ).copyWith(color: Colors.white),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    final pages = _chapters.isEmpty
        ? Center(
            child: Padding(
              padding: EdgeInsets.fromLTRB(
                24,
                media.padding.top + 68,
                24,
                bottomClearance + 24,
              ),
              child: Text(
                'This book has no readable material yet.',
                textAlign: TextAlign.center,
                style: AppTypography.sans(15).copyWith(color: theme.fg2),
              ),
            ),
          )
        : NotificationListener<ScrollNotification>(
            onNotification: _onScroll,
            child: PageView.builder(
              controller: _pageController,
              itemCount: _chapters.length,
              onPageChanged: _onChapterChanged,
              itemBuilder: (_, index) => _chapterPage(
                _chapters[index],
                index,
                settings,
                top: media.padding.top + 52 + 16,
                bottom: bottomClearance + (_narrationVisible ? 60 : 100),
              ),
            ),
          );
    return OverlayPortal(
      controller: _popover,
      overlayChildBuilder: _popoverContent,
      child: Column(
        children: [
          Expanded(
            child: Stack(
              children: [
                Positioned.fill(child: pages),
                chrome,
                if (showListen) listen,
              ],
            ),
          ),
          if (dockBelow) SafeArea(top: false, child: _narrationPlayer(theme)),
        ],
      ),
    );
  }

  // ── chapter page ──────────────────────────────────────────────────────────

  Widget _chapterPage(
    BookChapter chapter,
    int index,
    ReaderSettings settings, {
    required double top,
    required double bottom,
  }) {
    final theme = settings.theme;
    final dark = theme == ReaderTheme.dark;
    final fontSize = bookReaderFontSizes[settings.size.clamp(0, 2)];
    final current = index == _chapterIndex;
    final paragraphs = _paragraphsFor(index);
    final marks = _marksFor(index, paragraphs);
    final narratedBlock = _narrationVisible && current
        ? _currentNarrationSegment?.blockIndex
        : null;

    Widget frame(int blockIndex, Widget child) {
      final paragraph = paragraphs[blockIndex];
      final selected = current && _selectedParagraph == blockIndex;
      return _ParagraphFrame(
        key: ValueKey('book-paragraph-$index-$blockIndex'),
        theme: theme,
        tapGroup: _popoverGroup,
        selected: selected,
        mark: marks[blockIndex],
        narrated: narratedBlock == blockIndex,
        onTap: current && paragraph.tappable && paragraph.text.isNotEmpty
            ? (context, tap) => _toggleParagraph(blockIndex, context, tap)
            : null,
        child: child,
      );
    }

    final body =
        _narrationVisible &&
            index < _narrationDocuments.length &&
            _narrationDocuments[index].blocks.isNotEmpty
        ? _NarratedBookMarkdown(
            document: _narrationDocuments[index],
            activeSegmentIndex:
                current &&
                    _narrationPlaying &&
                    !_narrationPreparing &&
                    _narrationWordEnd > _narrationWordStart
                ? _narrationSegmentIndex
                : null,
            activeWordStart: _narrationWordStart,
            activeWordEnd: _narrationWordEnd,
            fontSize: fontSize,
            theme: theme,
            blockKey: (blockIndex) => _narrationBlockKey(index, blockIndex),
            frame: frame,
          )
        : Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (var i = 0; i < paragraphs.length; i++)
                Padding(
                  padding: const EdgeInsets.only(bottom: 16),
                  child: frame(
                    i,
                    CmpysMarkdown(
                      paragraphs[i].markdown,
                      readerTheme: theme,
                      fontSize: fontSize,
                      lineHeight: 1.7,
                    ),
                  ),
                ),
            ],
          );

    final author = _resource?.authorOrCreator?.trim();
    final guide = _resource?.kind == 'llm_book_summary';
    final hasOriginal = _resource?.originalReadingUrl != null;
    const inset = EdgeInsets.symmetric(horizontal: 4);
    return SingleChildScrollView(
      key: PageStorageKey<String>('${widget.resourceId}-$index'),
      padding: EdgeInsets.fromLTRB(20, top, 20, bottom),
      child: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 720),
          child: SelectionArea(
            contextMenuBuilder: _selectionMenu,
            onSelectionChanged: (content) =>
                _selectedQuote = content?.plainText.trim(),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (guide)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(4, 0, 4, 22),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 10,
                      ),
                      decoration: BoxDecoration(
                        color: AppColors.irisSoft,
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Padding(
                            padding: EdgeInsets.only(top: 1),
                            child: V3Icon(
                              V3Icons.info,
                              size: 15,
                              color: AppColors.iris2,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'Study guide written for CMPYS. Not '
                              '${author == null || author.isEmpty ? 'the author' : author}’s '
                              'full text.'
                              '${hasOriginal ? ' The original is available from the menu.' : ''}',
                              style: AppTypography.sans(
                                12.5,
                                FontWeight.w500,
                              ).copyWith(color: AppColors.iris2, height: 1.45),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                V3Rise(
                  duration: const Duration(milliseconds: 500),
                  child: Padding(
                    padding: inset,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'CHAPTER ${index + 1}',
                          style: AppTypography.kick.copyWith(color: theme.fg2),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          chapter.title,
                          style: AppTypography.display(
                            38,
                          ).copyWith(color: theme.fg, height: 1.1),
                        ),
                        const SizedBox(height: 22),
                      ],
                    ),
                  ),
                ),
                body,
                if (current && _narrationApproximate)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(4, 0, 4, 14),
                    child: Row(
                      children: [
                        Container(
                          width: 3,
                          height: 12,
                          decoration: BoxDecoration(
                            color: AppColors.ember,
                            borderRadius: BorderRadius.circular(2),
                          ),
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            'Position follows audio approximately. This voice '
                            'doesn’t provide word timing.',
                            style: AppTypography.sans(
                              11.5,
                            ).copyWith(color: theme.fg2),
                          ),
                        ),
                      ],
                    ),
                  ),
                Padding(
                  padding: inset,
                  child: V3Button(
                    key: ValueKey('book-chapter-next-$index'),
                    kind: dark ? V3ButtonKind.glass : V3ButtonKind.line,
                    full: true,
                    icon: index == _chapters.length - 1 ? V3Icons.check : null,
                    iconRight: index == _chapters.length - 1
                        ? null
                        : V3Icons.arrowR,
                    onPressed: () => unawaited(_next()),
                    child: Text(
                      index == _chapters.length - 1
                          ? 'Finish book'
                          : 'Next: Chapter ${index + 2}',
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// Whether the narration marker is only an estimate: the voice gives no
  /// word timing (design "Position follows audio approximately…").
  ///
  /// The provider is set by a session's first audio event and cleared when
  /// the session ends, so the caption waits for that first event but stays
  /// while the stream buffers mid-playback.
  bool get _narrationApproximate =>
      _narrationVisible &&
      _narrationProvider.trim().isNotEmpty &&
      _narrationAlignmentGranularity != BookNarrationAlignmentGranularity.word;

  Widget _narrationPlayer(ReaderTheme theme) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
          child: BookNarrationDock(controller: _remoteDockController),
        ),
      ),
    );
  }

  Widget _errorState(ReaderTheme theme) {
    final sourceUrl = safeDirectMaterialUrl(widget.fallbackSourceUrl);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            V3Icon(V3Icons.book, size: 42, color: theme.fg2),
            const SizedBox(height: 14),
            Text(
              _error!,
              textAlign: TextAlign.center,
              style: AppTypography.sans(
                15,
              ).copyWith(color: theme.fg, height: 1.45),
            ),
            const SizedBox(height: 18),
            V3Button(
              size: V3Size.md,
              kind: theme == ReaderTheme.dark
                  ? V3ButtonKind.light
                  : V3ButtonKind.dark,
              icon: V3Icons.refresh,
              onPressed: _load,
              child: const Text('Try again'),
            ),
            if (sourceUrl != null) ...[
              const SizedBox(height: 8),
              V3Button(
                size: V3Size.sm,
                kind: theme == ReaderTheme.dark
                    ? V3ButtonKind.glass
                    : V3ButtonKind.ghost,
                icon: V3Icons.external,
                onPressed: () =>
                    Navigator.of(context, rootNavigator: true).push(
                      CmpysPageRoute<void>(
                        builder: (_) => MaterialWebScreen(
                          title: widget.fallbackTitle,
                          url: sourceUrl,
                          access: AccessType.web,
                        ),
                      ),
                    ),
                child: const Text('Open source'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Body text sizes for the shared "A", "A+" and "A++" setting in the book
/// reader (design `fs = [16.5, 18, 20][st.readSize ?? 1]`).
const bookReaderFontSizes = [16.5, 18.0, 20.0];

/// One tappable unit of a chapter page (design `BOOK_TEXT[i]`): its Markdown
/// and the plain text a highlight, note or quote keeps.
@immutable
class BookReaderParagraph {
  const BookReaderParagraph({
    required this.markdown,
    required this.text,
    this.tappable = true,
  });

  final String markdown;

  /// Plain text with whitespace collapsed.
  final String text;

  /// Prose takes Highlight / Note / Quote; headings and figures do not.
  final bool tappable;
}

/// Splits chapter Markdown into its top-level blocks (paragraphs, lists,
/// quotes, tables, fenced figures, headings), so each renders on its own and
/// can be tapped. Fenced blocks stay whole, blank lines inside them included.
@visibleForTesting
List<BookReaderParagraph> bookReaderParagraphs(String markdown) {
  final blocks = <BookReaderParagraph>[];
  final lines = <String>[];
  String? fence;

  void flush({bool tappable = true}) {
    final source = lines.join('\n').trim();
    lines.clear();
    if (source.isEmpty) return;
    final nodes = md.Document(
      extensionSet: md.ExtensionSet.gitHubFlavored,
      encodeHtml: false,
    ).parse(source);
    blocks.add(
      BookReaderParagraph(
        markdown: source,
        text: _normalizedQuote(nodes.map(_plainText).join(' ')),
        tappable: tappable,
      ),
    );
  }

  final fenceOpen = RegExp(r'^(`{3,}|~{3,})');
  final heading = RegExp(r'^#{1,6}(\s|$)');
  for (final line in markdown.split('\n')) {
    final trimmed = line.trimLeft();
    if (fence != null) {
      lines.add(line);
      final close = RegExp(
        '^${RegExp.escape(fence[0])}{${fence.length},}\\s*\$',
      );
      if (close.hasMatch(trimmed)) {
        fence = null;
        flush(tappable: false);
      }
      continue;
    }
    final open = fenceOpen.firstMatch(trimmed);
    if (open != null) {
      flush();
      fence = open.group(1);
      lines.add(line);
      continue;
    }
    if (trimmed.isEmpty) {
      flush();
      continue;
    }
    if (heading.hasMatch(trimmed)) {
      flush();
      lines.add(line);
      flush(tappable: false);
      continue;
    }
    lines.add(line);
  }
  // An unclosed fence still renders (CmpysMarkdown degrades it to a box).
  flush(tappable: fence == null);
  return blocks;
}

String _plainText(md.Node node) {
  if (node is md.Text) return node.text;
  if (node is! md.Element) return node.textContent;
  if (node.tag == 'br') return ' ';
  final children = node.children ?? const <md.Node>[];
  const separated = {
    'ul',
    'ol',
    'li',
    'blockquote',
    'table',
    'thead',
    'tbody',
    'tr',
  };
  return children.map(_plainText).join(separated.contains(node.tag) ? ' ' : '');
}

String _normalizedQuote(String value) =>
    value.replaceAll(RegExp(r'\s+'), ' ').trim();

String _excerpt(String value, int max) =>
    value.length <= max ? value : '${value.substring(0, max).trimRight()}…';

bool _tappableNarrationBlock(BookNarrationBlockKind kind) => switch (kind) {
  BookNarrationBlockKind.paragraph ||
  BookNarrationBlockKind.listItem ||
  BookNarrationBlockKind.quote => true,
  _ => false,
};

enum _ParagraphMark { highlight, note }

/// A paragraph's surface (design `<p className="serif">`): tap to select it
/// for Highlight / Note / Quote, the gold wash once highlighted, the note
/// glyph, and the ember inset that marks the narration position.
class _ParagraphFrame extends StatelessWidget {
  const _ParagraphFrame({
    super.key,
    required this.theme,
    required this.tapGroup,
    required this.selected,
    required this.mark,
    required this.narrated,
    required this.onTap,
    required this.child,
  });

  /// Key on the narration marker (tests).
  static const markerKey = ValueKey('book-narration-marker');

  /// `oklch(0.5 0.1 85 / .28)`, the highlight wash on the dark theme.
  static const _darkHighlight = Color(0x477D5E07);

  final ReaderTheme theme;
  final Object tapGroup;
  final bool selected;
  final _ParagraphMark? mark;
  final bool narrated;

  /// Called with this paragraph's context and the tap's global position.
  final void Function(BuildContext paragraph, Offset globalTap)? onTap;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final dark = theme == ReaderTheme.dark;
    final motion = MotionConfig.enabled(context);
    final background = mark != null
        ? (dark ? _darkHighlight : AppColors.goldSoft)
        : selected
        ? (dark ? const Color(0x0FFFFFFF) : const Color(0x0D17151A))
        : const Color(0x00000000);
    Widget surface = ClipRRect(
      borderRadius: BorderRadius.circular(6),
      child: Stack(
        children: [
          AnimatedContainer(
            duration: motion
                ? const Duration(milliseconds: 300)
                : Duration.zero,
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
            color: background,
            child: child,
          ),
          Positioned(
            left: 0,
            top: 0,
            bottom: 0,
            child: AnimatedOpacity(
              opacity: narrated ? 1 : 0,
              duration: motion
                  ? const Duration(milliseconds: 400)
                  : Duration.zero,
              child: Container(
                key: narrated ? markerKey : null,
                width: 3,
                color: AppColors.ember,
              ),
            ),
          ),
        ],
      ),
    );
    if (mark == _ParagraphMark.note) {
      surface = Stack(
        clipBehavior: Clip.none,
        children: [
          surface,
          const Positioned(
            right: -16,
            top: 4,
            child: V3Icon(
              key: BookReaderScreen.noteGlyphKey,
              V3Icons.note,
              size: 14,
              color: AppColors.gold2,
            ),
          ),
        ],
      );
    }
    final tap = onTap;
    if (tap == null) return surface;
    return TapRegion(
      groupId: tapGroup,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapUp: (details) => tap(context, details.globalPosition),
        child: surface,
      ),
    );
  }
}

/// Where the paragraph actions may go, in the overlay's coordinates.
@immutable
class _PopoverAnchor {
  const _PopoverAnchor({
    required this.paragraph,
    required this.tapY,
    required this.top,
    required this.bottom,
  });

  /// The tapped paragraph.
  final Rect paragraph;

  /// The tap's vertical position, inside [paragraph].
  final double tapY;

  /// The visible band: below the chrome, above the bottom bars.
  final double top;
  final double bottom;

  @override
  bool operator ==(Object other) =>
      other is _PopoverAnchor &&
      other.paragraph == paragraph &&
      other.tapY == tapY &&
      other.top == top &&
      other.bottom == bottom;

  @override
  int get hashCode => Object.hash(paragraph, tapY, top, bottom);
}

/// Places the actions above the paragraph as the design does (`top: -46`,
/// centred) when that is visible; otherwise below the tap point, or above
/// it near the bottom; always clamped into the visible band and 16 pt from
/// the sides. The actions close on any scroll, so the place is fixed.
class _PopoverLayout extends SingleChildLayoutDelegate {
  const _PopoverLayout(this.anchor);

  final _PopoverAnchor anchor;

  @override
  BoxConstraints getConstraintsForChild(BoxConstraints constraints) =>
      BoxConstraints(
        maxWidth: math.max(0, constraints.maxWidth - 32),
        maxHeight: constraints.maxHeight,
      );

  @override
  Offset getPositionForChild(Size size, Size childSize) {
    final a = anchor;
    final above = a.paragraph.top - 6 - childSize.height;
    final double y;
    if (above >= a.top) {
      y = above;
    } else if (a.tapY + 16 + childSize.height <= a.bottom) {
      y = a.tapY + 16;
    } else {
      y = a.tapY - 16 - childSize.height;
    }
    final x = a.paragraph.center.dx - childSize.width / 2;
    return Offset(
      x.clamp(16, math.max(16, size.width - 16 - childSize.width)).toDouble(),
      y.clamp(a.top, math.max(a.top, a.bottom - childSize.height)).toDouble(),
    );
  }

  @override
  bool shouldRelayout(_PopoverLayout oldDelegate) =>
      oldDelegate.anchor != anchor;
}

class _NarratedBookMarkdown extends StatelessWidget {
  const _NarratedBookMarkdown({
    required this.document,
    required this.activeSegmentIndex,
    required this.activeWordStart,
    required this.activeWordEnd,
    required this.fontSize,
    required this.theme,
    required this.blockKey,
    required this.frame,
  });

  final BookNarrationDocument document;
  final int? activeSegmentIndex;
  final int activeWordStart;
  final int activeWordEnd;
  final double fontSize;
  final ReaderTheme theme;
  final GlobalKey Function(int blockIndex) blockKey;

  /// Wraps a block in its paragraph surface.
  final Widget Function(int blockIndex, Widget child) frame;

  bool get _dark => theme == ReaderTheme.dark;

  BookNarrationSegment? get _activeSegment {
    final index = activeSegmentIndex;
    if (index == null || index < 0 || index >= document.segments.length) {
      return null;
    }
    return document.segments[index];
  }

  @override
  Widget build(BuildContext context) {
    final activeSegment = _activeSegment;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var index = 0; index < document.blocks.length; index++)
          _block(document.blocks[index], index, activeSegment),
      ],
    );
  }

  Widget _block(
    BookNarrationBlock block,
    int blockIndex,
    BookNarrationSegment? activeSegment,
  ) {
    final isActive = activeSegment?.blockIndex == blockIndex;
    final text = Text.rich(
      TextSpan(children: _textSpans(block, activeSegment)),
      style: _baseStyle(block),
    );

    Widget content = switch (block.kind) {
      BookNarrationBlockKind.diagram => LearningDiagramView(
        diagram: block.diagram!,
        fontSize: fontSize,
        dark: _dark,
        spansForRange: (start, end) =>
            _textSpans(block, activeSegment, rangeStart: start, rangeEnd: end),
      ),
      BookNarrationBlockKind.comparison => LearningComparisonView(
        comparison: block.comparison!,
        fontSize: fontSize,
        dark: _dark,
        spansForRange: (start, end) =>
            _textSpans(block, activeSegment, rangeStart: start, rangeEnd: end),
      ),
      BookNarrationBlockKind.listItem => Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 27,
            child: Text(
              block.listMarker ?? '•',
              style: AppTypography.read(fontSize).copyWith(
                color: isActive ? AppColors.ember : theme.fg2,
                height: 1.7,
              ),
            ),
          ),
          Expanded(child: text),
        ],
      ),
      BookNarrationBlockKind.quote => Container(
        padding: const EdgeInsets.fromLTRB(14, 11, 14, 11),
        decoration: BoxDecoration(
          color: theme.card,
          borderRadius: AppRadii.br12,
        ),
        child: text,
      ),
      BookNarrationBlockKind.code => Container(
        padding: const EdgeInsets.all(13),
        decoration: BoxDecoration(
          color: theme.card,
          borderRadius: AppRadii.br12,
        ),
        child: text,
      ),
      _ => text,
    };

    if (isActive) {
      content = Semantics(
        label: 'Currently reading: ${activeSegment!.text}',
        child: content,
      );
    }

    return Padding(
      key: blockKey(blockIndex),
      padding: EdgeInsets.only(
        top: block.kind == BookNarrationBlockKind.heading ? 13 : 0,
        bottom: switch (block.kind) {
          BookNarrationBlockKind.heading => 7,
          BookNarrationBlockKind.listItem => 7,
          _ => 14,
        },
      ),
      child: frame(blockIndex, content),
    );
  }

  TextStyle _baseStyle(BookNarrationBlock block) {
    return switch (block.kind) {
      BookNarrationBlockKind.heading =>
        block.headingLevel <= 3
            ? AppTypography.h3.copyWith(
                color: theme.fg,
                fontSize: fontSize + 3,
                height: 1.32,
              )
            : AppTypography.h4.copyWith(
                color: theme.fg,
                fontSize: fontSize + 1,
                height: 1.38,
              ),
      BookNarrationBlockKind.quote => AppTypography.readingQuote.copyWith(
        color: theme.fg,
        fontSize: fontSize + .5,
        height: 1.55,
      ),
      BookNarrationBlockKind.code => AppTypography.monoLabel.copyWith(
        color: theme.fg,
        fontSize: (fontSize - 2).clamp(13, 21).toDouble(),
        height: 1.55,
      ),
      _ => AppTypography.read(fontSize).copyWith(color: theme.fg, height: 1.7),
    };
  }

  List<InlineSpan> _textSpans(
    BookNarrationBlock block,
    BookNarrationSegment? activeSegment, {
    int? rangeStart,
    int? rangeEnd,
  }) {
    final boundaries = <int>{0, block.text.length};
    final blockSegments = document.segments
        .skip(block.firstSegmentIndex)
        .take(block.segmentCount);
    for (final segment in blockSegments) {
      boundaries
        ..add(segment.start)
        ..add(segment.end);
    }

    int? wordStart;
    int? wordEnd;
    if (activeSegment != null &&
        activeSegment.index >= block.firstSegmentIndex &&
        activeSegment.index < block.firstSegmentIndex + block.segmentCount) {
      wordStart = (activeSegment.start + activeWordStart)
          .clamp(activeSegment.start, activeSegment.end)
          .toInt();
      wordEnd = (activeSegment.start + activeWordEnd)
          .clamp(wordStart, activeSegment.end)
          .toInt();
      boundaries
        ..add(wordStart)
        ..add(wordEnd);
    }

    if (rangeStart != null) boundaries.add(rangeStart);
    if (rangeEnd != null) boundaries.add(rangeEnd);
    final ordered =
        boundaries
            .where(
              (value) =>
                  value >= (rangeStart ?? 0) &&
                  value <= (rangeEnd ?? block.text.length),
            )
            .toList()
          ..sort();
    final spans = <InlineSpan>[];
    for (var index = 0; index < ordered.length - 1; index++) {
      final start = ordered[index];
      final end = ordered[index + 1];
      if (start == end) continue;
      final inActiveSentence =
          activeSegment != null &&
          activeSegment.index >= block.firstSegmentIndex &&
          activeSegment.index < block.firstSegmentIndex + block.segmentCount &&
          start >= activeSegment.start &&
          end <= activeSegment.end;
      final inActiveWord =
          wordStart != null &&
          wordEnd != null &&
          wordStart < wordEnd &&
          start >= wordStart &&
          end <= wordEnd;
      TextStyle? style;
      if (inActiveSentence) {
        style = TextStyle(
          backgroundColor: _dark
              ? AppColors.ember.withValues(alpha: .22)
              : AppColors.emberSoft,
        );
      }
      if (inActiveWord) {
        style = (style ?? const TextStyle()).copyWith(
          color: Colors.white,
          backgroundColor: AppColors.ember,
          fontWeight: FontWeight.w700,
        );
      }
      spans.add(TextSpan(text: block.text.substring(start, end), style: style));
    }
    return spans;
  }
}

/// The "Add a note" sheet body: the quoted passage, "Your thought", and
/// "Save note". It pops with the saved highlight.
@visibleForTesting
class BookNoteComposerSheet extends StatefulWidget {
  const BookNoteComposerSheet({
    super.key,
    required this.quote,
    required this.onSave,
  });

  final String quote;
  final Future<ContentHighlight> Function(String noteText) onSave;

  @override
  State<BookNoteComposerSheet> createState() => _BookNoteComposerSheetState();
}

class _BookNoteComposerSheetState extends State<BookNoteComposerSheet> {
  late final TextEditingController _noteController;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _noteController = TextEditingController();
  }

  @override
  void dispose() {
    _noteController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_saving || _noteController.text.trim().isEmpty) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final created = await widget.onSave(_noteController.text);
      if (!mounted) return;
      Navigator.of(context).pop(created);
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = 'Couldn’t save this note. Please try again.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final quote = _normalizedQuote(widget.quote);
    return PopScope(
      canPop: !_saving,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.only(left: 12),
            decoration: const BoxDecoration(
              border: Border(left: BorderSide(color: AppColors.gold, width: 3)),
            ),
            child: Text(
              '“${_excerpt(quote, 110)}”',
              style: AppTypography.read(
                14,
              ).copyWith(color: AppColors.ink2, height: 1.5),
            ),
          ),
          const SizedBox(height: 14),
          V3Field(
            controller: _noteController,
            multiline: true,
            rows: 3,
            placeholder: 'Your thought',
            autofocus: true,
            enabled: !_saving,
            textCapitalization: TextCapitalization.sentences,
            onChanged: (_) => setState(() {}),
          ),
          if (_error != null) ...[
            const SizedBox(height: 10),
            Text(
              _error!,
              style: AppTypography.sans(
                13,
                FontWeight.w500,
              ).copyWith(color: AppColors.danger),
            ),
          ],
          const SizedBox(height: 14),
          V3Button(
            full: true,
            loading: _saving,
            disabled: _noteController.text.trim().isEmpty,
            onPressed: () => unawaited(_save()),
            child: const Text('Save note'),
          ),
        ],
      ),
    );
  }
}
