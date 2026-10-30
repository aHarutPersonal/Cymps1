import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/design_tokens.dart';
import '../../../core/ui/motion/page_transition.dart';
import '../../../core/reading/lesson_fences.dart';
import '../../../core/ui/cmpys/cmpys_markdown.dart';
import '../../../core/ui/v3/lesson_blocks/quick_check.dart';
import '../../../core/ui/v3/v3.dart';
import '../data/plan_repository.dart';
import '../models/learning_support.dart';
import '../models/plan_models.dart';
import 'book_reader_screen.dart';
import 'material_web_screen.dart';

class BookCompanionScreen extends ConsumerStatefulWidget {
  const BookCompanionScreen({
    super.key,
    required this.itemId,
    required this.material,
    this.initialBook,
    this.shellBranchIndex = 1,
  });
  final String itemId;
  final PlanMaterialDetail material;
  final BookCompanion? initialBook;
  final int shellBranchIndex;
  @override
  ConsumerState<BookCompanionScreen> createState() =>
      _BookCompanionScreenState();
}

class _BookCompanionScreenState extends ConsumerState<BookCompanionScreen> {
  BookCompanion? _book;
  bool _loading = true;
  String? _message;
  Timer? _timer;
  int _polls = 0;
  bool _findingEdition = false;

