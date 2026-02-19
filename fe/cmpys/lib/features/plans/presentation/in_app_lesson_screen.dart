import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../app/assets.dart';
import '../../../app/design_tokens.dart';
import '../../../core/ui/cmpys_button.dart';

/// Screen to display in-app lesson content with markdown rendering.
class InAppLessonScreen extends ConsumerStatefulWidget {
  const InAppLessonScreen({
    super.key,
    required this.title,
    required this.markdown,
    this.materialId,
    this.durationMinutes,
    this.onMarkAsRead,
  });

  final String title;
  final String markdown;
  final String? materialId;
  final int? durationMinutes;
  final VoidCallback? onMarkAsRead;

  @override
  ConsumerState<InAppLessonScreen> createState() => _InAppLessonScreenState();
}

class _InAppLessonScreenState extends ConsumerState<InAppLessonScreen> {
  final ScrollController _scrollController = ScrollController();
  bool _isMarkedAsRead = false;
  bool _hasScrolledToBottom = false;
  double _scrollProgress = 0;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (!_scrollController.hasClients) return;

    final maxScroll = _scrollController.position.maxScrollExtent;
    final currentScroll = _scrollController.offset;

    setState(() {
      _scrollProgress = maxScroll > 0 ? (currentScroll / maxScroll).clamp(0, 1) : 1;

      // Consider "scrolled to bottom" when user has seen 90% of content
      if (_scrollProgress >= 0.9) {
        _hasScrolledToBottom = true;
      }
    });
  }

  void _markAsRead() {
    setState(() {
      _isMarkedAsRead = true;
    });

    // Call the callback if provided
    widget.onMarkAsRead?.call();

    // Show confirmation
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            SvgPicture.asset(
              AppAssets.iconCheckCircle,
              width: 20,
              height: 20,
              colorFilter: const ColorFilter.mode(
                AppColors.textPrimary,
                BlendMode.srcIn,
              ),
            ),
            const SizedBox(width: AppSpacing.s12),
            const Text('Marked as read'),
          ],
        ),
        backgroundColor: AppColors.success,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: AppRadii.br12),
        margin: const EdgeInsets.all(AppSpacing.s16),
      ),
    );
  }

  Future<void> _copyToClipboard() async {
    await Clipboard.setData(ClipboardData(text: widget.markdown));
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Content copied to clipboard'),
          backgroundColor: AppColors.surface,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: AppRadii.br12),
          margin: const EdgeInsets.all(AppSpacing.s16),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      body: CustomScrollView(
        controller: _scrollController,
        slivers: [
          // Custom App Bar
          _buildSliverAppBar(),

          // Content
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.s24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SizedBox(height: AppSpacing.s24),

                  // Title section
                  _buildTitleSection(),
                  const SizedBox(height: AppSpacing.s24),

                  // Markdown content
                  _buildMarkdownContent(),
                  const SizedBox(height: AppSpacing.s32),

                  // Mark as read button
                  _buildMarkAsReadButton(),
                  const SizedBox(height: AppSpacing.s48),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSliverAppBar() {
    return SliverAppBar(
      backgroundColor: AppColors.bg,
      elevation: 0,
      pinned: true,
      expandedHeight: 0,
      leading: IconButton(
        icon: Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: AppRadii.brFull,
          ),
          child: Center(
            child: SvgPicture.asset(
              AppAssets.iconArrowLeft,
              width: 20,
              height: 20,
              colorFilter: const ColorFilter.mode(
                AppColors.textPrimary,
                BlendMode.srcIn,
              ),
            ),
          ),
        ),
        onPressed: () => Navigator.of(context).pop(),
      ),
      actions: [
        // Copy button
        IconButton(
          icon: Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: AppRadii.brFull,
            ),
            child: Center(
              child: SvgPicture.asset(
                AppAssets.iconCopy,
                width: 18,
                height: 18,
                colorFilter: const ColorFilter.mode(
                  AppColors.textSecondary,
                  BlendMode.srcIn,
                ),
              ),
            ),
          ),
          onPressed: _copyToClipboard,
        ),
        const SizedBox(width: AppSpacing.s8),
      ],
      // Progress indicator at the bottom of app bar
      bottom: PreferredSize(
        preferredSize: const Size.fromHeight(3),
        child: LinearProgressIndicator(
          value: _scrollProgress,
          backgroundColor: AppColors.surface2,
          valueColor: AlwaysStoppedAnimation(
            _isMarkedAsRead ? AppColors.success : AppColors.accent,
          ),
          minHeight: 3,
        ),
      ),
    );
  }

  Widget _buildTitleSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Lesson badge
        Row(
          children: [
            Container(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.s12,
                vertical: AppSpacing.s6,
              ),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    AppColors.accent.withOpacity(0.2),
                    AppColors.accentLight.withOpacity(0.1),
                  ],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: AppRadii.brFull,
                border: Border.all(
                  color: AppColors.accent.withOpacity(0.3),
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SvgPicture.asset(
                    AppAssets.iconBookOpen,
                    width: 14,
                    height: 14,
                    colorFilter: const ColorFilter.mode(
                      AppColors.accent,
                      BlendMode.srcIn,
                    ),
                  ),
                  const SizedBox(width: AppSpacing.s6),
                  Text(
                    'Lesson',
                    style: AppTypography.caption.copyWith(
                      color: AppColors.accent,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
            if (_isMarkedAsRead) ...[
              const SizedBox(width: AppSpacing.s8),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.s10,
                  vertical: AppSpacing.s6,
                ),
                decoration: BoxDecoration(
                  color: AppColors.success.withOpacity(0.15),
                  borderRadius: AppRadii.brFull,
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SvgPicture.asset(
                      AppAssets.iconCheck,
                      width: 12,
                      height: 12,
                      colorFilter: const ColorFilter.mode(
                        AppColors.success,
                        BlendMode.srcIn,
                      ),
                    ),
                    const SizedBox(width: AppSpacing.s4),
                    Text(
                      'Read',
                      style: AppTypography.caption.copyWith(
                        color: AppColors.success,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
        const SizedBox(height: AppSpacing.s16),

        // Title
        Text(
          widget.title,
          style: AppTypography.h1.copyWith(
            height: 1.2,
          ),
        ),

        // Duration
        if (widget.durationMinutes != null) ...[
          const SizedBox(height: AppSpacing.s12),
          Row(
            children: [
              SvgPicture.asset(
                AppAssets.iconClock,
                width: 16,
                height: 16,
                colorFilter: const ColorFilter.mode(
                  AppColors.textTertiary,
                  BlendMode.srcIn,
                ),
              ),
              const SizedBox(width: AppSpacing.s6),
              Text(
                '${widget.durationMinutes} min read',
                style: AppTypography.body.copyWith(
                  color: AppColors.textTertiary,
                ),
              ),
              const SizedBox(width: AppSpacing.s16),
              Container(
                width: 4,
                height: 4,
                decoration: BoxDecoration(
                  color: AppColors.textTertiary,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: AppSpacing.s16),
              Text(
                '${(widget.markdown.split(' ').length / 200).ceil()} min',
                style: AppTypography.body.copyWith(
                  color: AppColors.textTertiary,
                ),
              ),
              Text(
                ' based on ~200 wpm',
                style: AppTypography.caption.copyWith(
                  color: AppColors.textTertiary.withOpacity(0.7),
                ),
              ),
            ],
          ),
        ],
      ],
    );
  }

  Widget _buildMarkdownContent() {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface.withOpacity(0.5),
        borderRadius: AppRadii.br16,
        border: Border.all(
          color: AppColors.border.withOpacity(0.5),
        ),
      ),
      padding: const EdgeInsets.all(AppSpacing.s20),
      child: MarkdownBody(
        data: widget.markdown,
        selectable: true,
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
      ),
    );
  }

  MarkdownStyleSheet _buildMarkdownStyleSheet() {
    return MarkdownStyleSheet(
      // Headings
      h1: AppTypography.h1.copyWith(
        color: AppColors.textPrimary,
        height: 1.3,
      ),
      h1Padding: const EdgeInsets.only(top: AppSpacing.s24, bottom: AppSpacing.s12),
      h2: AppTypography.h2.copyWith(
        color: AppColors.textPrimary,
        height: 1.3,
      ),
      h2Padding: const EdgeInsets.only(top: AppSpacing.s20, bottom: AppSpacing.s10),
      h3: AppTypography.h3.copyWith(
        color: AppColors.textPrimary,
        height: 1.3,
      ),
      h3Padding: const EdgeInsets.only(top: AppSpacing.s16, bottom: AppSpacing.s8),
      h4: AppTypography.h4.copyWith(
        color: AppColors.textPrimary,
        height: 1.3,
      ),
      h4Padding: const EdgeInsets.only(top: AppSpacing.s12, bottom: AppSpacing.s6),

      // Paragraphs
      p: AppTypography.body.copyWith(
        color: AppColors.textPrimary,
        height: 1.7,
        letterSpacing: 0.2,
      ),
      pPadding: const EdgeInsets.only(bottom: AppSpacing.s16),

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
        decorationColor: AppColors.accent.withOpacity(0.5),
      ),

      // Code
      code: TextStyle(
        fontFamily: 'SF Mono, Menlo, Monaco, monospace',
        fontSize: 14,
        color: AppColors.accent,
        backgroundColor: AppColors.accent.withOpacity(0.1),
        letterSpacing: -0.5,
      ),
      codeblockDecoration: BoxDecoration(
        color: AppColors.surface2,
        borderRadius: AppRadii.br12,
        border: Border.all(
          color: AppColors.border,
        ),
      ),
      codeblockPadding: const EdgeInsets.all(AppSpacing.s16),

      // Blockquote
      blockquote: AppTypography.body.copyWith(
        color: AppColors.textSecondary,
        fontStyle: FontStyle.italic,
        height: 1.6,
      ),
      blockquoteDecoration: BoxDecoration(
        color: AppColors.accent.withOpacity(0.05),
        borderRadius: const BorderRadius.only(
          topRight: Radius.circular(8),
          bottomRight: Radius.circular(8),
        ),
        border: Border(
          left: BorderSide(
            color: AppColors.accent,
            width: 4,
          ),
        ),
      ),
      blockquotePadding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.s16,
        vertical: AppSpacing.s12,
      ),

      // Lists
      listBullet: AppTypography.body.copyWith(
        color: AppColors.accent,
      ),
      listIndent: AppSpacing.s24,
      listBulletPadding: const EdgeInsets.only(right: AppSpacing.s12),

      // Table
      tableHead: AppTypography.bodyMedium.copyWith(
        color: AppColors.textPrimary,
      ),
      tableBody: AppTypography.body.copyWith(
        color: AppColors.textSecondary,
      ),
      tableBorder: TableBorder.all(
        color: AppColors.border,
        width: 1,
      ),
      tableHeadAlign: TextAlign.left,
      tableCellsPadding: const EdgeInsets.all(AppSpacing.s12),
      tableCellsDecoration: BoxDecoration(
        color: AppColors.surface2.withOpacity(0.5),
      ),

      // Horizontal rule
      horizontalRuleDecoration: BoxDecoration(
        border: Border(
          top: BorderSide(
            color: AppColors.border,
            width: 2,
          ),
        ),
      ),

      // Image
      textScaler: TextScaler.linear(1.0),
    );
  }

  Widget _buildMarkAsReadButton() {
    return Column(
      children: [
        // Completion prompt
        if (!_isMarkedAsRead && _hasScrolledToBottom) ...[
          Container(
            padding: const EdgeInsets.all(AppSpacing.s16),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  AppColors.success.withOpacity(0.1),
                  AppColors.success.withOpacity(0.05),
                ],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: AppRadii.br16,
              border: Border.all(
                color: AppColors.success.withOpacity(0.2),
              ),
            ),
            child: Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: AppColors.success.withOpacity(0.15),
                    borderRadius: AppRadii.br12,
                  ),
                  child: Center(
                    child: SvgPicture.asset(
                      AppAssets.iconTrophy,
                      width: 22,
                      height: 22,
                      colorFilter: const ColorFilter.mode(
                        AppColors.success,
                        BlendMode.srcIn,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: AppSpacing.s12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Great progress!',
                        style: AppTypography.bodyMedium.copyWith(
                          color: AppColors.success,
                        ),
                      ),
                      const SizedBox(height: AppSpacing.s2),
                      Text(
                        'You\'ve read through this lesson. Mark it complete!',
                        style: AppTypography.caption.copyWith(
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.s16),
        ],

        // Button
        CmpysButton(
          label: _isMarkedAsRead ? 'Completed' : 'Mark as Read',
          icon: _isMarkedAsRead ? AppAssets.iconCheckCircle : AppAssets.iconCheck,
          variant: _isMarkedAsRead
              ? CmpysButtonVariant.secondary
              : CmpysButtonVariant.primary,
          onPressed: _isMarkedAsRead ? null : _markAsRead,
          isExpanded: true,
        ),

        // Skip note
        if (!_isMarkedAsRead && !_hasScrolledToBottom) ...[
          const SizedBox(height: AppSpacing.s12),
          Text(
            'Scroll to the bottom to mark as read',
            style: AppTypography.caption.copyWith(
              color: AppColors.textTertiary,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ],
    );
  }
}
