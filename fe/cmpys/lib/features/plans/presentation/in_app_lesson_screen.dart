import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../app/design_tokens.dart';
import '../../../core/ui/resource_notes_panel.dart';
import '../../session/data/content_resources_repository.dart';
import '../../session/models/content_resource.dart';
import '../../session/providers/content_resources_provider.dart';
import '../../session/providers/library_provider.dart';

/// Screen to display in-app lesson content with markdown rendering.
class InAppLessonScreen extends ConsumerStatefulWidget {
  const InAppLessonScreen({
    super.key,
    required this.title,
    required this.markdown,
    this.materialId,
    this.durationMinutes,
    this.initialIsSaved = false,
    this.initialProgressPercent = 0,
    this.initialIsCompleted = false,
    this.onMarkAsRead,
  });

  final String title;
  final String markdown;
  final String? materialId;
  final int? durationMinutes;
  final bool initialIsSaved;
  final int initialProgressPercent;
  final bool initialIsCompleted;
  final VoidCallback? onMarkAsRead;

  @override
  ConsumerState<InAppLessonScreen> createState() => _InAppLessonScreenState();
}

class _InAppLessonScreenState extends ConsumerState<InAppLessonScreen> {
  final ScrollController _scrollController = ScrollController();
  final TextEditingController _noteController = TextEditingController();
  bool _isResourceSaved = false;
  bool _isSavingResource = false;
  bool _isLoadingHighlights = false;
  bool _isSavingHighlight = false;
  List<ContentHighlight> _highlights = const [];
  double _scrollProgress = 0;

  bool get _hasSharedResource => widget.materialId?.isNotEmpty == true;

  @override
  void initState() {
    super.initState();
    _isResourceSaved = widget.initialIsSaved;
    _scrollProgress = (widget.initialProgressPercent / 100).clamp(0, 1);
    _scrollController.addListener(_onScroll);
    if (_hasSharedResource) {
      _loadHighlights();
    }
  }

  @override
  void dispose() {
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    _noteController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (!_scrollController.hasClients) return;

    final maxScroll = _scrollController.position.maxScrollExtent;
    final currentScroll = _scrollController.offset;

    setState(() {
      _scrollProgress = maxScroll > 0
          ? (currentScroll / maxScroll).clamp(0, 1)
          : 1;
    });
  }

  Future<void> _markAsRead() async {
    // Call the callback if provided
    widget.onMarkAsRead?.call();

    if (_hasSharedResource) {
      try {
        await ref
            .read(contentResourcesRepositoryProvider)
            .updateProgress(
              widget.materialId!,
              progressPercent: 100,
              completed: true,
            );
        ref.invalidate(vaultResourcesProvider);
      } catch (_) {
        // Keep local completion optimistic; progress sync can retry later.
      }
    }
    if (!mounted) return;

    _showReaderSnack('Marked as read');
  }

  Future<void> _toggleSharedResourceSave() async {
    if (!_hasSharedResource || _isSavingResource) return;

    setState(() => _isSavingResource = true);
    try {
      final repository = ref.read(contentResourcesRepositoryProvider);
      if (_isResourceSaved) {
        await repository.unsaveResource(widget.materialId!);
      } else {
        await repository.saveResource(widget.materialId!);
      }
      setState(() => _isResourceSaved = !_isResourceSaved);
      ref.invalidate(vaultResourcesProvider);
      if (!mounted) return;
      _showReaderSnack(
        _isResourceSaved ? 'Saved to Vault' : 'Removed from Vault',
      );
    } catch (_) {
      if (!mounted) return;
      _showReaderSnack('Could not update Vault', isError: true);
    } finally {
      if (mounted) setState(() => _isSavingResource = false);
    }
  }

  Future<void> _toggleReaderVault() async {
    if (_hasSharedResource) {
      await _toggleSharedResourceSave();
      return;
    }

    final item = SavedItem(
      id: 'lesson_${widget.title.hashCode}',
      title: widget.title,
      content: widget.markdown,
      category: '15-Min Book',
      type: 'lesson',
    );
    ref.read(libraryProvider.notifier).toggleItem(item);
    final isSaved = ref.read(libraryProvider.notifier).isSaved(item.id);
    if (!mounted) return;
    _showReaderSnack(isSaved ? 'Saved to Vault' : 'Removed from Vault');
  }

