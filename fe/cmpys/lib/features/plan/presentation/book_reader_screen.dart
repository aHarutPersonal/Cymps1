import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/design_tokens.dart';
import '../../../core/ui/cmpys/cmpys_markdown.dart';
import '../../../core/ui/cmpys/cmpys_primitives.dart';
import '../../session/data/content_resources_repository.dart';
import '../../session/models/content_resource.dart';
import '../models/plan_models.dart';
import 'book_narration.dart';

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
    this.narrator,
  });

  final String resourceId;
  final String fallbackTitle;
  final BookNarrator? narrator;

  @override
  ConsumerState<BookReaderScreen> createState() => _BookReaderScreenState();
}

class _BookReaderScreenState extends ConsumerState<BookReaderScreen> {
  PageController _pageController = PageController();
  late final BookNarrator _narrator;
  ContentResource? _resource;
  List<BookChapter> _chapters = const [];
  List<BookNarrationDocument> _narrationDocuments = const [];
  List<ContentHighlight> _notes = const [];
  int _chapterIndex = 0;
  double _fontSize = 18;
  int _readingTheme = 0;
  String? _selectedQuote;
  bool _loading = true;
  bool _savingBook = false;
  String? _error;

  bool _narrationVisible = false;
  bool _narrationPlaying = false;
  bool _narrationPreparing = false;
  bool _narrationFinished = false;
  bool _narratorReady = false;
  bool _narrationChangingChapter = false;
  int _narrationRun = 0;
  int? _narrationSegmentIndex;
  int _narrationWordStart = 0;
  int _narrationWordEnd = 0;
  int _narrationResumeOffset = 0;
  int _speechBaseOffset = 0;
  double _narrationSpeed = 1;
  final Map<String, GlobalKey> _narrationBlockKeys = {};

  ContentResourcesRepository get _repository =>
      ref.read(contentResourcesRepositoryProvider);

  Color get _background => switch (_readingTheme) {
    1 => const Color(0xFFF7F0E3),
    2 => const Color(0xFF1B1C21),
    _ => const Color(0xFFFAFAF8),
  };

  Color get _ink =>
      _readingTheme == 2 ? const Color(0xFFF2F0EA) : AppColors.ink;

  Color get _muted =>
      _readingTheme == 2 ? const Color(0xFFA8A8B2) : AppColors.ink3;

  Color get _chrome =>
      _readingTheme == 2 ? const Color(0xFF25262D) : Colors.white;

  @override
  void initState() {
    super.initState();
    _narrator = widget.narrator ?? SystemBookNarrator();
    _narrator.setProgressHandler(_onNarrationProgress);
    _narrator.setErrorHandler(_onNarrationError);
    _load();
  }

