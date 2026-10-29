import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/design_tokens.dart';
import '../../../core/ui/app_shell.dart';
import '../../../core/ui/motion/motion_config.dart';
import '../../../core/ui/motion/page_transition.dart';
import '../../../core/ui/v3/v3.dart';
import '../../cmpys/state/today_data.dart' show accessTypeForMaterial;
import '../../session/data/content_resources_repository.dart';
import '../../session/models/content_resource.dart';
import '../models/plan_models.dart';
import '../state/book_narration_remote_controller.dart';
import 'book_narration_checkpoint.dart';
import 'book_narration_dock.dart';
import 'book_reader_screen.dart';
import '../../../core/ui/narration_dock_page.dart';

enum _LibraryFilter { all, saved, done }

/// Rows past this index share the last row's entrance delay, so a row that
/// is built later in the entrance does not wait seconds to appear.
const _riseRows = 6;

/// How long the entrance lasts after the first load. Past it, everything is
/// built already in place (a row scrolled back into view, or one a search moves
/// up, does not rise again).
const _entranceTime = Duration(milliseconds: 1200);

// Dart has no Unicode normaliser, so the NFD step is a lookup. This is the base
// letter of each precomposed Latin letter U+00E0–U+017F (after lower-casing);
// '?' marks a ligature, which [_foldLigatures] spells out. [_foldRanges] cover
// the Vietnamese and Romanian letters outside that block.
const _foldFirst = 0xE0;
const _foldBase =
    'aaaaaa?ceeeeiiiidnooooo÷ouuuuy?yaaaaaaccccccccddddeeeeeeeeeegggggggg'
    'hhhhiiiiiiiiii??jjkkkllllllllllnnnnnnnnnoooooo??rrrrrrssssssssttttttuuuu'
    'uuuuuuuuwwyyyzzzzzzs';
const _foldLigatures = <int, String>{
  0xDF: 'ss',
  0xE6: 'ae',
  0xFE: 'th',
  0x132: 'ij',
  0x133: 'ij',
  0x152: 'oe',
  0x153: 'oe',
};

const _foldRanges = <(int, int, String)>[
  (0x01A0, 0x01A1, 'o'), // Ơ ơ
  (0x01AF, 0x01B0, 'u'), // Ư ư
  (0x0218, 0x0219, 's'), // Ș ș
  (0x021A, 0x021B, 't'), // Ț ț
  (0x1EA0, 0x1EB7, 'a'), // Latin Extended-Additional: a
  (0x1EB8, 0x1EC7, 'e'), // e
  (0x1EC8, 0x1ECB, 'i'), // i
  (0x1ECC, 0x1EE3, 'o'), // o
  (0x1EE4, 0x1EF1, 'u'), // u
  (0x1EF2, 0x1EF9, 'y'), // y
];

/// Lower-cases [value] and removes diacritics, so "José" and "jose" match:
/// precomposed Latin letters fall to their base letter and combining marks
/// (U+0300–036F, the result of an NFD split) are dropped.
@visibleForTesting
String foldSearchText(String value) {
  final out = StringBuffer();
  for (final rune in value.toLowerCase().runes) {
    if (rune >= 0x0300 && rune <= 0x036F) continue;
    final ligature = _foldLigatures[rune];
    if (ligature != null) {
      out.write(ligature);
    } else if (rune >= _foldFirst && rune < _foldFirst + _foldBase.length) {
      out.write(_foldBase[rune - _foldFirst]);
    } else {
      var folded = false;
      for (final (from, to, letter) in _foldRanges) {
        if (rune >= from && rune <= to) {
          out.write(letter);
          folded = true;
          break;
        }
      }
      if (!folded) out.writeCharCode(rune);
    }
  }
  return out.toString();
}

/// What a tap on [book] opens, through the mapping Today and the mission
/// screen share: the reader on this resource, which is the CMPYS guide.
AccessType _accessFor(ContentResource book) => accessTypeForMaterial(
  PlanMaterialDetail(
    title: book.title,
    type: 'book',
    authorOrCreator: book.authorOrCreator,
    contentResourceId: book.id,
    canonicalKey: book.canonicalKey,
  ),
);

