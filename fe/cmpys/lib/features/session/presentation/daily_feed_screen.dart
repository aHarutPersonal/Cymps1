import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../../app/design_tokens.dart';
import '../../../core/ui/prototype_grid_background.dart';
import '../../ideas/models/idea_card_models.dart';
import '../../ideas/providers/idea_card_provider.dart';
import '../../idols/providers/idol_provider.dart';
import '../models/session_models.dart';
import 'widgets/idea_card.dart';

/// Daily Ideas Feed — vertical swipe through IdeaCards.
///
/// Uses the Ideas provider to fetch cards from the API.
/// Triggers LLM generation lazily if pool is empty.
class DailyFeedScreen extends ConsumerStatefulWidget {
  const DailyFeedScreen({super.key});

  @override
  ConsumerState<DailyFeedScreen> createState() => _DailyFeedScreenState();
}

class _DailyFeedScreenState extends ConsumerState<DailyFeedScreen> {
  final PageController _pageController = PageController();
  late FlutterTts _flutterTts;
  int? _playingIndex;
  int _currentPage = 0;

  @override
  void initState() {
    super.initState();
    _initTts();

    // Trigger initial data load after first frame
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadInitialData();
    });
  }

  void _initTts() {
    _flutterTts = FlutterTts();
    _flutterTts.setCompletionHandler(() {
      if (mounted) setState(() => _playingIndex = null);
    });
  }

  /// Load ideas for the currently active idol.
  void _loadInitialData() {
    final activeIdol = ref.read(activeIdolProvider);
    if (activeIdol != null) {
      ref.read(ideasFeedProvider.notifier).loadIdeas(activeIdol.id);
    }
  }

  @override
  void dispose() {
    _flutterTts.stop();
    _pageController.dispose();
    super.dispose();
  }

  Future<void> _onPlayAudio(int index, IdeaCardModel card) async {
    if (_playingIndex == index) {
      await _flutterTts.stop();
      setState(() => _playingIndex = null);
      return;
    }

    await _flutterTts.stop();
    setState(() => _playingIndex = index);

    // Strip markdown bold for TTS
    final clean = card.contentMarkdown.replaceAll(RegExp(r'\*\*'), '');
    await _flutterTts.speak('${card.categoryTag}. $clean');
  }

  void _onPageChanged(int index) {
    setState(() => _currentPage = index);

    // Stop TTS on page change
    if (_playingIndex != null) {
      _flutterTts.stop();
      setState(() => _playingIndex = null);
    }

    // Preload more cards when approaching end
    final state = ref.read(ideasFeedProvider);
    if (index >= state.cards.length - 3) {
      ref.read(ideasFeedProvider.notifier).loadMore();
    }
  }

  void _onStashToggle(IdeaCardModel card) {
    HapticFeedback.mediumImpact();
    ref.read(ideasFeedProvider.notifier).toggleStash(card.id);

    // Show brief feedback
    final messenger = ScaffoldMessenger.of(context);
    messenger.clearSnackBars();
    messenger.showSnackBar(
      SnackBar(
        content: Text(
          card.isStashed ? 'Removed from stash' : 'Saved to stash',
          style: AppTypography.caption.copyWith(color: Colors.white),
        ),
        behavior: SnackBarBehavior.floating,
        backgroundColor: AppColors.charcoal,
        duration: const Duration(seconds: 1),
        shape: RoundedRectangleBorder(borderRadius: AppRadii.br12),
        margin: const EdgeInsets.only(
          bottom: 100,
          left: AppSpacing.s20,
          right: AppSpacing.s20,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final feedState = ref.watch(ideasFeedProvider);

    // React to idol changes
    ref.listen<SelectedIdolInfo?>(activeIdolProvider, (
      SelectedIdolInfo? prev,
      SelectedIdolInfo? next,
    ) {
      if (next != null && next.id != prev?.id) {
        ref.read(ideasFeedProvider.notifier).loadIdeas(next.id);
      }
    });

    return Scaffold(
      backgroundColor: AppColors.bg,
      extendBodyBehindAppBar: true,
      body: PrototypeGridBackground(
        child: feedState.isLoading
            ? _buildLoading()
            : feedState.error != null
            ? _buildError(feedState.error!)
            : feedState.cards.isEmpty
            ? _buildEmpty()
            : _buildFeed(feedState.cards),
      ),
    );
  }

  Widget _buildLoading() {
    return const Center(
      child: CircularProgressIndicator(color: AppColors.brandAccent),
    );
  }

  Widget _buildError(String error) {
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
              onPressed: () {
                final idol = ref.read(ideasFeedProvider).activeIdolId;
                if (idol != null) {
                  ref.read(ideasFeedProvider.notifier).refresh(idol);
                }
              },
              child: Text(
                'Retry',
                style: TextStyle(color: AppColors.brandAccent),
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
              PhosphorIconsRegular.sparkle,
              color: AppColors.textTertiary,
              size: 64,
            ),
            const SizedBox(height: 20),
            Text('No insights yet', style: AppTypography.h3),
            const SizedBox(height: 8),
            Text(
              'Select an idol to get personalized insights',
              style: AppTypography.body.copyWith(
                color: AppColors.textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFeed(List<IdeaCardModel> cards) {
    return Stack(
      children: [
        // Vertical swipe feed
        PageView.builder(
          controller: _pageController,
          scrollDirection: Axis.vertical,
          onPageChanged: _onPageChanged,
          itemCount: cards.length,
          itemBuilder: (context, index) {
            final card = cards[index];
            return IdeaCard(
              contentMarkdown: card.contentMarkdown,
              category: card.categoryTag,
              isStashed: card.isStashed,
              isPlaying: _playingIndex == index,
              onStash: () => _onStashToggle(card),
              onPlayAudio: () => _onPlayAudio(index, card),
            );
          },
        ),

        SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 16, 24, 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Library.Idea_Stack',
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
                Tooltip(
                  message: 'New ideas',
                  child: IconButton(
                    style: IconButton.styleFrom(
                      backgroundColor: AppColors.surface,
                      shape: RoundedRectangleBorder(
                        borderRadius: AppRadii.br12,
                        side: const BorderSide(color: AppColors.border),
                      ),
                    ),
                    icon: Icon(
                      PhosphorIconsRegular.slidersHorizontal,
                      color: AppColors.textPrimary,
                      size: 20,
                    ),
                    onPressed: () {
                      final idol = ref.read(ideasFeedProvider).activeIdolId;
                      if (idol != null) {
                        ref.read(ideasFeedProvider.notifier).refresh(idol);
                      }
                    },
                  ),
                ),
              ],
            ),
          ),
        ),

        // Scroll progress bar (replaces 15-dot limit)
        if (cards.length > 1)
          Positioned(
            right: 6,
            top: 0,
            bottom: 0,
            child: Center(
              child: _ScrollProgressBar(
                current: _currentPage,
                total: cards.length,
              ),
            ),
          ),

        // Loading more indicator
        if (ref.watch(ideasFeedProvider).isLoadingMore)
          const Positioned(
            bottom: 100,
            left: 0,
            right: 0,
            child: Center(
              child: SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: AppColors.brandAccent,
                ),
              ),
            ),
          ),
      ],
    );
  }
}

/// Minimal scroll progress indicator — shows a thin animated bar
/// that scales from a visible window of dots, capping at 7.
class _ScrollProgressBar extends StatelessWidget {
  const _ScrollProgressBar({required this.current, required this.total});

  final int current;
  final int total;

  @override
  Widget build(BuildContext context) {
    // Show max 7 dots centered around current
    const maxDots = 7;
    int start = 0;
    int end = total;
    if (total > maxDots) {
      start = (current - maxDots ~/ 2).clamp(0, total - maxDots);
      end = start + maxDots;
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (int i = start; i < end; i++)
          AnimatedContainer(
            duration: AppDurations.fast,
            width: 3,
            height: i == current ? 18 : 3,
            margin: const EdgeInsets.symmetric(vertical: 2),
            decoration: BoxDecoration(
              color: i == current
                  ? AppColors.mint
                  : AppColors.textTertiary.withValues(alpha: 0.25),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
      ],
    );
  }
}