  @override
  void dispose() {
    _narrationRun++;
    _narrator.setProgressHandler(null);
    _narrator.setErrorHandler(null);
    unawaited(_narrator.dispose());
    _pageController.dispose();
    super.dispose();
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
      ]);
      final resource = results[0] as ContentResource;
      final notes = results[1] as List<ContentHighlight>;
      final markdown = resource.contentMarkdown?.trim() ?? '';
      final chapters = markdown.isEmpty
          ? <BookChapter>[]
          : splitBookChapters(resource.contentMarkdown!);
      final narrationDocuments = chapters
          .map(
            (chapter) => BookNarrationDocument.fromMarkdown(chapter.markdown),
          )
          .toList(growable: false);
      var initialChapter = (resource.cursorJson?['chapter'] as num?)?.toInt();
      if (initialChapter == null && chapters.isNotEmpty) {
        initialChapter = ((resource.progressPercent / 100) * chapters.length)
            .floor();
      }
      initialChapter = chapters.isEmpty
          ? 0
          : (initialChapter ?? 0).clamp(0, chapters.length - 1).toInt();

      if (!mounted) return;
      _pageController.dispose();
      _pageController = PageController(initialPage: initialChapter);
      setState(() {
        _resource = resource;
        _chapters = chapters;
        _narrationDocuments = narrationDocuments;
        _narrationBlockKeys.clear();
        _notes = notes;
        _chapterIndex = initialChapter!;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error =
            'Couldn’t open this book. Check your connection and try again.';
      });
    }
  }

  int get _progressPercent {
    if (_chapters.isEmpty) return 0;
    return ((_chapterIndex / _chapters.length) * 100).round();
  }

  Future<void> _persistProgress({bool completed = false}) async {
    if (_chapters.isEmpty) return;
    final progress = completed ? 100 : _progressPercent;
    try {
      await _repository.updateProgress(
        widget.resourceId,
        progressPercent: progress,
        completed: completed,
        cursorJson: {
          'chapter': _chapterIndex,
          'chapterTitle': _chapters[_chapterIndex].title,
        },
      );
    } catch (_) {
      // Reading must remain uninterrupted when a background sync misses.
    }
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
      _narrationResumeOffset = wordStart;
    });
  }

  void _onNarrationError(Object _) {
    if (!mounted || (!_narrationPlaying && !_narrationPreparing)) return;
    _narrationRun++;
    setState(() {
      _narrationPlaying = false;
      _narrationPreparing = false;
    });
    _toast('Narration paused. Try playing it again.');
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

    final run = ++_narrationRun;
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
      _toast('Narration isn’t available on this device.');
      return;
    }

    if (!mounted || run != _narrationRun) return;
    setState(() {
      _narrationPreparing = false;
      _narrationPlaying = true;
    });
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

      try {
        await _narrator.speak(segment.text.substring(offset));
      } catch (_) {
        if (!mounted || run != _narrationRun) return;
        setState(() => _narrationPlaying = false);
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
    _narrationRun++;
    if (mounted) {
      setState(() {
        _narrationPlaying = false;
        _narrationPreparing = false;
        if (_narrationWordStart > 0) {
          _narrationResumeOffset = _narrationWordStart;
        }
      });
    }
    try {
      await _narrator.stop();
    } catch (_) {}
  }

  Future<void> _closeNarration() async {
    _narrationRun++;
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
      });
    }
    try {
      await _narrator.stop();
    } catch (_) {}
  }

  Future<void> _skipNarration(int direction) async {
    final currentDocument = _currentNarrationDocument;
    if (currentDocument == null || currentDocument.segments.isEmpty) return;
    final continuePlaying = _narrationPlaying;
    _narrationRun++;
    setState(() {
      _narrationPlaying = false;
      _narrationPreparing = false;
      _narrationFinished = false;
    });
    try {
      await _narrator.stop();
    } catch (_) {}

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
    final targetDocument = _narrationDocuments[chapter];
    if (targetDocument.segments.isEmpty) return;
    segment = segment.clamp(0, targetDocument.segments.length - 1).toInt();

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
      _narrationResumeOffset = 0;
      _narrationWordStart = 0;
      _narrationWordEnd = 0;
    });
    _revealNarrationSegment();
    if (continuePlaying) unawaited(_playNarration());
  }

  Future<void> _changeNarrationSpeed(double speed) async {
    if (_narrationSpeed == speed) return;
    final continuePlaying = _narrationPlaying;
    _narrationRun++;
    setState(() {
      _narrationSpeed = speed;
      _narrationPlaying = false;
      _narrationPreparing = false;
    });
    try {
      await _narrator.stop();
      if (_narratorReady) await _narrator.setSpeed(speed);
    } catch (_) {}
    if (continuePlaying && mounted) unawaited(_playNarration());
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
    final continuePlaying = _narrationPlaying;
    setState(() {
      _chapterIndex = index;
      _selectedQuote = null;
      if (!narrationControlled && _narrationVisible) {
        _narrationSegmentIndex = 0;
        _narrationResumeOffset = 0;
        _narrationWordStart = 0;
        _narrationWordEnd = 0;
        _narrationPlaying = false;
        _narrationFinished = false;
      }
    });
    if (!narrationControlled && _narrationVisible) {
      _narrationRun++;
      unawaited(_restartNarrationAfterChapterChange(continuePlaying));
    }
    unawaited(_persistProgress());
  }

  Future<void> _restartNarrationAfterChapterChange(bool continuePlaying) async {
    try {
      await _narrator.stop();
    } catch (_) {}
    if (continuePlaying && mounted) unawaited(_playNarration());
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
      _toast(wasSaved ? 'Removed from saved' : 'Saved to your library');
    } catch (_) {
      if (mounted) _toast('Couldn’t update your library');
    } finally {
      if (mounted) setState(() => _savingBook = false);
    }
  }

  void _toast(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(message),
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 2),
        ),
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
    final created = await showModalBottomSheet<ContentHighlight>(
      context: context,
      isScrollControlled: true,
      backgroundColor: _chrome,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (sheetContext) => BookNoteComposerSheet(
        quote: quote,
        background: _background,
        chrome: _chrome,
        ink: _ink,
        muted: _muted,
        dark: _readingTheme == 2,
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
    _toast('Note saved');
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

  Future<void> _showContents() async {
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: _chrome,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (sheetContext) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(18, 14, 18, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _sheetHandle(),
              const SizedBox(height: 18),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: Text(
                  'Contents',
                  style: AppTypography.h2.copyWith(color: _ink, fontSize: 23),
                ),
              ),
              const SizedBox(height: 12),
              Expanded(
                child: ListView.separated(
                  itemCount: _chapters.length,
                  separatorBuilder: (context, index) =>
                      Divider(height: 1, color: _muted.withValues(alpha: 0.18)),
                  itemBuilder: (_, index) => ListTile(
                    contentPadding: const EdgeInsets.symmetric(horizontal: 4),
                    leading: Container(
                      width: 32,
                      height: 32,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: index == _chapterIndex
                            ? AppColors.green
                            : _muted.withValues(alpha: 0.12),
                        shape: BoxShape.circle,
                      ),
                      child: Text(
                        '${index + 1}',
                        style: AppTypography.captionMedium.copyWith(
                          color: index == _chapterIndex ? Colors.white : _muted,
                        ),
                      ),
                    ),
                    title: Text(
                      _chapters[index].title,
                      style: AppTypography.bodyMedium.copyWith(
                        color: _ink,
                        fontWeight: index == _chapterIndex
                            ? FontWeight.w700
                            : FontWeight.w500,
                      ),
                    ),
                    trailing: index < _chapterIndex
                        ? const Icon(
                            Icons.check_rounded,
                            color: AppColors.green,
                            size: 18,
                          )
                        : null,
                    onTap: () {
                      Navigator.of(sheetContext).pop();
                      _pageController.animateToPage(
                        index,
                        duration: const Duration(milliseconds: 260),
                        curve: Curves.easeOutCubic,
                      );
                    },
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _showReaderSettings() async {
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: _chrome,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (context) => StatefulBuilder(
        builder: (context, setSheetState) => SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(22, 14, 22, 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _sheetHandle(),
                const SizedBox(height: 20),
                Text(
                  'Reading settings',
                  style: AppTypography.h2.copyWith(color: _ink, fontSize: 23),
                ),
                const SizedBox(height: 20),
                Row(
                  children: [
                    Text(
                      'A',
                      style: AppTypography.reading.copyWith(
                        fontSize: 15,
                        color: _ink,
                      ),
                    ),
                    Expanded(
                      child: Slider(
                        value: _fontSize,
                        min: 15,
                        max: 23,
                        divisions: 8,
                        activeColor: AppColors.green,
                        onChanged: (value) {
                          setState(() => _fontSize = value);
                          setSheetState(() {});
                        },
                      ),
                    ),
                    Text(
                      'A',
                      style: AppTypography.reading.copyWith(
                        fontSize: 24,
                        color: _ink,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    _themeChoice(
                      0,
                      const Color(0xFFFAFAF8),
                      'Light',
                      setSheetState,
                    ),
                    const SizedBox(width: 10),
                    _themeChoice(
                      1,
                      const Color(0xFFF7F0E3),
                      'Warm',
                      setSheetState,
                    ),
                    const SizedBox(width: 10),
                    _themeChoice(
                      2,
                      const Color(0xFF1B1C21),
                      'Dark',
                      setSheetState,
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _themeChoice(
    int value,
    Color color,
    String label,
    StateSetter setSheetState,
  ) {
    final selected = _readingTheme == value;
    return Expanded(
      child: GestureDetector(
        onTap: () {
          setState(() => _readingTheme = value);
          setSheetState(() {});
        },
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 12),
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: selected ? AppColors.green : _muted.withValues(alpha: .2),
              width: selected ? 2 : 1,
            ),
          ),
          child: Text(
            label,
            textAlign: TextAlign.center,
            style: AppTypography.captionMedium.copyWith(
              color: value == 2 ? Colors.white : AppColors.ink,
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _showNotes() async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: _chrome,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (sheetContext) => StatefulBuilder(
        builder: (context, setSheetState) => FractionallySizedBox(
          heightFactor: .78,
          child: SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(18, 14, 18, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _sheetHandle(),
                  const SizedBox(height: 18),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          'Notes & highlights',
                          style: AppTypography.h2.copyWith(
                            color: _ink,
                            fontSize: 23,
                          ),
                        ),
                      ),
                      Text(
                        '${_notes.length}',
                        style: AppTypography.kicker.copyWith(color: _muted),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  Expanded(
                    child: _notes.isEmpty
                        ? Center(
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 30,
                              ),
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    Icons.draw_outlined,
                                    color: _muted,
                                    size: 32,
                                  ),
                                  const SizedBox(height: 10),
                                  Text(
                                    'Select any passage to add a note.',
                                    textAlign: TextAlign.center,
                                    style: AppTypography.body.copyWith(
                                      color: _muted,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          )
                        : ListView.separated(
                            itemCount: _notes.length,
                            separatorBuilder: (context, index) =>
                                const SizedBox(height: 10),
                            itemBuilder: (_, index) {
                              final note = _notes[index];
                              return Container(
                                padding: const EdgeInsets.all(15),
                                decoration: BoxDecoration(
                                  color: _background,
                                  borderRadius: BorderRadius.circular(18),
                                  border: Border.all(
                                    color: _muted.withValues(alpha: .14),
                                  ),
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    if ((note.quoteText ?? '').isNotEmpty)
                                      Text(
                                        '“${note.quoteText}”',
                                        maxLines: 4,
                                        overflow: TextOverflow.ellipsis,
                                        style: AppTypography.readingQuote
                                            .copyWith(
                                              color: _ink,
                                              fontSize: 14.5,
                                              height: 1.4,
                                            ),
                                      ),
                                    if ((note.noteText ?? '').isNotEmpty) ...[
                                      const SizedBox(height: 10),
                                      Text(
                                        note.noteText!,
                                        style: AppTypography.body.copyWith(
                                          color: _ink,
                                          height: 1.45,
                                        ),
                                      ),
                                    ],
                                    const SizedBox(height: 8),
                                    Row(
                                      children: [
                                        Expanded(
                                          child: Text(
                                            note.locatorJson?['chapterTitle']
                                                    ?.toString() ??
                                                'Book note',
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: AppTypography.caption
                                                .copyWith(color: _muted),
                                          ),
                                        ),
                                        IconButton(
                                          visualDensity: VisualDensity.compact,
                                          onPressed: () async {
                                            try {
                                              await _repository.deleteHighlight(
                                                widget.resourceId,
                                                note.id,
                                              );
                                              if (!mounted) return;
                                              setState(
                                                () => _notes = _notes
                                                    .where(
                                                      (n) => n.id != note.id,
                                                    )
                                                    .toList(),
                                              );
                                              setSheetState(() {});
                                            } catch (_) {}
                                          },
                                          icon: Icon(
                                            Icons.delete_outline,
                                            color: _muted,
                                            size: 19,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                              );
                            },
                          ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _sheetHandle() => Center(
    child: Container(
      width: 38,
      height: 4,
      decoration: BoxDecoration(
        color: _muted.withValues(alpha: .35),
        borderRadius: BorderRadius.circular(99),
      ),
    ),
  );

  Future<void> _next() async {
    if (_chapterIndex < _chapters.length - 1) {
      await _pageController.nextPage(
        duration: const Duration(milliseconds: 260),
        curve: Curves.easeOutCubic,
      );
      return;
    }
    await _closeNarration();
    await _persistProgress(completed: true);
    if (!mounted) return;
    _toast('Book completed');
    Navigator.of(context).maybePop();
  }

  @override
  Widget build(BuildContext context) {
    final title = (_resource?.title.trim().isNotEmpty ?? false)
        ? _resource!.title
        : widget.fallbackTitle;
    return Scaffold(
      backgroundColor: _background,
      body: SafeArea(
        child: _loading
            ? const Center(
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: AppColors.green,
                ),
              )
            : _error != null
            ? _errorState()
            : Column(
                children: [
                  _topBar(title),
                  LinearProgressIndicator(
                    value: _progressPercent / 100,
                    minHeight: 3,
                    backgroundColor: _muted.withValues(alpha: .12),
                    valueColor: const AlwaysStoppedAnimation<Color>(
                      AppColors.green,
                    ),
                  ),
                  Expanded(
                    child: _chapters.isEmpty
                        ? Center(
                            child: Text(
                              'This book has no readable material yet.',
                              style: AppTypography.body.copyWith(color: _muted),
                            ),
                          )
                        : PageView.builder(
                            controller: _pageController,
                            itemCount: _chapters.length,
                            onPageChanged: _onChapterChanged,
                            itemBuilder: (_, index) =>
                                _chapterPage(_chapters[index], index),
                          ),
                  ),
                  if (_chapters.isNotEmpty && _narrationVisible)
                    _narrationPlayer(),
                  if (_chapters.isNotEmpty) _bottomBar(),
                ],
              ),
      ),
    );
  }

  Widget _topBar(String title) {
    final chapterTitle = _chapters.isEmpty
        ? 'Book guide'
        : _chapters[_chapterIndex].title;
    return Padding(
      padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
      child: Row(
        children: [
          _circleButton(Icons.chevron_left_rounded, () {
            _narrationRun++;
            unawaited(_narrator.stop());
            Navigator.of(context).maybePop();
          }),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTypography.label.copyWith(
                    color: _ink,
                    fontSize: 13.5,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  chapterTitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTypography.caption.copyWith(
                    color: _muted,
                    fontSize: 11.5,
                  ),
                ),
              ],
            ),
          ),
          _circleButton(Icons.format_size_rounded, _showReaderSettings),
          const SizedBox(width: 5),
          _circleButton(
            _resource?.isSaved == true
                ? Icons.bookmark_rounded
                : Icons.bookmark_border_rounded,
            _toggleSaved,
            active: _resource?.isSaved == true,
          ),
        ],
      ),
    );
  }

  Widget _circleButton(
    IconData icon,
    VoidCallback onTap, {
    bool active = false,
  }) {
    return IconButton(
      onPressed: onTap,
      visualDensity: VisualDensity.compact,
      style: IconButton.styleFrom(
        backgroundColor: _chrome,
        side: BorderSide(color: _muted.withValues(alpha: .15)),
      ),
      icon:
          _savingBook &&
              (icon == Icons.bookmark_rounded ||
                  icon == Icons.bookmark_border_rounded)
          ? const SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : Icon(icon, size: 20, color: active ? AppColors.green : _muted),
    );
  }

  Widget _chapterPage(BookChapter chapter, int index) {
    final author = _resource?.authorOrCreator?.trim();
    return SingleChildScrollView(
      key: PageStorageKey<String>('${widget.resourceId}-$index'),
      padding: const EdgeInsets.fromLTRB(24, 30, 24, 52),
      child: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 720),
          child: SelectionArea(
            contextMenuBuilder: _selectionMenu,
            onSelectionChanged: (content) =>
                _selectedQuote = content?.plainText.trim(),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'CHAPTER ${(index + 1).toString().padLeft(2, '0')} '
                  'OF ${_chapters.length.toString().padLeft(2, '0')}',
                  style: AppTypography.kicker.copyWith(
                    color: AppColors.green,
                    fontSize: 10.5,
                  ),
                ),
                const SizedBox(height: 13),
                Text(
                  chapter.title,
                  style: AppTypography.h1.copyWith(
                    color: _ink,
                    fontSize: 30,
                    height: 1.16,
                    letterSpacing: -.5,
                  ),
                ),
                if (index == 0 && author != null && author.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  Text(
                    'A practical reading of $author',
                    style: AppTypography.captionMedium.copyWith(
                      color: _muted,
                      fontSize: 13,
                    ),
                  ),
                ],
                const SizedBox(height: 24),
                if (_narrationVisible &&
                    index < _narrationDocuments.length &&
                    _narrationDocuments[index].blocks.isNotEmpty)
                  _NarratedBookMarkdown(
                    document: _narrationDocuments[index],
                    activeSegmentIndex: index == _chapterIndex
                        ? _narrationSegmentIndex
                        : null,
                    activeWordStart: _narrationWordStart,
                    activeWordEnd: _narrationWordEnd,
                    fontSize: _fontSize,
                    ink: _ink,
                    muted: _muted,
                    dark: _readingTheme == 2,
                    blockKey: (blockIndex) =>
                        _narrationBlockKey(index, blockIndex),
                  )
                else
                  CmpysMarkdown(
                    chapter.markdown,
                    onDark: _readingTheme == 2,
                    fontSize: _fontSize,
                    lineHeight: 1.72,
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _narrationPlayer() {
    final document = _currentNarrationDocument;
    final segment = _currentNarrationSegment;
    final segmentCount = document?.segments.length ?? 0;
    final segmentIndex = (_narrationSegmentIndex ?? 0)
        .clamp(0, segmentCount == 0 ? 0 : segmentCount - 1)
        .toInt();
    final progress = segmentCount == 0
        ? 0.0
        : ((segmentIndex + 1) / segmentCount).clamp(0.0, 1.0);
    final currentText =
        segment?.text ??
        (_narrationPreparing
            ? 'Preparing the system voice…'
            : 'Ready to listen');
    final speedLabel = _narrationSpeed == _narrationSpeed.roundToDouble()
        ? '${_narrationSpeed.toInt()}×'
        : '${_narrationSpeed.toStringAsFixed(2).replaceFirst(RegExp(r'0$'), '')}×';

    return Container(
      key: const Key('book-narration-player'),
      decoration: BoxDecoration(
        color: _chrome,
        border: Border(top: BorderSide(color: _muted.withValues(alpha: .13))),
      ),
      padding: const EdgeInsets.fromLTRB(14, 10, 10, 10),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 34,
                height: 34,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: AppColors.greenSoft.withValues(
                    alpha: _readingTheme == 2 ? .16 : .8,
                  ),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  _narrationPlaying
                      ? Icons.graphic_eq_rounded
                      : Icons.headphones_rounded,
                  color: AppColors.green,
                  size: 19,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'LISTENING · CHAPTER ${_chapterIndex + 1} OF ${_chapters.length}',
                      style: AppTypography.kicker.copyWith(
                        color: AppColors.green,
                        fontSize: 9.5,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Semantics(
                      liveRegion: true,
                      label: 'Now reading: $currentText',
                      child: ExcludeSemantics(
                        child: Text(
                          currentText,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: AppTypography.captionMedium.copyWith(
                            color: _ink,
                            fontSize: 12.5,
                            height: 1.3,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                key: const Key('book-narration-close'),
                tooltip: 'Close listening controls',
                onPressed: () => unawaited(_closeNarration()),
                visualDensity: VisualDensity.compact,
                icon: Icon(Icons.close_rounded, color: _muted, size: 19),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              PopupMenuButton<double>(
                key: const Key('book-narration-speed'),
                tooltip: 'Listening speed',
                initialValue: _narrationSpeed,
                onSelected: (speed) => unawaited(_changeNarrationSpeed(speed)),
                color: _chrome,
                itemBuilder: (context) => [
                  for (final speed in const [0.75, 1.0, 1.25, 1.5, 2.0])
                    PopupMenuItem<double>(
                      value: speed,
                      child: Row(
                        children: [
                          SizedBox(
                            width: 24,
                            child: speed == _narrationSpeed
                                ? const Icon(
                                    Icons.check_rounded,
                                    size: 18,
                                    color: AppColors.green,
                                  )
                                : null,
                          ),
                          Text(
                            '${speed == speed.roundToDouble() ? speed.toInt() : speed}×',
                            style: AppTypography.bodyMedium.copyWith(
                              color: _ink,
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
                child: Container(
                  height: 34,
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: _background,
                    borderRadius: AppRadii.brFull,
                    border: Border.all(color: _muted.withValues(alpha: .16)),
                  ),
                  child: Text(
                    speedLabel,
                    style: AppTypography.captionMedium.copyWith(
                      color: _ink,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: ClipRRect(
                  borderRadius: AppRadii.brFull,
                  child: LinearProgressIndicator(
                    value: progress,
                    minHeight: 4,
                    backgroundColor: _muted.withValues(alpha: .12),
                    valueColor: const AlwaysStoppedAnimation<Color>(
                      AppColors.green,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                segmentCount == 0 ? '—' : '${segmentIndex + 1}/$segmentCount',
                style: AppTypography.kicker.copyWith(
                  color: _muted,
                  fontSize: 9.5,
                ),
              ),
              const SizedBox(width: 5),
              IconButton(
                key: const Key('book-narration-previous'),
                tooltip: 'Previous sentence',
                onPressed: segmentCount == 0
                    ? null
                    : () => unawaited(_skipNarration(-1)),
                visualDensity: VisualDensity.compact,
                icon: Icon(Icons.skip_previous_rounded, color: _ink, size: 23),
              ),
              SizedBox(
                width: 42,
                height: 42,
                child: IconButton.filled(
                  key: const Key('book-narration-play-pause'),
                  tooltip: _narrationPlaying ? 'Pause' : 'Play',
                  onPressed: () => unawaited(_toggleNarration()),
                  style: IconButton.styleFrom(
                    backgroundColor: AppColors.green,
                    foregroundColor: Colors.white,
                  ),
                  icon: _narrationPreparing
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : Icon(
                          _narrationPlaying
                              ? Icons.pause_rounded
                              : Icons.play_arrow_rounded,
                          size: 24,
                        ),
                ),
              ),
              IconButton(
                key: const Key('book-narration-next'),
                tooltip: 'Next sentence',
                onPressed: segmentCount == 0
                    ? null
                    : () => unawaited(_skipNarration(1)),
                visualDensity: VisualDensity.compact,
                icon: Icon(Icons.skip_next_rounded, color: _ink, size: 23),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _bottomBar() {
    final last = _chapterIndex == _chapters.length - 1;
    final compact =
        MediaQuery.sizeOf(context).width < 360 ||
        MediaQuery.textScalerOf(context).scale(14) > 17;
    return Container(
      decoration: BoxDecoration(
        color: _chrome,
        border: Border(top: BorderSide(color: _muted.withValues(alpha: .13))),
      ),
      padding: const EdgeInsets.fromLTRB(12, 9, 12, 10),
      child: Row(
        children: [
          IconButton(
            tooltip: 'Contents',
            onPressed: _showContents,
            icon: Icon(Icons.format_list_bulleted_rounded, color: _muted),
          ),
          Stack(
            clipBehavior: Clip.none,
            children: [
              IconButton(
                tooltip: 'Notes',
                onPressed: _showNotes,
                icon: Icon(Icons.edit_note_rounded, color: _muted),
              ),
              if (_notes.isNotEmpty)
                Positioned(
                  right: 2,
                  top: 0,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 5,
                      vertical: 2,
                    ),
                    decoration: const BoxDecoration(
                      color: AppColors.green,
                      borderRadius: AppRadii.brFull,
                    ),
                    child: Text(
                      '${_notes.length}',
                      style: AppTypography.captionMedium.copyWith(
                        color: Colors.white,
                        fontSize: 9,
                      ),
                    ),
                  ),
                ),
            ],
          ),
          if (!_narrationVisible) ...[
            const SizedBox(width: 2),
            if (compact)
              IconButton(
                key: const Key('book-listen-button'),
                tooltip: 'Listen',
                onPressed: () => unawaited(_toggleNarration()),
                visualDensity: VisualDensity.compact,
                icon: const Icon(
                  Icons.headphones_rounded,
                  color: AppColors.green2,
                  size: 20,
                ),
              )
            else
              TextButton.icon(
                key: const Key('book-listen-button'),
                onPressed: () => unawaited(_toggleNarration()),
                icon: const Icon(Icons.headphones_rounded, size: 19),
                label: const Text('Listen'),
                style: TextButton.styleFrom(
                  foregroundColor: AppColors.green2,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 9,
                  ),
                  minimumSize: const Size(0, 42),
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  shape: const StadiumBorder(),
                ),
              ),
          ],
          const Spacer(),
          if (_chapterIndex > 0)
            IconButton(
              tooltip: 'Previous chapter',
              onPressed: () => _pageController.previousPage(
                duration: const Duration(milliseconds: 260),
                curve: Curves.easeOutCubic,
              ),
              icon: Icon(Icons.arrow_back_rounded, color: _muted),
            ),
          const SizedBox(width: 4),
          if (compact)
            IconButton.filled(
              tooltip: last ? 'Finish book' : 'Next chapter',
              onPressed: _next,
              style: IconButton.styleFrom(
                backgroundColor: AppColors.green,
                foregroundColor: Colors.white,
              ),
              icon: Icon(
                last ? Icons.check_rounded : Icons.arrow_forward_rounded,
                size: 20,
              ),
            )
          else
            FilledButton.icon(
              onPressed: _next,
              icon: Icon(
                last ? Icons.check_rounded : Icons.arrow_forward_rounded,
                size: 18,
              ),
              label: Text(last ? 'Finish' : 'Next'),
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.green,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(
                  horizontal: 18,
                  vertical: 13,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(99),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _errorState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.menu_book_outlined, size: 42, color: _muted),
            const SizedBox(height: 14),
            Text(
              _error!,
              textAlign: TextAlign.center,
              style: AppTypography.body.copyWith(color: _ink),
            ),
            const SizedBox(height: 16),
            CmpysButton(
              onTap: _load,
              leadingIcon: Icons.refresh_rounded,
              child: const Text('Try again'),
            ),
          ],
        ),
      ),
    );
  }
}

class _NarratedBookMarkdown extends StatelessWidget {
  const _NarratedBookMarkdown({
    required this.document,
    required this.activeSegmentIndex,
    required this.activeWordStart,
    required this.activeWordEnd,
    required this.fontSize,
    required this.ink,
    required this.muted,
    required this.dark,
    required this.blockKey,
  });

  final BookNarrationDocument document;
  final int? activeSegmentIndex;
  final int activeWordStart;
  final int activeWordEnd;
  final double fontSize;
  final Color ink;
  final Color muted;
  final bool dark;
  final GlobalKey Function(int blockIndex) blockKey;

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
      BookNarrationBlockKind.listItem => Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 27,
            child: Text(
              block.listMarker ?? '•',
              style: AppTypography.reading.copyWith(
                color: isActive ? AppColors.green : muted,
                fontSize: fontSize,
                height: 1.72,
              ),
            ),
          ),
          Expanded(child: text),
        ],
      ),
      BookNarrationBlockKind.quote => Container(
        padding: const EdgeInsets.fromLTRB(14, 11, 14, 11),
        decoration: BoxDecoration(
          color: dark
              ? Colors.white.withValues(alpha: .07)
              : AppColors.greenSoft.withValues(alpha: .72),
          borderRadius: AppRadii.br12,
        ),
        child: text,
      ),
      BookNarrationBlockKind.code => Container(
        padding: const EdgeInsets.all(13),
        decoration: BoxDecoration(
          color: dark
              ? Colors.white.withValues(alpha: .06)
              : AppColors.paper2.withValues(alpha: .7),
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
      child: content,
    );
  }

  TextStyle _baseStyle(BookNarrationBlock block) {
    return switch (block.kind) {
      BookNarrationBlockKind.heading =>
        block.headingLevel <= 3
            ? AppTypography.h3.copyWith(
                color: ink,
                fontSize: fontSize + 3,
                height: 1.32,
              )
            : AppTypography.h4.copyWith(
                color: ink,
                fontSize: fontSize + 1,
                height: 1.38,
              ),
      BookNarrationBlockKind.quote => AppTypography.readingQuote.copyWith(
        color: ink,
        fontSize: fontSize + .5,
        height: 1.55,
      ),
      BookNarrationBlockKind.code => AppTypography.monoLabel.copyWith(
        color: ink,
        fontSize: (fontSize - 2).clamp(13, 21).toDouble(),
        height: 1.55,
      ),
      _ => AppTypography.reading.copyWith(
        color: ink,
        fontSize: fontSize,
        height: 1.72,
      ),
    };
  }

  List<InlineSpan> _textSpans(
    BookNarrationBlock block,
    BookNarrationSegment? activeSegment,
  ) {
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

    final ordered = boundaries.toList()..sort();
    final spans = <InlineSpan>[];
    for (var index = 0; index < ordered.length - 1; index++) {
      final start = ordered[index];
      final end = ordered[index + 1];
      if (start == end) continue;
      final inActiveSentence =
          activeSegment != null &&
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
          backgroundColor: dark
              ? AppColors.green.withValues(alpha: .22)
              : AppColors.greenSoft,
        );
      }
      if (inActiveWord) {
        style = (style ?? const TextStyle()).copyWith(
          color: Colors.white,
          backgroundColor: AppColors.green,
          fontWeight: FontWeight.w700,
        );
      }
      spans.add(TextSpan(text: block.text.substring(start, end), style: style));
    }
    return spans;
  }
}

@visibleForTesting
class BookNoteComposerSheet extends StatefulWidget {
  const BookNoteComposerSheet({
    super.key,
    required this.quote,
    required this.background,
    required this.chrome,
    required this.ink,
    required this.muted,
    required this.dark,
    required this.onSave,
  });

  final String quote;
  final Color background;
  final Color chrome;
  final Color ink;
  final Color muted;
  final bool dark;
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
    if (_saving) return;
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
    final keyboardInset = MediaQuery.viewInsetsOf(context).bottom;
    return PopScope(
      canPop: !_saving,
      child: AnimatedPadding(
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOutCubic,
        padding: EdgeInsets.only(bottom: keyboardInset),
        child: SafeArea(
          top: false,
          child: SingleChildScrollView(
            keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
            padding: const EdgeInsets.fromLTRB(22, 14, 22, 22),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 38,
                    height: 4,
                    decoration: BoxDecoration(
                      color: widget.muted.withValues(alpha: 0.35),
                      borderRadius: BorderRadius.circular(99),
                    ),
                  ),
                ),
                const SizedBox(height: 22),
                Text(
                  'Add a note',
                  style: AppTypography.h2.copyWith(
                    color: widget.ink,
                    fontSize: 23,
                  ),
                ),
                const SizedBox(height: 12),
                Container(
                  width: double.infinity,
                  constraints: const BoxConstraints(maxHeight: 130),
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: AppColors.ochreSoft.withValues(
                      alpha: widget.dark ? 0.12 : 0.65,
                    ),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: SingleChildScrollView(
                    child: Text(
                      '“${widget.quote}”',
                      style: AppTypography.readingQuote.copyWith(
                        color: widget.ink,
                        fontSize: 15.5,
                        height: 1.45,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 14),
                TextField(
                  controller: _noteController,
                  autofocus: true,
                  minLines: 3,
                  maxLines: 6,
                  enabled: !_saving,
                  style: AppTypography.body.copyWith(color: widget.ink),
                  decoration: InputDecoration(
                    hintText: 'What do you want to remember?',
                    hintStyle: AppTypography.body.copyWith(color: widget.muted),
                    filled: true,
                    fillColor: widget.background,
                    border: OutlineInputBorder(
                      borderSide: BorderSide.none,
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
                ),
                if (_error != null) ...[
                  const SizedBox(height: 10),
                  Text(
                    _error!,
                    style: AppTypography.captionMedium.copyWith(
                      color: AppColors.danger,
                    ),
                  ),
                ],
                const SizedBox(height: 14),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: _saving ? null : _save,
                    icon: _saving
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.note_add_outlined),
                    label: Text(_saving ? 'Saving…' : 'Save note'),
                    style: FilledButton.styleFrom(
                      backgroundColor: AppColors.green,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 15),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(99),
                      ),
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
}
