import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:go_router/go_router.dart';

import '../../../app/design_tokens.dart';
import '../../../core/ui/ambient_background.dart';
import '../../session/models/daily_insight.dart';
import '../../session/providers/stash_provider.dart';
import '../../session/presentation/widgets/idea_card.dart';
import '../models/plan_models.dart';

/// prototype-style book ideas reader.
/// Presents book insights as vertical-swipe idea cards.
class BookIdeasScreen extends ConsumerStatefulWidget {
  const BookIdeasScreen({
    super.key,
    required this.bookTitle,
    required this.ideas,
  });

  final String bookTitle;
  final List<BookIdea> ideas;

  @override
  ConsumerState<BookIdeasScreen> createState() => _BookIdeasScreenState();
}

class _BookIdeasScreenState extends ConsumerState<BookIdeasScreen> {
  final PageController _pageController = PageController();
  late FlutterTts _flutterTts;
  int? _playingIndex;
  int _currentPage = 0;

  @override
  void initState() {
    super.initState();
    _initTts();
  }

  void _initTts() {
    _flutterTts = FlutterTts();
    _flutterTts.setCompletionHandler(() {
      if (mounted) {
        setState(() => _playingIndex = null);
      }
    });
  }

  @override
  void dispose() {
    _flutterTts.stop();
    _pageController.dispose();
    super.dispose();
  }

  void _onStash(BookIdea idea) {
    final insight = DailyInsight(
      title: idea.title,
      content: idea.content,
      category: idea.category,
      idolName: widget.bookTitle,
    );
    ref.read(stashProvider.notifier).toggleStash(insight);
  }

  Future<void> _onPlayAudio(int index, BookIdea idea) async {
    if (_playingIndex == index) {
      await _flutterTts.stop();
      setState(() => _playingIndex = null);
      return;
    }

    await _flutterTts.stop();
    setState(() => _playingIndex = index);

    final textToSpeak = "${idea.category}. ${idea.title}. ${idea.content}";
    await _flutterTts.speak(textToSpeak);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.brandBg,
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.close, color: AppColors.textPrimary),
          onPressed: () {
            _flutterTts.stop();
            context.pop();
          },
        ),
        title: Column(
          children: [
            Text(
              widget.bookTitle,
              style: AppTypography.h3,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            Text(
              '${_currentPage + 1} of ${widget.ideas.length}',
              style: AppTypography.captionUpper.copyWith(
                color: AppColors.textSecondary,
              ),
            ),
          ],
        ),
        centerTitle: true,
        actions: [
          IconButton(
            icon: const Icon(Icons.bookmarks, color: AppColors.textPrimary),
            onPressed: () {
              _flutterTts.stop();
              context.push('/stash');
            },
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: AmbientBackground(
        useSafeArea: false,
        child: SafeArea(
          child: Column(
            children: [
              // Elegant horizontal premium progress bar
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: AppSpacing.s32),
                child: ClipRRect(
                  borderRadius: AppRadii.brFull,
                  child: LinearProgressIndicator(
                    value: (_currentPage + 1) / widget.ideas.length,
                    backgroundColor: AppColors.brandAccent.withValues(
                      alpha: 0.1,
                    ),
                    valueColor: const AlwaysStoppedAnimation<Color>(
                      AppColors.brandAccent,
                    ),
                    minHeight: 3,
                  ),
                ),
              ),
              const SizedBox(height: AppSpacing.s24),
              // Cards
              Expanded(
                child: PageView.builder(
                  controller: _pageController,
                  scrollDirection: Axis.horizontal,
                  physics: const BouncingScrollPhysics(),
                  onPageChanged: (index) {
                    if (_playingIndex != null) {
                      _flutterTts.stop();
                      setState(() => _playingIndex = null);
                    }
                    setState(() => _currentPage = index);
                    HapticFeedback.lightImpact();
                  },
                  itemCount: widget.ideas.length,
                  itemBuilder: (context, index) {
                    final idea = widget.ideas[index];
                    final isStashed = ref
                        .watch(stashProvider)
                        .any((item) => item.title == idea.title);

                    return IdeaCard(
                      contentMarkdown: '**${idea.title}**\n\n${idea.content}',
                      category: idea.category,
                      idolName: widget.bookTitle,
                      isStashed: isStashed,
                      isPlaying: _playingIndex == index,
                      onStash: () => _onStash(idea),
                      onPlayAudio: () => _onPlayAudio(index, idea),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