  Future<void> _loadHighlights() async {
    if (!_hasSharedResource) return;
    setState(() => _isLoadingHighlights = true);
    try {
      final highlights = await ref
          .read(contentResourcesRepositoryProvider)
          .listHighlights(widget.materialId!);
      if (!mounted) return;
      setState(() => _highlights = highlights);
    } catch (_) {
      if (!mounted) return;
      setState(() => _highlights = const []);
    } finally {
      if (mounted) setState(() => _isLoadingHighlights = false);
    }
  }

  Future<void> _saveReaderNote() async {
    final note = _noteController.text.trim();
    if (!_hasSharedResource || note.isEmpty || _isSavingHighlight) return;

    setState(() => _isSavingHighlight = true);
    try {
      final highlight = await ref
          .read(contentResourcesRepositoryProvider)
          .createHighlight(
            widget.materialId!,
            locatorJson: {
              'screen': 'reader',
              'scrollProgress': _scrollProgress,
              'title': widget.title,
            },
            noteText: note,
          );
      if (!mounted) return;
      setState(() {
        _highlights = [highlight, ..._highlights];
        _noteController.clear();
      });
      _showReaderSnack('Note saved');
    } catch (_) {
      if (!mounted) return;
      _showReaderSnack('Could not save note', isError: true);
    } finally {
      if (mounted) setState(() => _isSavingHighlight = false);
    }
  }

  Future<void> _deleteReaderNote(ContentHighlight highlight) async {
    if (!_hasSharedResource) return;

    final previous = _highlights;
    setState(() {
      _highlights = _highlights
          .where((item) => item.id != highlight.id)
          .toList();
    });

    try {
      await ref
          .read(contentResourcesRepositoryProvider)
          .deleteHighlight(widget.materialId!, highlight.id);
    } catch (_) {
      if (!mounted) return;
      setState(() => _highlights = previous);
      _showReaderSnack('Could not delete note', isError: true);
    }
  }

  Future<void> _highlightCurrentPassage() async {
    final passage = _currentPassage();

    if (_hasSharedResource) {
      setState(() => _isSavingHighlight = true);
      try {
        final highlight = await ref
            .read(contentResourcesRepositoryProvider)
            .createHighlight(
              widget.materialId!,
              locatorJson: {
                'screen': 'reader',
                'scrollProgress': _scrollProgress,
                'title': widget.title,
                'kind': 'highlight',
              },
              noteText: 'Highlighted: $passage',
            );
        if (!mounted) return;
        setState(() => _highlights = [highlight, ..._highlights]);
        _showReaderSnack('Highlight saved');
      } catch (_) {
        if (!mounted) return;
        _showReaderSnack('Could not save highlight', isError: true);
      } finally {
        if (mounted) setState(() => _isSavingHighlight = false);
      }
      return;
    }

    await Clipboard.setData(ClipboardData(text: passage));
    if (!mounted) return;
    _showReaderSnack('Passage copied');
  }