  Future<void> _findEdition() async {
    setState(() => _findingEdition = true);
    try {
      final material = widget.material;
      final access = await ref
          .read(planRepositoryProvider)
          .resolveBookReadingAccess(
            material.canonicalKey!,
            material.title,
            material.authorOrCreator,
          );
      if (!mounted) return;
      if (access.source case final source?) {
        await Navigator.of(context).push(
          CmpysPageRoute<void>(
            builder: (_) => MaterialWebScreen(
              url: source.url,
              title: material.title,
              sourceDescription: source.description,
              access: source.scope == 'excerpt'
                  ? AccessType.excerpt
                  : AccessType.original,
              openedFrom: 'Book companion · ${material.title}',
            ),
          ),
        );
      } else if (access.resourceId case final id?) {
        await Navigator.of(context).push(
          CmpysPageRoute<void>(
            builder: (_) => BookReaderScreen(
              resourceId: id,
              fallbackTitle: material.title,
              shellBranchIndex: widget.shellBranchIndex,
            ),
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('No reading edition is available here yet.'),
          ),
        );
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Couldn’t check reading editions. Please try again.'),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _findingEdition = false);
    }
  }

  @override
  void initState() {
    super.initState();
    _book = widget.initialBook;
    if (_book?.status == 'ready') {
      _loading = false;
    } else {
      _load(true);
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _load(bool prepare) async {
    try {
      final result = await ref
          .read(planRepositoryProvider)
          .getLearningSupport(
            widget.itemId,
            bookTitle: widget.material.title,
            prepare: prepare,
          );
      if (!mounted) return;
      setState(() {
        _book = result.books
            .where((b) => b.title == widget.material.title)
            .firstOrNull;
        _loading = _book?.status != 'ready' && result.checking && _polls < 50;
        _message = _loading
            ? 'Preparing short tutorials and checking their sources. You can continue your mission and return here.'
            : _book?.status == 'ready'
            ? null
            : 'We haven’t found enough reliable source material for these tutorials yet. Your mission already includes everything you need.';
      });
      if (_loading && _polls++ < 50) {
        _timer = Timer(const Duration(seconds: 12), () => _load(false));
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _loading = false;
          _message = 'Couldn’t load the book tutorials. Please try again.';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final book = _book;
    final material = widget.material;
    return Scaffold(
      backgroundColor: AppColors.paper,
      body: Column(
        children: [
          V3TopBar(
            title: 'Book companion',
            onBack: () => Navigator.of(context).maybePop(),
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.all(22),
              children: [
                Text(
                  material.title,
                  style: AppTypography.sans(26, FontWeight.w600),
                ),
                if (material.authorOrCreator != null)
                  Text(
                    material.authorOrCreator!,
                    style: AppTypography.sans(15),
                  ),
                const SizedBox(height: 16),
                Text(
                  'Optional short tutorials by CMPYS, based on publicly documented ideas. The full book is not included.',
                  style: AppTypography.sans(
                    15,
                  ).copyWith(height: 1.5, color: AppColors.ink2),
                ),
                const SizedBox(height: 18),
                if (_loading)
                  const Align(
                    alignment: Alignment.centerLeft,
                    child: SizedBox(
                      height: 22,
                      width: 22,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  ),
                if (_message != null)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    child: Text(_message!),
                  ),
                if (!_loading && book?.status != 'ready')
                  V3Button(
                    kind: V3ButtonKind.soft,
                    onPressed: () {
                      setState(() {
                        _loading = true;
                        _polls = 0;
                      });
                      _load(true);
                    },
                    child: const Text('Check again'),
                  ),
                if (book?.status == 'ready') ...[
                  Text(
                    book!.scope,
                    style: AppTypography.sans(15).copyWith(height: 1.5),
                  ),
                  const SizedBox(height: 20),
                  for (var index = 0; index < book.lessons.length; index++)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: ListTile(
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 8,
                        ),
                        tileColor: AppColors.card,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                          side: const BorderSide(color: AppColors.hair),
                        ),
                        leading: Text(
                          '${index + 1}',
                          style: AppTypography.sans(20, FontWeight.w600),
                        ),
                        title: Text(book.lessons[index].title),
                        subtitle: Text(
                          '${book.lessons[index].minutes} min · includes a self-check',
                        ),
                        trailing: const Icon(Icons.chevron_right),
                        onTap: () => Navigator.of(context).push(
                          CmpysPageRoute<void>(
                            builder: (_) =>
                                BookTutorialScreen(book: book, index: index),
                          ),
                        ),
                      ),
                    ),
                  const SizedBox(height: 12),
                  Text(
                    'Sources',
                    style: AppTypography.sans(17, FontWeight.w600),
                  ),
                  for (final source in book.sources)
                    TextButton(
                      onPressed: () => _openSource(context, source),
                      child: Text(source['title'] as String),
                    ),
                ],
                if (material.contentResourceId?.isNotEmpty == true) ...[
                  const SizedBox(height: 16),
                  V3Button(
                    kind: V3ButtonKind.soft,
                    onPressed: () => Navigator.of(context).push(
                      CmpysPageRoute<void>(
                        builder: (_) => BookReaderScreen(
                          resourceId: material.contentResourceId!,
                          fallbackTitle: material.title,
                          shellBranchIndex: widget.shellBranchIndex,
                        ),
                      ),
                    ),
                    child: const Text('Open full study guide'),
                  ),
                ],
                if (material.directUrl != null) ...[
                  const SizedBox(height: 12),
                  V3Button(
                    kind: V3ButtonKind.line,
                    onPressed: () => Navigator.of(context).push(
                      CmpysPageRoute<void>(
                        builder: (_) => MaterialWebScreen(
                          url: material.directUrl!,
                          title: material.title,
                        ),
                      ),
                    ),
                    child: const Text('Find the book'),
                  ),
                ],
                if (material.contentResourceId == null &&
                    material.directUrl == null &&
                    material.canonicalKey?.isNotEmpty == true) ...[
                  const SizedBox(height: 12),
                  V3Button(
                    kind: V3ButtonKind.line,
                    loading: _findingEdition,
                    onPressed: _findingEdition ? null : _findEdition,
                    child: const Text('Find a reading edition'),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

void _openSource(BuildContext context, Map<String, dynamic> source) {
  final material = PlanMaterialDetail(
    title: source['title'] as String,
    url: source['url'] as String,
  );
  if (material.directUrl == null) return;
  Navigator.of(context).push(
    CmpysPageRoute<void>(
      builder: (_) =>
          MaterialWebScreen(url: material.directUrl!, title: material.title),
    ),
  );
}

class BookTutorialScreen extends StatelessWidget {
  const BookTutorialScreen({
    super.key,
    required this.book,
    required this.index,
  });
  final BookCompanion book;
  final int index;
  @override
  Widget build(BuildContext context) {
    final lesson = book.lessons[index];
    return Scaffold(
      backgroundColor: AppColors.paper,
      body: Column(
        children: [
          V3TopBar(
            title: 'Tutorial ${index + 1} of ${book.lessons.length}',
            onBack: () => Navigator.of(context).maybePop(),
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.all(22),
              children: [
                Text(
                  lesson.title,
                  style: AppTypography.sans(26, FontWeight.w600),
                ),
                const SizedBox(height: 8),
                Text(
                  '${book.title} · ${lesson.minutes} min',
                  style: AppTypography.sans(13).copyWith(color: AppColors.ink2),
                ),
                const SizedBox(height: 22),
                CmpysMarkdown(lesson.content),
                const SizedBox(height: 24),
                QuickCheck(
                  block: CheckBlock(
                    lesson.question,
                    [
                      for (var i = 0; i < lesson.options.length; i++)
                        CheckOption(lesson.options[i], i == lesson.answer),
                    ],
                    null,
                    lesson.explanation,
                  ),
                ),
                const SizedBox(height: 24),
                for (final source in book.sources.where(
                  (s) => lesson.sourceIds.contains(s['id']),
                ))
                  TextButton(
                    onPressed: () => _openSource(context, source),
                    child: Text('Source: ${source['title']}'),
                  ),
                const SizedBox(height: 16),
                V3Button(
                  onPressed: () {
                    if (index + 1 < book.lessons.length) {
                      Navigator.of(context).pushReplacement(
                        CmpysPageRoute<void>(
                          builder: (_) =>
                              BookTutorialScreen(book: book, index: index + 1),
                        ),
                      );
                    } else {
                      Navigator.of(context).pop();
                    }
                  },
                  child: Text(
                    index + 1 < book.lessons.length
                        ? 'Next tutorial'
                        : 'Back to book',
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
