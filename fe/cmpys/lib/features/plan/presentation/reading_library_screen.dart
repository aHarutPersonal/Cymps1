import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/design_tokens.dart';
import '../../../core/ui/cmpys/cmpys_primitives.dart';
import '../../../core/ui/motion/page_transition.dart';
import '../../session/data/content_resources_repository.dart';
import '../../session/models/content_resource.dart';
import 'book_reader_screen.dart';

/// Dedicated home for generated book guides and public-domain books.
class ReadingLibraryScreen extends ConsumerStatefulWidget {
  const ReadingLibraryScreen({super.key});

  @override
  ConsumerState<ReadingLibraryScreen> createState() =>
      _ReadingLibraryScreenState();
}

class _ReadingLibraryScreenState extends ConsumerState<ReadingLibraryScreen> {
  final _searchController = TextEditingController();
  List<ContentResource> _books = const [];
  ContentResource? _continueReading;
  String _filter = 'all';
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final repository = ref.read(contentResourcesRepositoryProvider);
      final results = await Future.wait<dynamic>([
        repository.listLibraryResources(limit: 100, sort: 'title'),
        repository.getContinueReading(),
      ]);
      if (!mounted) return;
      final all = (results[0] as List<ContentResource>)
          .where((resource) => resource.isBook)
          .toList();
      final recent = results[1] as ContentResource?;
      setState(() {
        _books = all;
        _continueReading = recent?.isBook == true ? recent : null;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'Couldn’t load your reading library.';
      });
    }
  }

  List<ContentResource> get _visibleBooks {
    final query = _searchController.text.trim().toLowerCase();
    return _books.where((book) {
      final matchesQuery =
          query.isEmpty ||
          book.title.toLowerCase().contains(query) ||
          (book.authorOrCreator ?? '').toLowerCase().contains(query);
      final matchesFilter = switch (_filter) {
        'saved' => book.isSaved,
        'completed' => book.isCompleted,
        _ => true,
      };
      return matchesQuery && matchesFilter;
    }).toList();
  }

  Future<void> _open(ContentResource book) async {
    await Navigator.of(context, rootNavigator: true).push(
      CmpysPageRoute<void>(
        builder: (_) =>
            BookReaderScreen(resourceId: book.id, fallbackTitle: book.title),
      ),
    );
    if (mounted) await _load();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.paper,
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            _header(),
            Expanded(
              child: _loading
                  ? const Center(
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: AppColors.green,
                      ),
                    )
                  : _error != null
                  ? _errorState()
                  : RefreshIndicator(
                      color: AppColors.green,
                      onRefresh: _load,
                      child: _content(),
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _header() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(10, 8, 18, 10),
      child: Row(
        children: [
          IconButton(
            onPressed: () => Navigator.of(context).maybePop(),
            style: IconButton.styleFrom(
              backgroundColor: AppColors.card,
              side: const BorderSide(color: AppColors.hair),
            ),
            icon: const Icon(
              Icons.chevron_left_rounded,
              color: AppColors.ink,
              size: 22,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Reading',
                  style: AppTypography.h1.copyWith(
                    fontSize: 28,
                    letterSpacing: -.4,
                    height: 1.1,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  'Your books, progress, and notes',
                  style: AppTypography.caption.copyWith(
                    color: AppColors.ink3,
                    fontSize: 12.5,
                  ),
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: AppColors.greenSoft,
              borderRadius: AppRadii.brFull,
            ),
            child: Text(
              '${_books.length} books',
              style: AppTypography.kicker.copyWith(
                color: AppColors.green2,
                fontSize: 10,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _content() {
    final books = _visibleBooks;
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(18, 8, 18, 36),
      children: [
        if (_continueReading != null) ...[
          const CmpysKicker('Continue reading'),
          const SizedBox(height: 9),
          _continueCard(_continueReading!),
          const SizedBox(height: 24),
        ],
        TextField(
          controller: _searchController,
          onChanged: (_) => setState(() {}),
          textAlignVertical: TextAlignVertical.center,
          onTapOutside: (_) => FocusManager.instance.primaryFocus?.unfocus(),
          decoration: InputDecoration(
            hintText: 'Search books or authors',
            hintStyle: AppTypography.body.copyWith(color: AppColors.ink3),
            prefixIcon: const Icon(Icons.search_rounded, color: AppColors.ink3),
            suffixIcon: _searchController.text.isEmpty
                ? null
                : IconButton(
                    onPressed: () {
                      _searchController.clear();
                      setState(() {});
                    },
                    icon: const Icon(
                      Icons.close_rounded,
                      color: AppColors.ink3,
                    ),
                  ),
            filled: true,
            fillColor: AppColors.card,
            border: OutlineInputBorder(
              borderSide: const BorderSide(color: AppColors.hair),
              borderRadius: BorderRadius.circular(18),
            ),
            enabledBorder: OutlineInputBorder(
              borderSide: const BorderSide(color: AppColors.hair),
              borderRadius: BorderRadius.circular(18),
            ),
            focusedBorder: OutlineInputBorder(
              borderSide: const BorderSide(color: AppColors.hair2, width: 1.5),
              borderRadius: BorderRadius.circular(18),
            ),
          ),
        ),
        const SizedBox(height: 13),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              _filterChip('all', 'All'),
              const SizedBox(width: 8),
              _filterChip('saved', 'Saved'),
              const SizedBox(width: 8),
              _filterChip('completed', 'Completed'),
            ],
          ),
        ),
        const SizedBox(height: 20),
        Row(
          children: [
            const Expanded(child: CmpysKicker('Your books')),
            Text(
              '${books.length}',
              style: AppTypography.caption.copyWith(color: AppColors.ink3),
            ),
          ],
        ),
        const SizedBox(height: 10),
        if (books.isEmpty)
          _emptyState()
        else
          for (final book in books) ...[
            _bookCard(book),
            const SizedBox(height: 10),
          ],
      ],
    );
  }

  Widget _filterChip(String value, String label) {
    final selected = _filter == value;
    return ChoiceChip(
      selected: selected,
      label: Text(label),
      showCheckmark: false,
      onSelected: (_) => setState(() => _filter = value),
      labelStyle: AppTypography.captionMedium.copyWith(
        color: selected ? Colors.white : AppColors.ink2,
        fontWeight: FontWeight.w700,
      ),
      selectedColor: AppColors.ink,
      backgroundColor: AppColors.card,
      side: BorderSide(color: selected ? AppColors.ink : AppColors.hair),
      shape: RoundedRectangleBorder(borderRadius: AppRadii.brFull),
    );
  }

  Widget _continueCard(ContentResource book) {
    final progress = book.progressPercent.clamp(0, 100);
    return GestureDetector(
      onTap: () => _open(book),
      child: Container(
        padding: const EdgeInsets.all(18),
        decoration: const BoxDecoration(
          gradient: AppColors.gradInk,
          borderRadius: AppRadii.card,
        ),
        child: Row(
          children: [
            _bookCover(book, dark: true),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    book.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: AppTypography.h3.copyWith(
                      color: Colors.white,
                      fontSize: 18,
                    ),
                  ),
                  if ((book.authorOrCreator ?? '').isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(
                      book.authorOrCreator!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTypography.caption.copyWith(
                        color: Colors.white.withValues(alpha: .6),
                      ),
                    ),
                  ],
                  const SizedBox(height: 14),
                  ClipRRect(
                    borderRadius: AppRadii.brFull,
                    child: LinearProgressIndicator(
                      value: progress / 100,
                      minHeight: 5,
                      backgroundColor: Colors.white.withValues(alpha: .15),
                      valueColor: const AlwaysStoppedAnimation<Color>(
                        AppColors.green,
                      ),
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    '$progress% complete',
                    style: AppTypography.kicker.copyWith(
                      color: Colors.white.withValues(alpha: .65),
                      fontSize: 9.5,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            const Icon(
              Icons.arrow_forward_rounded,
              color: Colors.white,
              size: 22,
            ),
          ],
        ),
      ),
    );
  }

  Widget _bookCard(ContentResource book) {
    return CmpysCardSurface(
      onTap: () => _open(book),
      pad: const EdgeInsets.all(14),
      child: Row(
        children: [
          _bookCover(book),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        book.title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: AppTypography.bodyMedium.copyWith(
                          fontSize: 15.5,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    if (book.isSaved)
                      const Icon(
                        Icons.bookmark_rounded,
                        color: AppColors.green,
                        size: 18,
                      ),
                  ],
                ),
                if ((book.authorOrCreator ?? '').isNotEmpty) ...[
                  const SizedBox(height: 3),
                  Text(
                    book.authorOrCreator!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppTypography.caption.copyWith(
                      color: AppColors.ink3,
                    ),
                  ),
                ],
                const SizedBox(height: 10),
                Row(
                  children: [
                    Icon(
                      Icons.schedule_rounded,
                      size: 14,
                      color: AppColors.ink3,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      '${book.durationMinutes ?? 15} min',
                      style: AppTypography.caption.copyWith(
                        color: AppColors.ink3,
                        fontSize: 11.5,
                      ),
                    ),
                    if (book.progressPercent > 0) ...[
                      const SizedBox(width: 10),
                      Expanded(
                        child: ClipRRect(
                          borderRadius: AppRadii.brFull,
                          child: LinearProgressIndicator(
                            value: book.progressPercent.clamp(0, 100) / 100,
                            minHeight: 4,
                            backgroundColor: AppColors.hair,
                            valueColor: const AlwaysStoppedAnimation<Color>(
                              AppColors.green,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 7),
                      Text(
                        '${book.progressPercent}%',
                        style: AppTypography.kicker.copyWith(
                          color: AppColors.green2,
                          fontSize: 9,
                        ),
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: 6),
          const Icon(
            Icons.chevron_right_rounded,
            color: AppColors.hair2,
            size: 20,
          ),
        ],
      ),
    );
  }

  Widget _bookCover(ContentResource book, {bool dark = false}) {
    return Container(
      width: 58,
      height: 78,
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: dark ? Colors.white.withValues(alpha: .1) : AppColors.ochreSoft,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            Icons.menu_book_rounded,
            size: 16,
            color: dark ? Colors.white : AppColors.ochre2,
          ),
          Text(
            book.title,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: AppTypography.kicker.copyWith(
              color: dark ? Colors.white : AppColors.ochre2,
              fontSize: 7.5,
              height: 1.2,
            ),
          ),
        ],
      ),
    );
  }

  Widget _emptyState() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 42),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: AppRadii.card,
        border: Border.all(color: AppColors.hair),
      ),
      child: Column(
        children: [
          const Icon(
            Icons.auto_stories_outlined,
            color: AppColors.ink3,
            size: 34,
          ),
          const SizedBox(height: 10),
          Text(
            _searchController.text.isNotEmpty || _filter != 'all'
                ? 'No books match this view.'
                : 'Books from your learning plan will appear here.',
            textAlign: TextAlign.center,
            style: AppTypography.body.copyWith(color: AppColors.ink2),
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
            const Icon(
              Icons.cloud_off_outlined,
              color: AppColors.ink3,
              size: 38,
            ),
            const SizedBox(height: 12),
            Text(_error!, style: AppTypography.body),
            const SizedBox(height: 14),
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