/// Dedicated home for generated book guides and public-domain books
/// (`LibraryScreen` in `v3/library.jsx`).
///
/// Data: [contentResourcesRepositoryProvider] (the library list and the
/// continue-reading entry). Saved and completed come from the server
/// (`isSaved`, `completedAt` / progress). The backend has no chapter total
/// for a listed book, so none is shown.
class ReadingLibraryScreen extends ConsumerStatefulWidget {
  const ReadingLibraryScreen({
    super.key,
    this.shellBranchIndex = ActiveBookNarrationResume.profileBranchIndex,
  });

  /// The shell branch this library was pushed in (You by default, Today
  /// from the Today tab). Its books open in the same branch, so the player's
  /// sub-line and a cold-start resume name the right tab.
  final int shellBranchIndex;

  @override
  ConsumerState<ReadingLibraryScreen> createState() =>
      _ReadingLibraryScreenState();
}

class _ReadingLibraryScreenState extends ConsumerState<ReadingLibraryScreen> {
  final _searchController = TextEditingController();
  List<ContentResource> _books = const [];
  ContentResource? _continueReading;
  _LibraryFilter _filter = _LibraryFilter.all;

  /// Whether the list has loaded once. The skeleton shows only before that;
  /// a refresh after it (returning from the reader, pull to refresh) updates
  /// the list in place.
  bool _hasLoaded = false;
  String? _error;

  /// Set once the entrance is over. Until then the page and its rows rise in;
  /// after it they are built in place.
  bool _entranceDone = false;
  Timer? _entranceTimer;

  /// Only the latest load may apply its result: a slow earlier load must not
  /// overwrite a newer one.
  int _loadToken = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _entranceTimer?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  /// Loads the library. With [silent] (and a list already shown) nothing is
  /// blanked: the new books replace the old ones when they arrive, and a
  /// failed refresh leaves the list as it was ([toastOnFailure] says so, for a
  /// refresh the reader asked for). Only the latest load applies its result.
  Future<void> _load({bool silent = false, bool toastOnFailure = false}) async {
    final quiet = silent && _hasLoaded;
    final token = ++_loadToken;
    if (!quiet) setState(() => _error = null);
    try {
      final repository = ref.read(contentResourcesRepositoryProvider);
      final results = await Future.wait<dynamic>([
        repository.listLibraryResources(limit: 100, sort: 'title'),
        // A stale resume entry must not hide the entire reading library.
        repository.getContinueReading().catchError((_) => null),
      ]);
      if (!mounted || token != _loadToken) return;
      final all = (results[0] as List<ContentResource>)
          .where((resource) => resource.isBook)
          .toList();
      final recent = results[1] as ContentResource?;
      final first = !_hasLoaded;
      setState(() {
        _books = all;
        _continueReading = recent?.isBook == true ? recent : null;
        _hasLoaded = true;
        _error = null;
      });
      if (first) {
        _entranceTimer = Timer(_entranceTime, () {
          if (mounted) setState(() => _entranceDone = true);
        });
      }
    } catch (_) {
      if (!mounted || token != _loadToken) return;
      if (quiet) {
        if (toastOnFailure) {
          showV3Toast(
            context,
            'Couldn’t refresh — try again.',
            icon: V3Icons.alert,
            tone: V3ToastTone.warn,
          );
        }
        return;
      }
      setState(() => _error = 'Couldn’t load your reading library.');
    }
  }

  String get _query => _searchController.text.trim();

  /// The design's `list`: the filter and the search, title or author.
  List<ContentResource> get _visibleBooks {
    final query = foldSearchText(_query);
    return _books.where((book) {
      final matchesQuery =
          query.isEmpty ||
          foldSearchText(book.title).contains(query) ||
          foldSearchText(book.authorOrCreator ?? '').contains(query);
      final matchesFilter = switch (_filter) {
        _LibraryFilter.all => true,
        _LibraryFilter.saved => book.isSaved,
        _LibraryFilter.done => book.isCompleted,
      };
      return matchesQuery && matchesFilter;
    }).toList();
  }