  Future<void> _openCommentComposer() async {
    final controller = TextEditingController();
    final result = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return Padding(
          padding: EdgeInsets.only(
            left: 16,
            right: 16,
            bottom: MediaQuery.viewInsetsOf(context).bottom + 16,
          ),
          child: Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: AppRadii.br24,
              border: Border.all(color: AppColors.border),
              boxShadow: AppShadows.lg,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Reader Comment', style: AppTypography.h3),
                const SizedBox(height: 8),
                Text(
                  _currentPassage(),
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  style: AppTypography.caption.copyWith(
                    color: AppColors.textSecondary,
                  ),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: controller,
                  minLines: 3,
                  maxLines: 5,
                  autofocus: true,
                  decoration: InputDecoration(
                    hintText: 'Capture a proof loop, question, or action...',
                    filled: true,
                    fillColor: AppColors.surfaceHighlight,
                    enabledBorder: OutlineInputBorder(
                      borderRadius: AppRadii.br16,
                      borderSide: const BorderSide(color: AppColors.border),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: AppRadii.br16,
                      borderSide: const BorderSide(color: AppColors.mint),
                    ),
                    border: OutlineInputBorder(borderRadius: AppRadii.br16),
                  ),
                ),
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  height: 52,
                  child: ElevatedButton(
                    onPressed: () =>
                        Navigator.of(context).pop(controller.text.trim()),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.textPrimary,
                      foregroundColor: Colors.white,
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: AppRadii.br12,
                      ),
                    ),
                    child: const Text('Save Comment'),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
    controller.dispose();

    final comment = result?.trim();
    if (comment == null || comment.isEmpty) return;

    if (_hasSharedResource) {
      _noteController.text = comment;
      await _saveReaderNote();
      return;
    }

    await Clipboard.setData(
      ClipboardData(text: 'Comment on "${widget.title}": $comment'),
    );
    if (!mounted) return;
    _showReaderSnack('Comment copied');
  }

  String _currentPassage() {
    final blocks = widget.markdown
        .split(RegExp(r'\n\s*\n'))
        .map(
          (block) => block
              .replaceAll(RegExp(r'[#>*_`~\[\]\(\)]'), '')
              .replaceAll(RegExp(r'\s+'), ' ')
              .trim(),
        )
        .where((block) => block.length > 32)
        .toList();
    if (blocks.isEmpty) return widget.title;
    final index = (_scrollProgress * (blocks.length - 1)).round().clamp(
      0,
      blocks.length - 1,
    );
    return blocks[index];
  }

