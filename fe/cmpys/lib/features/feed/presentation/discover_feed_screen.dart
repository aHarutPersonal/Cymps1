import 'dart:math';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../../app/design_tokens.dart';
import '../../../core/ui/prototype_grid_background.dart';
import '../../session/providers/library_provider.dart';
import '../data/feed_repository.dart';
import '../models/feed_models.dart';
import '../providers/feed_preloader.dart';

/// Prototype-style idea stack feed with social actions.
class DiscoverFeedScreen extends ConsumerStatefulWidget {
  const DiscoverFeedScreen({super.key});

  @override
  ConsumerState<DiscoverFeedScreen> createState() => _DiscoverFeedScreenState();
}

class _DiscoverFeedScreenState extends ConsumerState<DiscoverFeedScreen> {
  final PageController _pageController = PageController();

  final List<FeedItem> _items = [];
  bool _isLoading = true;
  bool _isLoadingMore = false;
  bool _hasMore = true;
  String? _error;
  int _apiPage = 1;
  late int _seed;

  // Saves now tracked via library provider

  static const int _pageSize = 10;

  @override
  void initState() {
    super.initState();
    _seed = Random().nextInt(999999);
    _pageController.addListener(_onPageScroll);
    _tryLoadFromCache();
  }

  void _onPageScroll() {
    if (!_pageController.hasClients || _items.isEmpty) return;

    final page = _pageController.page ?? _pageController.initialPage.toDouble();
    if (page >= _items.length - 2.5) {
      _loadMore();
    }
  }

  List<FeedItem> _textIdeas(List<FeedItem> items) {
    return items.where((item) => item.type.toLowerCase() != 'video').toList();
  }

  /// Try to load from preloaded cache first; fall back to API.
  void _tryLoadFromCache() {
    final cacheState = ref.read(feedCacheProvider);
    cacheState.when(
      data: (cache) {
        if (cache.items.isNotEmpty) {
          setState(() {
            _items.clear();
            _items.addAll(_textIdeas(cache.items));
            _hasMore = cache.hasMore;
            _seed = cache.seed;
            _apiPage = 1;
            _isLoading = false;
          });
        } else {
          _loadFeed();
        }
      },
      loading: () => _loadFeed(),
      error: (error, stackTrace) => _loadFeed(),
    );
  }