  /// The design's `resume`: the book to pick up. The continue-reading entry
  /// when it is unfinished, else the first book with progress that is not done.
  ContentResource? get _resume {
    final recent = _continueReading;
    if (recent != null && !recent.isCompleted) return recent;
    for (final book in _books) {
      if (book.progressPercent > 0 && !book.isCompleted) return book;
    }
    return null;
  }

  Future<void> _open(ContentResource book, {bool listen = false}) async {
    await Navigator.of(context).push(
      CmpysPageRoute<void>(
        builder: (_) => BookReaderScreen(
          resourceId: book.id,
          fallbackTitle: book.title,
          fallbackSourceUrl: book.sourceUrl,
          shellBranchIndex: widget.shellBranchIndex,
          startNarrationOnOpen: listen,
        ),
      ),
    );
    if (mounted) await _load(silent: true);
  }

  void _listen(ContentResource book) {
    // The book already being narrated is toggled in place. Any other book
    // opens and starts narrating, from its saved position or its start; its
    // reader takes over the session, which stops the book playing before.
    final remote = ref.read(bookNarrationRemoteControllerProvider);
    if (remote.narrates(book.id)) {
      unawaited(remote.toggle());
      return;
    }
    unawaited(_open(book, listen: true));
  }

  @override
  Widget build(BuildContext context) {
    return NarrationDockPage(
      child: Scaffold(
        backgroundColor: AppColors.paper,
        body: Column(
          children: [
            V3TopBar(onBack: () => Navigator.of(context).maybePop()),
            Expanded(
              child: !_hasLoaded
                  ? (_error != null ? _errorView() : _loadingView())
                  : RefreshIndicator(
                      color: AppColors.ember,
                      onRefresh: () =>
                          _load(silent: true, toastOnFailure: true),
                      child: _content(),
                    ),
            ),
          ],
        ),
      ),
    );
  }

  double _bottomPad(BuildContext context) => AppShell.isWithinShell(context)
      ? AppShell.bottomNavClearance(context)
      : 36;

  Widget _clearOrSearchIcon() {
    if (_searchController.text.isEmpty) {
      return const V3Icon(V3Icons.search, size: 18, color: AppColors.ink3);
    }
    return V3Pressable(
      semanticLabel: 'Clear search',
      onTap: () {
        _searchController.clear();
        setState(() {});
      },
      child: const SizedBox(
        width: 44,
        height: 44,
        child: Center(
          child: V3Icon(V3Icons.x, size: 18, color: AppColors.ink3),
        ),
      ),
    );
  }

  /// The design's `rise(delay)` while the entrance lasts; afterwards the same
  /// widget with no delay and no duration, so it is simply in place.
  Widget _rise({Duration delay = Duration.zero, required Widget child}) =>
      V3Rise(
        delay: _entranceDone ? Duration.zero : delay,
        duration: _entranceDone
            ? Duration.zero
            : const Duration(milliseconds: 650),
        child: child,
      );