  void _showReaderSnack(String message, {bool isError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          message,
          style: AppTypography.captionMedium.copyWith(color: Colors.white),
        ),
        backgroundColor: isError ? AppColors.error : AppColors.textPrimary,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: AppRadii.br12),
        margin: const EdgeInsets.fromLTRB(20, 0, 20, 96),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.surface,
      body: Stack(
        children: [
          CustomScrollView(
            controller: _scrollController,
            slivers: [
              _buildSliverAppBar(),
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(32, 40, 32, 132),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildTitleSection(),
                      const SizedBox(height: 28),
                      _buildMarkdownContent(),
                      if (_hasSharedResource) ...[
                        const SizedBox(height: AppSpacing.s32),
                        ResourceNotesPanel(
                          title: 'Reader notes',
                          hintText:
                              'Capture a proof loop, question, or action...',
                          controller: _noteController,
                          highlights: _highlights,
                          isLoading: _isLoadingHighlights,
                          isSaving: _isSavingHighlight,
                          onSave: _saveReaderNote,
                          onDelete: _deleteReaderNote,
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ],
          ),
          Positioned(
            left: 22,
            right: 22,
            bottom: 28,
            child: _ReadingTools(
              isSaved: _isResourceSaved,
              onHighlight: _highlightCurrentPassage,
              onComment: _openCommentComposer,
              onVault: _toggleReaderVault,
              onNext: _markAsRead,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSliverAppBar() {
    return SliverAppBar(
      backgroundColor: AppColors.surface.withValues(alpha: 0.96),
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      pinned: true,
      toolbarHeight: 80,
      leading: IconButton(
        icon: Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: AppRadii.br12,
            border: Border.all(color: AppColors.border),
          ),
          child: Center(
            child: Icon(Icons.close_rounded, color: AppColors.textSecondary),
          ),
        ),
        onPressed: () => Navigator.of(context).pop(),
      ),
      title: Column(
        children: [
          Text(
            'Immersive_Mode',
            style: AppTypography.captionUpper.copyWith(
              color: AppColors.textTertiary,
              fontSize: 9,
              letterSpacing: 1.4,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            widget.title,
            style: AppTypography.captionMedium.copyWith(
              color: AppColors.textPrimary,
              fontSize: 10,
              fontWeight: FontWeight.w800,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
      centerTitle: true,
      actions: [
        IconButton(
          icon: Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: AppRadii.br12,
              border: Border.all(color: AppColors.border),
            ),
            child: Center(
              child: Icon(
                Icons.text_fields_rounded,
                size: 20,
                color: AppColors.textSecondary,
              ),
            ),
          ),
          onPressed: () {},
        ),
        const SizedBox(width: AppSpacing.s8),
      ],
      bottom: PreferredSize(
        preferredSize: const Size.fromHeight(19),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 0, 24, 16),
          child: Row(
            children: List.generate(8, (index) {
              final active = index / 8 <= _scrollProgress;
              return Expanded(
                child: Container(
                  height: 3,
                  margin: EdgeInsets.only(right: index == 7 ? 0 : 4),
                  decoration: BoxDecoration(
                    color: active ? AppColors.mint : AppColors.borderLight,
                    borderRadius: AppRadii.brFull,
                  ),
                ),
              );
            }),
          ),
        ),
      ),
    );
  }

  Widget _buildTitleSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              widget.durationMinutes == null
                  ? 'CHAPTER 03'
                  : '${widget.durationMinutes} MIN READ',
              style: AppTypography.captionUpper.copyWith(
                color: AppColors.mint,
                fontSize: 10,
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(width: 8),
            const Expanded(child: Divider(color: AppColors.borderLight)),
          ],
        ),
        const SizedBox(height: 24),
        Text(
          widget.title,
          style: AppTypography.readingBold.copyWith(
            fontSize: 32,
            height: 1.18,
            color: AppColors.textPrimary,
          ),
        ),
      ],
    );
  }

  Widget _buildMarkdownContent() {
    return MarkdownBody(
      data: widget.markdown,
      selectable: false,
      styleSheet: _buildMarkdownStyleSheet(),
      onTapLink: (text, href, title) async {
        if (href != null) {
          final uri = Uri.tryParse(href);
          if (uri != null) {
            try {
              await launchUrl(uri, mode: LaunchMode.externalApplication);
            } catch (e) {
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('Could not open link: $href')),
                );
              }
            }
          }
        }
      },
    );
  }

  MarkdownStyleSheet _buildMarkdownStyleSheet() {
    return MarkdownStyleSheet(
      h1: AppTypography.readingBold.copyWith(
        fontSize: 28,
        color: AppColors.textPrimary,
        height: 1.25,
      ),
      h1Padding: const EdgeInsets.only(
        top: AppSpacing.s24,
        bottom: AppSpacing.s12,
      ),
      h2: AppTypography.readingBold.copyWith(
        fontSize: 26,
        color: AppColors.textPrimary,
        height: 1.28,
      ),
      h2Padding: const EdgeInsets.only(
        top: AppSpacing.s20,
        bottom: AppSpacing.s10,
      ),
      h3: AppTypography.h3.copyWith(color: AppColors.textPrimary, height: 1.3),
      h3Padding: const EdgeInsets.only(
        top: AppSpacing.s16,
        bottom: AppSpacing.s8,
      ),
      h4: AppTypography.h4.copyWith(color: AppColors.textPrimary, height: 1.3),
      h4Padding: const EdgeInsets.only(
        top: AppSpacing.s12,
        bottom: AppSpacing.s6,
      ),

      p: AppTypography.body.copyWith(
        color: const Color(0xFF334155),
        fontSize: 18,
        height: 1.8,
      ),
      pPadding: const EdgeInsets.only(bottom: 28),

      // Strong & emphasis
      strong: AppTypography.body.copyWith(
        color: AppColors.textPrimary,
        fontWeight: FontWeight.w700,
      ),
      em: AppTypography.body.copyWith(
        color: AppColors.textPrimary,
        fontStyle: FontStyle.italic,
      ),

      // Links
      a: AppTypography.body.copyWith(
        color: AppColors.accent,
        decoration: TextDecoration.underline,
        decorationColor: AppColors.accent.withValues(alpha: 0.5),
      ),

      // Code
      code: TextStyle(
        fontFamily: 'SF Mono, Menlo, Monaco, monospace',
        fontSize: 14,
        color: AppColors.mint,
        backgroundColor: AppColors.mint.withValues(alpha: 0.1),
        letterSpacing: 0,
      ),
      codeblockDecoration: BoxDecoration(
        color: AppColors.surface2,
        borderRadius: AppRadii.br12,
        border: Border.all(color: AppColors.border),
      ),
      codeblockPadding: const EdgeInsets.all(AppSpacing.s16),

      // Blockquote
      blockquote: AppTypography.body.copyWith(
        color: AppColors.textSecondary,
        fontStyle: FontStyle.italic,
        height: 1.6,
      ),
      blockquoteDecoration: BoxDecoration(
        color: AppColors.mint.withValues(alpha: 0.05),
        borderRadius: const BorderRadius.only(
          topRight: Radius.circular(8),
          bottomRight: Radius.circular(8),
        ),
        border: Border(left: BorderSide(color: AppColors.mint, width: 4)),
      ),
      blockquotePadding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.s16,
        vertical: AppSpacing.s12,
      ),

      // Lists
      listBullet: AppTypography.body.copyWith(color: AppColors.mint),
      listIndent: AppSpacing.s24,
      listBulletPadding: const EdgeInsets.only(right: AppSpacing.s12),

      // Table
      tableHead: AppTypography.bodyMedium.copyWith(
        color: AppColors.textPrimary,
      ),
      tableBody: AppTypography.body.copyWith(color: AppColors.textSecondary),
      tableBorder: TableBorder.all(color: AppColors.border, width: 1),
      tableHeadAlign: TextAlign.left,
      tableCellsPadding: const EdgeInsets.all(AppSpacing.s12),
      tableCellsDecoration: BoxDecoration(
        color: AppColors.surface2.withValues(alpha: 0.5),
      ),

      // Horizontal rule
      horizontalRuleDecoration: BoxDecoration(
        border: Border(top: BorderSide(color: AppColors.border, width: 2)),
      ),

      // Image
      textScaler: TextScaler.linear(1.0),
    );
  }
}