  Future<void> _loadFeed() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });
    try {
      final repo = ref.read(feedRepositoryProvider);
      final response = await repo.getFeed(
        page: 1,
        pageSize: _pageSize,
        seed: _seed,
      );
      if (mounted) {
        setState(() {
          _items.clear();
          _items.addAll(_textIdeas(response.items));
          _hasMore = response.hasMore;
          _apiPage = 1;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _loadMore() async {
    if (_isLoadingMore || !_hasMore) return;
    _isLoadingMore = true;
    try {
      final repo = ref.read(feedRepositoryProvider);
      final response = await repo.getFeed(
        page: _apiPage + 1,
        pageSize: _pageSize,
        seed: _seed,
      );
      if (mounted) {
        setState(() {
          _items.addAll(_textIdeas(response.items));
          _hasMore = response.hasMore;
          _apiPage += 1;
          _isLoadingMore = false;
        });
      }
    } catch (_) {
      _isLoadingMore = false;
    }
  }

  Future<void> _refresh() async {
    _seed = Random().nextInt(999999);
    if (_pageController.hasClients) {
      _pageController.jumpToPage(0);
    }
    await _loadFeed();
  }

  Future<void> _toggleLike(int index) async {
    HapticFeedback.lightImpact();
    final item = _items[index];

    // Optimistic update
    setState(() {
      _items[index] = item.copyWith(
        isLiked: !item.isLiked,
        likeCount: item.isLiked ? item.likeCount - 1 : item.likeCount + 1,
      );
    });

    try {
      final repo = ref.read(feedRepositoryProvider);
      final result = await repo.toggleLike(item.id);
      if (mounted) {
        setState(() {
          _items[index] = _items[index].copyWith(
            isLiked: result['is_liked'] as bool,
            likeCount: result['like_count'] as int,
          );
        });
      }
    } catch (_) {
      // Revert on error
      if (mounted) {
        setState(() {
          _items[index] = item;
        });
      }
    }
  }

  void _toggleSave(FeedItem item) {
    HapticFeedback.mediumImpact();
    final savedItem = SavedItem(
      id: 'feed_${item.id}',
      title: item.title,
      content: item.content ?? '',
      category: item.category ?? item.type,
      type: 'card',
      source: item.source,
    );
    ref.read(libraryProvider.notifier).toggleItem(savedItem);
  }

  void _openComments(FeedItem item, int index) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _CommentsSheet(
        item: item,
        repository: ref.read(feedRepositoryProvider),
        onCommentAdded: () {
          // Increment comment count locally
          if (mounted) {
            setState(() {
              _items[index] = _items[index].copyWith(
                commentCount: _items[index].commentCount + 1,
              );
            });
          }
        },
      ),
    );
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      body: PrototypeGridBackground(
        child: _isLoading
            ? _buildLoading()
            : _error != null
            ? _buildError()
            : _items.isEmpty
            ? _buildEmpty()
            : _buildFeed(),
      ),
    );
  }

  Widget _buildLoading() {
    return const Center(
      child: CircularProgressIndicator(color: AppColors.accent),
    );
  }

  Widget _buildError() {
    return Center(
      child: Padding(
        padding: AppSpacing.p24,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              PhosphorIconsRegular.warningCircle,
              color: AppColors.textTertiary,
              size: 48,
            ),
            const SizedBox(height: 16),
            Text('Daily Insights Unavailable', style: AppTypography.h3),
            const SizedBox(height: 12),
            TextButton(
              onPressed: _loadFeed,
              child: const Text(
                'Retry',
                style: TextStyle(color: AppColors.accent),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmpty() {
    return Center(
      child: Padding(
        padding: AppSpacing.p24,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.explore_outlined,
              color: AppColors.textTertiary,
              size: 64,
            ),
            const SizedBox(height: 20),
            Text('No insights yet', style: AppTypography.h3),
          ],
        ),
      ),
    );
  }

  Widget _buildFeed() {
    final topPadding = MediaQuery.paddingOf(context).top + 138;

    return Stack(
      children: [
        RefreshIndicator(
          onRefresh: _refresh,
          color: AppColors.accent,
          backgroundColor: AppColors.surface,
          child: Padding(
            padding: EdgeInsets.only(top: topPadding, bottom: AppSpacing.floatingNavBarHeight),
            child: PageView.builder(
              controller: _pageController,
              scrollDirection: Axis.vertical,
              clipBehavior: Clip.none,
              physics: const BouncingScrollPhysics(
                parent: AlwaysScrollableScrollPhysics(),
              ),
              itemCount: _items.length + (_isLoadingMore ? 1 : 0),
              itemBuilder: (context, index) {
                if (index == _items.length) {
                  return const Center(
                    child: CircularProgressIndicator(color: AppColors.accent),
                  );
                }

                final item = _items[index];
                final isSaved = ref.watch(
                  libraryProvider.select(
                    (items) => items.any((e) => e.id == 'feed_${item.id}'),
                  ),
                );

                return _AnimatedIdeaPage(
                  controller: _pageController,
                  index: index,
                  child: _IdeaStackPage(
                    child: _IdeaStackCard(
                      item: item,
                      isSaved: isSaved,
                      onLike: () => _toggleLike(index),
                      onComment: () => _openComments(item, index),
                      onSave: () => _toggleSave(item),
                      onShare: () {
                        final text = item.content ?? item.title;
                        Clipboard.setData(ClipboardData(text: text));
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('Copied to clipboard'),
                            backgroundColor: AppColors.charcoal,
                            duration: Duration(seconds: 1),
                          ),
                        );
                      },
                    ),
                  ),
                );
              },
            ),
          ),
        ),

        Positioned(
          top: MediaQuery.paddingOf(context).top + 70,
          left: 24,
          right: 24,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Ideas',
                    style: AppTypography.captionUpper.copyWith(
                      color: AppColors.mint,
                      fontSize: 9,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 1.2,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'Daily Insights',
                    style: AppTypography.h2.copyWith(
                      fontWeight: FontWeight.w900,
                      color: AppColors.textPrimary,
                    ),
                  ),
                ],
              ),
              _PrototypeIconButton(
                icon: PhosphorIconsRegular.slidersHorizontal,
                tooltip: 'Filter ideas',
                onTap: _refresh,
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _AnimatedIdeaPage extends StatelessWidget {
  const _AnimatedIdeaPage({
    required this.controller,
    required this.index,
    required this.child,
  });

  final PageController controller;
  final int index;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      child: child,
      builder: (context, child) {
        var page = controller.initialPage.toDouble();
        if (controller.hasClients && controller.position.haveDimensions) {
          page = controller.page ?? page;
        }

        final distance = (page - index).clamp(-1.0, 1.0).abs();
        final scale = lerpDouble(1, 0.9, distance)!;
        final opacity = lerpDouble(1, 0.52, distance)!;
        final yOffset = lerpDouble(0, 28, distance)!;

        return Transform.translate(
          offset: Offset(0, yOffset),
          child: Transform.scale(
            scale: scale,
            child: Opacity(opacity: opacity, child: child),
          ),
        );
      },
    );
  }
}

class _IdeaStackPage extends StatelessWidget {
  const _IdeaStackPage({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final cardHeight = min(500.0, MediaQuery.sizeOf(context).height * 0.54);
    return Center(
      child: SizedBox(
        height: cardHeight + 34,
        child: Stack(
          alignment: Alignment.center,
          children: [
            Positioned(
              top: 0,
              left: 24,
              right: 24,
              child: Transform.scale(
                scale: 0.92,
                child: Container(
                  height: cardHeight,
                  decoration: BoxDecoration(
                    color: AppColors.surface.withValues(alpha: 0.42),
                    borderRadius: AppRadii.br16,
                    border: Border.all(color: AppColors.border),
                  ),
                ),
              ),
            ),
            Positioned(
              left: 22,
              right: 22,
              bottom: 0,
              child: SizedBox(height: cardHeight, child: child),
            ),
          ],
        ),
      ),
    );
  }
}

class _IdeaStackCard extends StatelessWidget {
  const _IdeaStackCard({
    required this.item,
    required this.isSaved,
    required this.onLike,
    required this.onComment,
    required this.onSave,
    required this.onShare,
  });

  final FeedItem item;
  final bool isSaved;
  final VoidCallback onLike;
  final VoidCallback onComment;
  final VoidCallback onSave;
  final VoidCallback onShare;

  @override
  Widget build(BuildContext context) {
    final content = (item.reason ?? item.content ?? '').trim();
    final quote = _quoteFrom(content);
    final body = _bodyFrom(content, quote);
    final source = item.source?.trim().isNotEmpty == true
        ? item.source!.trim()
        : 'CMPYS Mentor';

    return Container(
      padding: const EdgeInsets.all(28),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: AppRadii.br16,
        border: Border.all(color: AppColors.border),
        boxShadow: [
          BoxShadow(
            color: AppColors.textPrimary.withValues(alpha: 0.08),
            blurRadius: 40,
            offset: const Offset(0, 20),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Category: ${(item.category ?? item.type).toUpperCase()}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTypography.captionUpper.copyWith(
                        color: AppColors.mint,
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 1.2,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      'Source: $source',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTypography.captionUpper.copyWith(
                        color: AppColors.textTertiary,
                        fontSize: 9,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
              _SmallIconTap(
                icon: isSaved
                    ? PhosphorIconsFill.bookmarkSimple
                    : PhosphorIconsRegular.bookmarkSimple,
                color: isSaved ? AppColors.mint : AppColors.textTertiary,
                tooltip: isSaved ? 'Saved' : 'Save',
                onTap: onSave,
              ),
            ],
          ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 24),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item.title,
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                    style: AppTypography.h3.copyWith(
                      fontSize: 20,
                      fontWeight: FontWeight.w800,
                      color: AppColors.textPrimary,
                      height: 1.25,
                    ),
                  ),
                  const SizedBox(height: 20),
                  Text(
                    quote.isEmpty ? '"${item.title}"' : '"$quote"',
                    maxLines: 5,
                    overflow: TextOverflow.ellipsis,
                    style: AppTypography.readingQuote.copyWith(
                      color: AppColors.textPrimary,
                      fontSize: 24,
                      fontWeight: FontWeight.w600,
                      height: 1.45,
                    ),
                  ),
                  if (body.isNotEmpty) ...[
                    const SizedBox(height: 20),
                    Text(
                      body,
                      maxLines: 5,
                      overflow: TextOverflow.ellipsis,
                      style: AppTypography.bodyMedium.copyWith(
                        color: AppColors.textSecondary,
                        height: 1.48,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
          Container(
            padding: const EdgeInsets.only(top: 20),
            decoration: const BoxDecoration(
              border: Border(top: BorderSide(color: AppColors.borderLight)),
            ),
            child: Row(
              children: [
                _FooterAction(
                  icon: item.isLiked
                      ? PhosphorIconsFill.heart
                      : PhosphorIconsRegular.heart,
                  label: item.likeCount > 0
                      ? _compactCount(item.likeCount)
                      : '',
                  color: item.isLiked
                      ? AppColors.brandAccent
                      : AppColors.textTertiary,
                  onTap: onLike,
                ),
                const SizedBox(width: 16),
                _FooterAction(
                  icon: PhosphorIconsRegular.shareNetwork,
                  label: '',
                  color: AppColors.textTertiary,
                  onTap: onShare,
                ),
                const Spacer(),
                GestureDetector(
                  onTap: onComment,
                  behavior: HitTestBehavior.opaque,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      color: AppColors.surfaceHighlight,
                      borderRadius: AppRadii.br8,
                      border: Border.all(color: AppColors.borderLight),
                    ),
                    child: Text(
                      'DETAILS',
                      style: AppTypography.captionUpper.copyWith(
                        color: AppColors.textSecondary,
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  static String _quoteFrom(String value) {
    if (value.isEmpty) return '';
    final normalized = value.replaceAll(RegExp(r'\s+'), ' ').trim();
    final match = RegExp(r'^(.{32,180}?[.!?])\s+').firstMatch(normalized);
    if (match != null) return match.group(1)!.trim();
    return normalized.length > 180
        ? '${normalized.substring(0, 177).trim()}...'
        : normalized;
  }

  static String _bodyFrom(String value, String quote) {
    if (value.isEmpty || quote.isEmpty) return '';
    final normalized = value.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (normalized == quote || !normalized.startsWith(quote)) return '';
    return normalized.substring(quote.length).trim();
  }

  static String _compactCount(int count) {
    if (count >= 1000000) return '${(count / 1000000).toStringAsFixed(1)}M';
    if (count >= 1000) return '${(count / 1000).toStringAsFixed(1)}K';
    return '$count';
  }
}

class _PrototypeIconButton extends StatelessWidget {
  const _PrototypeIconButton({
    required this.icon,
    required this.tooltip,
    required this.onTap,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: AppRadii.br12,
            border: Border.all(color: AppColors.border),
          ),
          child: Icon(icon, color: AppColors.textPrimary, size: 20),
        ),
      ),
    );
  }
}

class _SmallIconTap extends StatelessWidget {
  const _SmallIconTap({
    required this.icon,
    required this.color,
    required this.tooltip,
    required this.onTap,
  });

  final IconData icon;
  final Color color;
  final String tooltip;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: SizedBox(
          width: 36,
          height: 36,
          child: Icon(icon, color: color, size: 22),
        ),
      ),
    );
  }
}

class _FooterAction extends StatelessWidget {
  const _FooterAction({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: color, size: 18),
          if (label.isNotEmpty) ...[
            const SizedBox(width: 7),
            Text(
              label,
              style: AppTypography.captionUpper.copyWith(
                color: AppColors.textTertiary,
                fontSize: 10,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

// =============================================================================
// Comments Bottom Sheet — loads from API, submits to API
// =============================================================================

class _CommentsSheet extends StatefulWidget {
  const _CommentsSheet({
    required this.item,
    required this.repository,
    required this.onCommentAdded,
  });
  final FeedItem item;
  final FeedRepository repository;
  final VoidCallback onCommentAdded;

  @override
  State<_CommentsSheet> createState() => _CommentsSheetState();
}

class _CommentsSheetState extends State<_CommentsSheet> {
  final _controller = TextEditingController();
  List<FeedComment> _comments = [];
  bool _isLoading = true;
  bool _isSending = false;

  @override
  void initState() {
    super.initState();
    _loadComments();
  }

  Future<void> _loadComments() async {
    try {
      final comments = await widget.repository.getComments(widget.item.id);
      if (mounted) {
        setState(() {
          _comments = comments;
          _isLoading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _addComment() async {
    final text = _controller.text.trim();
    if (text.isEmpty || _isSending) return;

    setState(() => _isSending = true);
    try {
      final comment = await widget.repository.addComment(widget.item.id, text);
      if (mounted) {
        setState(() {
          _comments.add(comment);
          _controller.clear();
          _isSending = false;
        });
        widget.onCommentAdded();
      }
    } catch (_) {
      if (mounted) setState(() => _isSending = false);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;

    return Container(
      height: MediaQuery.of(context).size.height * 0.6,
      decoration: const BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Column(
        children: [
          // Handle
          Container(
            margin: const EdgeInsets.only(top: 12, bottom: 8),
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: AppColors.borderFocus,
              borderRadius: BorderRadius.circular(2),
            ),
          ),

          // Title
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Comments',
                  style: AppTypography.h3.copyWith(fontSize: 16),
                ),
                Text(
                  '${_comments.length}',
                  style: AppTypography.body.copyWith(
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
            ),
          ),

          const Divider(color: AppColors.border, height: 1),

          // Comments list
          Expanded(
            child: _isLoading
                ? const Center(
                    child: CircularProgressIndicator(color: AppColors.accent),
                  )
                : _comments.isEmpty
                ? Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.chat_bubble_outline,
                          color: AppColors.textTertiary,
                          size: 48,
                        ),
                        const SizedBox(height: 12),
                        Text(
                          'No comments yet',
                          style: AppTypography.caption.copyWith(
                            color: AppColors.textSecondary,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Be the first to share your thoughts',
                          style: AppTypography.caption.copyWith(
                            color: AppColors.textTertiary,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.all(16),
                    itemCount: _comments.length,
                    itemBuilder: (_, i) {
                      final c = _comments[i];
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 16),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            CircleAvatar(
                              radius: 16,
                              backgroundColor: AppColors.accent.withValues(
                                alpha: 0.2,
                              ),
                              child: const Icon(
                                Icons.person,
                                color: AppColors.accent,
                                size: 18,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Text(
                                        c.userName ?? 'User',
                                        style: const TextStyle(
                                          color: AppColors.textPrimary,
                                          fontWeight: FontWeight.w600,
                                          fontSize: 13,
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      Text(
                                        _formatTime(c.createdAt),
                                        style: const TextStyle(
                                          color: AppColors.textTertiary,
                                          fontSize: 11,
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    c.text,
                                    style: const TextStyle(
                                      color: AppColors.textSecondary,
                                      fontSize: 14,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
          ),

          // Input field
          Padding(
            padding: EdgeInsets.only(
              left: 12,
              right: 12,
              bottom: bottomInset + 12,
              top: 8,
            ),
            child: Container(
              decoration: BoxDecoration(
                color: AppColors.surfaceHighlight,
                borderRadius: BorderRadius.circular(24),
                border: Border.all(color: AppColors.border),
              ),
              child: Row(
                children: [
                  const SizedBox(width: 16),
                  Expanded(
                    child: TextField(
                      controller: _controller,
                      style: const TextStyle(
                        color: AppColors.textPrimary,
                        fontSize: 14,
                      ),
                      decoration: const InputDecoration(
                        hintText: 'Add a comment...',
                        hintStyle: TextStyle(color: AppColors.textTertiary),
                        border: InputBorder.none,
                        contentPadding: EdgeInsets.symmetric(vertical: 12),
                      ),
                      onSubmitted: (_) => _addComment(),
                    ),
                  ),
                  _isSending
                      ? const Padding(
                          padding: EdgeInsets.all(12),
                          child: SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: AppColors.accent,
                            ),
                          ),
                        )
                      : IconButton(
                          onPressed: _addComment,
                          icon: const Icon(
                            Icons.send_rounded,
                            color: AppColors.accent,
                            size: 22,
                          ),
                        ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _formatTime(DateTime t) {
    final diff = DateTime.now().difference(t);
    if (diff.inSeconds < 60) return 'Just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    return '${diff.inDays}d ago';
  }
}