  Widget _content() {
    final books = _visibleBooks;
    final resume = _resume;
    final searching = _query.isNotEmpty;
    return CustomScrollView(
      physics: const AlwaysScrollableScrollPhysics(),
      slivers: [
        SliverToBoxAdapter(
          key: const ValueKey('library-sliver-header'),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _rise(
                  child: Text(
                    'Library'.toUpperCase(),
                    style: AppTypography.kick,
                  ),
                ),
                const SizedBox(height: 8),
                _rise(
                  delay: const Duration(milliseconds: 50),
                  child: Semantics(
                    header: true,
                    child: Text(
                      'Reading',
                      style: AppTypography.display(
                        42,
                      ).copyWith(color: AppColors.ink),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                _rise(
                  delay: const Duration(milliseconds: 100),
                  child: V3Field(
                    controller: _searchController,
                    placeholder: 'Search title or author',
                    textInputAction: TextInputAction.search,
                    onChanged: (_) => setState(() {}),
                    onTapOutside: (_) =>
                        FocusManager.instance.primaryFocus?.unfocus(),
                    right: _clearOrSearchIcon(),
                  ),
                ),
              ],
            ),
          ),
        ),
        if (resume != null && !searching)
          SliverToBoxAdapter(
            key: const ValueKey('library-sliver-hero'),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
              child: _rise(
                delay: const Duration(milliseconds: 150),
                child: _ResumeHero(
                  key: const Key('library-hero'),
                  book: resume,
                  playing: ref.watch(
                    bookNarrationRemoteControllerProvider.select(
                      (remote) =>
                          remote.narrates(resume.id) &&
                          (remote.playing || remote.preparing),
                    ),
                  ),
                  onContinue: () => _open(resume),
                  onListen: () => _listen(resume),
                ),
              ),
            ),
          ),
        SliverToBoxAdapter(
          key: const ValueKey('library-sliver-filter'),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 18, 20, 0),
            child: _rise(
              delay: const Duration(milliseconds: 200),
              child: V3Seg<_LibraryFilter>(
                items: const [
                  V3SegItem(_LibraryFilter.all, 'All'),
                  V3SegItem(_LibraryFilter.saved, 'Saved'),
                  V3SegItem(_LibraryFilter.done, 'Completed'),
                ],
                value: _filter,
                onChanged: (value) => setState(() => _filter = value),
              ),
            ),
          ),
        ),
        SliverToBoxAdapter(
          key: const ValueKey('library-sliver-count'),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 10),
            child: Semantics(
              liveRegion: true,
              child: Text(
                '${books.length} ${books.length == 1 ? 'book' : 'books'}',
                style: AppTypography.sans(
                  12.5,
                ).merge(AppTypography.tnum).copyWith(color: AppColors.ink3),
              ),
            ),
          ),
        ),
        if (books.isEmpty)
          SliverToBoxAdapter(
            key: const ValueKey('library-sliver-empty'),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: _emptyState(searching: searching),
            ),
          )
        else
          SliverPadding(
            key: const ValueKey('library-sliver-rows'),
            padding: const EdgeInsets.symmetric(horizontal: 20),
            sliver: SliverList(
              delegate: SliverChildBuilderDelegate(
                (context, i) {
                  final book = books[i];
                  final row = _BookRow(book: book, onTap: () => _open(book));
                  return Padding(
                    key: ValueKey('library-row-${book.id}'),
                    padding: EdgeInsets.only(
                      bottom: i == books.length - 1 ? 0 : 10,
                    ),
                    // The design staggers rows by 60 ms. The wrapper is the
                    // same widget at every index, so a row that a search moves
                    // keeps its state instead of remounting.
                    child: _rise(
                      delay: Duration(
                        milliseconds: (i < _riseRows ? i : _riseRows) * 60,
                      ),
                      child: row,
                    ),
                  );
                },
                childCount: books.length,
                findChildIndexCallback: (key) {
                  if (key is! ValueKey<String>) return null;
                  final index = books.indexWhere(
                    (book) => 'library-row-${book.id}' == key.value,
                  );
                  return index < 0 ? null : index;
                },
              ),
            ),
          ),
        SliverToBoxAdapter(child: SizedBox(height: _bottomPad(context))),
      ],
    );
  }

  Widget _emptyState({required bool searching}) {
    final String title;
    final String? body;
    final V3Icons icon;
    if (searching) {
      // A search with no hits is its own state, whatever the filter: one line.
      title = 'No books match your search.';
      body = null;
      icon = V3Icons.search;
    } else {
      icon = V3Icons.book;
      switch (_filter) {
        case _LibraryFilter.saved:
          title = 'No saved books yet';
          body = 'Save a book from its menu to find it here.';
        case _LibraryFilter.all:
          title = 'Nothing here yet';
          body = 'Books from your learning plan will appear here.';
        case _LibraryFilter.done:
          title = 'Nothing here yet';
          body = 'Books you finish will appear here.';
      }
    }
    return _FadeIn(
      key: ValueKey('library-empty-$searching-${_filter.name}'),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 40),
        child: Column(
          children: [
            V3Icon(icon, size: 28, color: AppColors.ink3),
            const SizedBox(height: 10),
            Text(
              title,
              textAlign: TextAlign.center,
              style: AppTypography.sans(
                15,
                FontWeight.w600,
              ).copyWith(color: AppColors.ink),
            ),
            if (body != null) ...[
              const SizedBox(height: 4),
              Text(
                body,
                textAlign: TextAlign.center,
                style: AppTypography.sans(13.5).copyWith(color: AppColors.ink2),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _loadingView() {
    return Semantics(
      label: 'Loading',
      child: ExcludeSemantics(
        child: ListView(
          physics: const NeverScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
          children: [
            const Align(
              alignment: Alignment.centerLeft,
              child: V3Skel(width: 70, height: 11),
            ),
            const SizedBox(height: 12),
            const Align(
              alignment: Alignment.centerLeft,
              child: V3Skel(width: 190, height: 38, radius: 10),
            ),
            const SizedBox(height: 16),
            const V3Skel(height: 52, radius: 16),
            const SizedBox(height: 24),
            for (var i = 0; i < 3; i++) ...[
              const V3Skel(height: 112, radius: AppRadii.r),
              const SizedBox(height: 10),
            ],
          ],
        ),
      ),
    );
  }

  Widget _errorView() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.all(22),
          decoration: v3Card(),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const V3Icon(V3Icons.alert, size: 28, color: AppColors.ink3),
              const SizedBox(height: 10),
              Text(
                _error!,
                textAlign: TextAlign.center,
                style: AppTypography.sans(
                  15,
                  FontWeight.w600,
                ).copyWith(color: AppColors.ink),
              ),
              const SizedBox(height: 16),
              V3Button(
                kind: V3ButtonKind.dark,
                size: V3Size.md,
                icon: V3Icons.refresh,
                onPressed: _load,
                child: const Text('Try again'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The night "Continue reading" card.
class _ResumeHero extends StatelessWidget {
  const _ResumeHero({
    super.key,
    required this.book,
    required this.onContinue,
    required this.onListen,
    this.playing = false,
  });

  final ContentResource book;
  final VoidCallback onContinue;
  final VoidCallback onListen;

  /// This book is the one being narrated, and it is playing.
  final bool playing;

  /// "Ch. 6 · Accounting essays" from the reader's saved position; null
  /// when the book has none (nothing is invented).
  String? get _where {
    final chapter = (book.cursorJson?['chapter'] as num?)?.toInt();
    if (chapter == null || chapter < 0) return null;
    final title = book.cursorJson?['chapterTitle']?.toString().trim() ?? '';
    return title.isEmpty ? 'Ch. ${chapter + 1}' : 'Ch. ${chapter + 1} · $title';
  }

  @override
  Widget build(BuildContext context) {
    final ground = v3CoverGround(book.id);
    final where = _where;
    final pct = book.progressPercent.clamp(0, 100);
    return ClipRRect(
      borderRadius: AppRadii.brR2,
      child: ColoredBox(
        color: AppColors.night,
        child: Stack(
          children: [
            Positioned(
              right: -70,
              top: -70,
              width: 220,
              height: 220,
              child: IgnorePointer(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: RadialGradient(
                      // CSS `circle` = farthest-corner on a square box.
                      radius: 0.7071,
                      colors: [
                        ground.withValues(alpha: .9),
                        ground.withValues(alpha: 0),
                      ],
                      stops: const [0, .7],
                    ),
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(18),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  V3Cover(
                    title: v3CoverTitle(book.title),
                    author: book.authorOrCreator?.trim() ?? '',
                    background: ground,
                    foreground: kV3CoverInk,
                    width: 86,
                    height: 124,
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Continue reading',
                          style: AppTypography.sans(
                            12,
                            FontWeight.w600,
                          ).copyWith(color: AppColors.nink3),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          book.title,
                          maxLines: 3,
                          overflow: TextOverflow.ellipsis,
                          style: AppTypography.sans(
                            17,
                            FontWeight.w600,
                          ).copyWith(color: Colors.white, height: 1.25),
                        ),
                        if (where != null) ...[
                          const SizedBox(height: 3),
                          Text(
                            where,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: AppTypography.sans(
                              12.5,
                            ).copyWith(color: AppColors.nink2),
                          ),
                        ],
                        const SizedBox(height: 12),
                        V3Bar(
                          value: pct / 100,
                          height: 4,
                          track: const Color(0x24FFFFFF),
                          delay: const Duration(milliseconds: 500),
                        ),
                        const SizedBox(height: 12),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            V3Button(
                              size: V3Size.sm,
                              onPressed: onContinue,
                              child: const Text('Continue'),
                            ),
                            V3Button(
                              kind: V3ButtonKind.glass,
                              size: V3Size.sm,
                              icon: playing ? null : V3Icons.headphones,
                              semanticLabel: playing ? 'Listening' : 'Listen',
                              onPressed: onListen,
                              child: playing
                                  ? const Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        SizedBox(
                                          width: 20,
                                          child: BookNarrationWaves(
                                            playing: true,
                                            count: 4,
                                            height: 14,
                                          ),
                                        ),
                                        SizedBox(width: 8),
                                        Text('Listen'),
                                      ],
                                    )
                                  : const Text('Listen'),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// One book of the list: cover, title, author, what a tap opens, and
/// progress (a ring, or a check once finished) with a bookmark when saved.
class _BookRow extends StatelessWidget {
  const _BookRow({required this.book, required this.onTap});

  final ContentResource book;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final author = book.authorOrCreator?.trim() ?? '';
    final access = _accessFor(book);
    final original =
        access == AccessType.guide && book.originalReadingUrl != null;
    final pct = book.progressPercent.clamp(0, 100);
    final done = book.isCompleted;
    final label = [
      book.title,
      if (author.isNotEmpty) author,
      accessCopy(access).label,
      if (original) accessCopy(AccessType.original).label,
      done ? 'Completed' : '$pct% read',
      if (book.isSaved) 'Saved',
    ].join(', ');
    return V3Pressable(
      onTap: onTap,
      semanticLabel: label,
      focusRadius: AppRadii.brR,
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: v3Card(),
        child: Row(
          children: [
            V3Cover(
              title: v3CoverTitle(book.title),
              author: author,
              background: v3CoverGround(book.id),
              foreground: kV3CoverInk,
              width: 62,
              height: 88,
              radius: 8,
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    book.title,
                    style: AppTypography.sans(
                      15.5,
                      FontWeight.w600,
                    ).copyWith(color: AppColors.ink, height: 1.25),
                  ),
                  if (author.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(
                      author,
                      style: AppTypography.sans(
                        12.5,
                      ).copyWith(color: AppColors.ink3),
                    ),
                  ],
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      _FitBadge(access),
                      if (original) const _FitBadge(AccessType.original),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(width: 14),
            Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (done)
                  const V3Icon(
                    V3Icons.check,
                    size: 18,
                    strokeWidth: 2.5,
                    color: AppColors.sage2,
                  )
                else
                  V3Ring(
                    value: pct / 100,
                    size: 30,
                    strokeWidth: 3,
                    child: Text(
                      '$pct',
                      style: AppTypography.sans(8.5, FontWeight.w700)
                          .merge(AppTypography.tnum)
                          .copyWith(color: AppColors.ink),
                    ),
                  ),
                if (book.isSaved) ...[
                  const SizedBox(height: 6),
                  const V3Icon(
                    V3Icons.bookmark,
                    size: 14,
                    color: AppColors.ember,
                    fill: AppColors.ember,
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// A badge that scales down rather than overflow a narrow text column.
class _FitBadge extends StatelessWidget {
  const _FitBadge(this.type);

  final AccessType type;

  @override
  Widget build(BuildContext context) {
    return FittedBox(
      fit: BoxFit.scaleDown,
      alignment: Alignment.centerLeft,
      child: V3AccessBadge(type: type),
    );
  }
}

/// The design's `animation: fade .4s`; reduced motion shows it at once.
class _FadeIn extends StatelessWidget {
  const _FadeIn({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: MotionConfig.enabled(context)
          ? const Duration(milliseconds: 400)
          : Duration.zero,
      builder: (context, value, child) => Opacity(opacity: value, child: child),
      child: child,
    );
  }
}
