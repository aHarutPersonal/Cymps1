import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/design_tokens.dart';
import '../../../core/ui/cmpys/cmpys_markdown.dart';
import '../../../core/ui/cmpys/cmpys_primitives.dart';
import '../../session/data/content_resources_repository.dart';
import '../../session/models/content_resource.dart';
import '../models/plan_models.dart';

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
  });

  final String resourceId;
  final String fallbackTitle;

  @override
  ConsumerState<BookReaderScreen> createState() => _BookReaderScreenState();
}

class _BookReaderScreenState extends ConsumerState<BookReaderScreen> {
  PageController _pageController = PageController();
  ContentResource? _resource;
  List<BookChapter> _chapters = const [];
  List<ContentHighlight> _notes = const [];
  int _chapterIndex = 0;
  double _fontSize = 18;
  int _readingTheme = 0;
  String? _selectedQuote;
  bool _loading = true;
  bool _savingBook = false;
  String? _error;

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
    _load();
  }

  @override
  void dispose() {
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

  void _onChapterChanged(int index) {
    setState(() {
      _chapterIndex = index;
      _selectedQuote = null;
    });
    unawaited(_persistProgress());
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
          _circleButton(
            Icons.chevron_left_rounded,
            () => Navigator.of(context).maybePop(),
          ),
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

  Widget _bottomBar() {
    final last = _chapterIndex == _chapters.length - 1;
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
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 13),
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