class _ReadingTools extends StatelessWidget {
  const _ReadingTools({
    required this.isSaved,
    required this.onHighlight,
    required this.onComment,
    required this.onVault,
    required this.onNext,
  });

  final bool isSaved;
  final VoidCallback onHighlight;
  final VoidCallback? onComment;
  final VoidCallback onVault;
  final VoidCallback onNext;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        height: 56,
        padding: const EdgeInsets.symmetric(horizontal: 18),
        decoration: BoxDecoration(
          color: AppColors.textPrimary,
          borderRadius: AppRadii.br16,
          boxShadow: AppShadows.lg,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _ReadingToolButton(
              icon: Icons.border_color_rounded,
              label: 'Highlight',
              onTap: onHighlight,
            ),
            const SizedBox(width: 18),
            _ReadingToolButton(
              icon: Icons.add_comment_outlined,
              label: 'Comment',
              onTap: onComment,
            ),
            const SizedBox(width: 18),
            _ReadingToolButton(
              icon: isSaved ? Icons.bookmark : Icons.bookmark_border,
              label: 'Vault',
              onTap: onVault,
            ),
            Container(
              width: 1,
              height: 24,
              margin: const EdgeInsets.symmetric(horizontal: 18),
              color: Colors.white.withValues(alpha: 0.12),
            ),
            InkWell(
              onTap: onNext,
              borderRadius: AppRadii.br12,
              child: Row(
                children: [
                  Text(
                    'Next',
                    style: AppTypography.captionUpper.copyWith(
                      color: Colors.white,
                      fontSize: 10,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(width: 5),
                  const Icon(
                    Icons.chevron_right_rounded,
                    color: Colors.white,
                    size: 18,
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

class _ReadingToolButton extends StatelessWidget {
  const _ReadingToolButton({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: AppRadii.br12,
      child: Opacity(
        opacity: onTap == null ? 0.45 : 1,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: Colors.white, size: 19),
            const SizedBox(height: 2),
            Text(
              label,
              style: AppTypography.captionUpper.copyWith(
                color: Colors.white,
                fontSize: 8,
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
