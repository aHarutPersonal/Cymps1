import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/design_tokens.dart';
import '../../../app/router.dart';
import '../../../core/ui/ambient_background.dart';
import '../data/chat_repository.dart';
import '../models/chat_models.dart';

/// Screen displaying a list of past chat threads.
class ChatThreadsScreen extends ConsumerStatefulWidget {
  const ChatThreadsScreen({super.key, this.isEmbedded = false});

  final bool isEmbedded;

  @override
  ConsumerState<ChatThreadsScreen> createState() => _ChatThreadsScreenState();
}

class _ChatThreadsScreenState extends ConsumerState<ChatThreadsScreen> {
  bool _isLoading = true;
  String? _error;
  List<ChatThread> _threads = [];

  @override
  void initState() {
    super.initState();
    _loadThreads();
  }

  Future<void> _loadThreads() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final repo = ref.read(chatRepositoryProvider);
      final response = await repo.getThreads(limit: 50);
      if (!mounted) return;
      setState(() {
        _threads = response.threads;
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _error = 'Failed to load chat history';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      body: AmbientBackground(
        useSafeArea: false,
        child: SafeArea(
          bottom: false,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header
              Padding(
                padding: EdgeInsets.only(
                  left: 24,
                  right: 24,
                  top: widget.isEmbedded ? 60 : 12,
                  bottom: 12,
                ),
                child: Row(
                  children: [
                    if (!widget.isEmbedded) ...[
                      GestureDetector(
                        onTap: () {
                          if (context.canPop()) {
                            context.pop();
                          } else {
                            context.go(AppRoutes.home);
                          }
                        },
                        child: Container(
                          width: 40,
                          height: 40,
                          decoration: BoxDecoration(
                            color: AppColors.surface,
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(
                            Icons.arrow_back,
                            size: 20,
                            color: AppColors.textPrimary,
                          ),
                        ),
                      ),
                      const SizedBox(width: 16),
                    ],
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Chat History',
                            style: AppTypography.h3.copyWith(
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          if (_threads.isNotEmpty)
                            Text(
                              '${_threads.length} conversation${_threads.length != 1 ? 's' : ''}',
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

              const Divider(height: 1, color: AppColors.glassBorder),

              // Content
              Expanded(
                child: _isLoading
                    ? const Center(
                        child: CircularProgressIndicator(
                          color: AppColors.accent,
                        ),
                      )
                    : _error != null
                    ? _buildError()
                    : _threads.isEmpty
                    ? _buildEmpty()
                    : _buildThreadList(),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildError() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.error_outline, size: 48, color: AppColors.textTertiary),
          const SizedBox(height: 16),
          Text(
            _error!,
            style: AppTypography.body.copyWith(color: AppColors.textSecondary),
          ),
          const SizedBox(height: 16),
          TextButton(onPressed: _loadThreads, child: const Text('Retry')),
        ],
      ),
    );
  }

  Widget _buildEmpty() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 72,
            height: 72,
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: AppRadii.br24,
            ),
            child: Center(
              child: Icon(
                Icons.chat_bubble_outline,
                size: 32,
                color: AppColors.textTertiary,
              ),
            ),
          ),
          const SizedBox(height: 20),
          Text('No conversations yet', style: AppTypography.h3),
          const SizedBox(height: 8),
          Text(
            'Start chatting with your idol\nto see your history here',
            style: AppTypography.body.copyWith(color: AppColors.textSecondary),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _buildThreadList() {
    return RefreshIndicator(
      color: AppColors.accent,
      onRefresh: _loadThreads,
      child: ListView.separated(
        padding: const EdgeInsets.only(
          top: 8,
          bottom: AppSpacing.floatingNavBarHeight,
        ),
        itemCount: _threads.length,
        separatorBuilder: (_, _) =>
            const Divider(height: 1, indent: 80, color: AppColors.glassBorder),
        itemBuilder: (context, index) {
          final thread = _threads[index];
          return _ThreadTile(thread: thread, onTap: () => _openThread(thread));
        },
      ),
    );
  }

  void _openThread(ChatThread thread) {
    context.push(AppRoutes.chatThread, extra: {'threadId': thread.id});
  }
}

/// A single thread tile in the list.
class _ThreadTile extends StatelessWidget {
  const _ThreadTile({required this.thread, required this.onTap});

  final ChatThread thread;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final preview = thread.lastMessage?.content ?? 'No messages';
    final date = thread.updatedAt ?? thread.createdAt;
    final timeAgo = _formatTimeAgo(date);

    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
        child: Row(
          children: [
            // Avatar
            thread.idolImageUrl != null
                ? Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      image: DecorationImage(
                        image: NetworkImage(thread.idolImageUrl!),
                        fit: BoxFit.cover,
                      ),
                    ),
                  )
                : Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      color: AppColors.accent,
                      shape: BoxShape.circle,
                    ),
                    child: Center(
                      child: Text(
                        (thread.idolName ?? 'AI').substring(0, 1).toUpperCase(),
                        style: AppTypography.h3.copyWith(color: Colors.white),
                      ),
                    ),
                  ),
            const SizedBox(width: 14),

            // Content
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          thread.idolName ?? 'AI Coach',
                          style: AppTypography.body.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      Text(
                        timeAgo,
                        style: AppTypography.caption.copyWith(
                          color: AppColors.textTertiary,
                          fontSize: 11,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          preview,
                          style: AppTypography.caption.copyWith(
                            color: AppColors.textSecondary,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (thread.messageCount > 0)
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: AppColors.surface,
                            borderRadius: AppRadii.brFull,
                          ),
                          child: Text(
                            '${thread.messageCount}',
                            style: AppTypography.caption.copyWith(
                              color: AppColors.textTertiary,
                              fontSize: 11,
                            ),
                          ),
                        ),
                    ],
                  ),
                ],
              ),
            ),

            const SizedBox(width: 8),
            Icon(Icons.chevron_right, size: 20, color: AppColors.textTertiary),
          ],
        ),
      ),
    );
  }

  String _formatTimeAgo(DateTime date) {
    final now = DateTime.now();
    final diff = now.difference(date);

    if (diff.inMinutes < 1) return 'now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m';
    if (diff.inHours < 24) return '${diff.inHours}h';
    if (diff.inDays < 7) return '${diff.inDays}d';
    if (diff.inDays < 30) return '${(diff.inDays / 7).floor()}w';
    return '${date.month}/${date.day}';
  }
}
