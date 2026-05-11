import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_tts/flutter_tts.dart';

import '../../../app/design_tokens.dart';
import '../models/daily_insight.dart';
import '../providers/stash_provider.dart';

abstract final class _StashPalette {
  static const canvas = AppColors.bg;
  static const paper = Color(0xFFFFFFFF);
  static const ink = AppColors.textPrimary;
  static const muted = AppColors.textSecondary;
  static const line = AppColors.border;
  static const mint = AppColors.mint;
  static const coralDark = AppColors.brandAccentDark;
}

class StashScreen extends ConsumerStatefulWidget {
  const StashScreen({super.key});

  @override
  ConsumerState<StashScreen> createState() => _StashScreenState();
}

class _StashScreenState extends ConsumerState<StashScreen> {
  late FlutterTts _flutterTts;
  String? _currentlyPlayingId;

  @override
  void initState() {
    super.initState();
    _initTts();
  }

  void _initTts() {
    _flutterTts = FlutterTts();
    _flutterTts.setCompletionHandler(() {
      if (!mounted) return;
      setState(() {
        _currentlyPlayingId = null;
      });
    });
  }

  @override
  void dispose() {
    _flutterTts.stop();
    super.dispose();
  }

  Future<void> _play(DailyInsight insight) async {
    final id = insight.title;
    if (_currentlyPlayingId == id) {
      await _flutterTts.stop();
      setState(() => _currentlyPlayingId = null);
      return;
    }

    await _flutterTts.stop();
    setState(() => _currentlyPlayingId = id);

    final textToSpeak =
        '${insight.category}. ${insight.title}. ${insight.content}';
    await _flutterTts.speak(textToSpeak);
  }

  @override
  Widget build(BuildContext context) {
    final stashedIdeas = ref.watch(stashProvider);

    return Scaffold(
      backgroundColor: _StashPalette.canvas,
      body: DecoratedBox(
        decoration: const BoxDecoration(
          color: _StashPalette.canvas,
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              AppColors.surfaceHighlight,
              _StashPalette.canvas,
              AppColors.bg,
            ],
            stops: [0, 0.52, 1],
          ),
        ),
        child: SafeArea(
          child: Column(
            children: [
              _StashHeader(
                count: stashedIdeas.length,
                onBack: () {
                  _flutterTts.stop();
                  context.pop();
                },
              ),
              Expanded(
                child: stashedIdeas.isEmpty
                    ? const _EmptyStash()
                    : ListView.separated(
                        padding: const EdgeInsets.fromLTRB(20, 8, 20, 28),
                        itemCount: stashedIdeas.length,
                        separatorBuilder: (_, _) => const SizedBox(height: 12),
                        itemBuilder: (context, index) {
                          final insight = stashedIdeas[index];
                          return _StashedInsightCard(
                            insight: insight,
                            isPlaying: _currentlyPlayingId == insight.title,
                            onPlay: () => _play(insight),
                            onRemove: () {
                              ref
                                  .read(stashProvider.notifier)
                                  .toggleStash(insight);
                            },
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

class _StashHeader extends StatelessWidget {
  const _StashHeader({required this.count, required this.onBack});

  final int count;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 10),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: _StashPalette.paper.withValues(alpha: 0.92),
          borderRadius: AppRadii.br20,
          border: Border.all(color: _StashPalette.line),
          boxShadow: [
            BoxShadow(
              color: _StashPalette.ink.withValues(alpha: 0.08),
              blurRadius: 28,
              offset: const Offset(0, 14),
            ),
          ],
        ),
        child: Row(
          children: [
            IconButton(
              onPressed: onBack,
              icon: const Icon(Icons.arrow_back_ios_new, size: 19),
              color: _StashPalette.ink,
            ),
            const SizedBox(width: 4),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Saved ideas',
                    style: AppTypography.h3.copyWith(color: _StashPalette.ink),
                  ),
                  Text(
                    '$count stashed cards',
                    style: AppTypography.caption.copyWith(
                      color: _StashPalette.muted,
                    ),
                  ),
                ],
              ),
            ),
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                color: _StashPalette.mint,
                borderRadius: AppRadii.br12,
              ),
              child: const Icon(Icons.bookmark, color: _StashPalette.ink),
            ),
          ],
        ),
      ),
    );
  }
}

class _EmptyStash extends StatelessWidget {
  const _EmptyStash();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                color: _StashPalette.paper,
                borderRadius: AppRadii.brFull,
                border: Border.all(color: _StashPalette.line),
              ),
              child: const Icon(
                Icons.bookmark_border,
                color: _StashPalette.coralDark,
                size: 34,
              ),
            ),
            const SizedBox(height: 18),
            Text(
              'Your stash is empty',
              style: AppTypography.h3.copyWith(color: _StashPalette.ink),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              'Save cards from the Daily Feed and they will collect here.',
              style: AppTypography.body.copyWith(color: _StashPalette.muted),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

class _StashedInsightCard extends StatelessWidget {
  const _StashedInsightCard({
    required this.insight,
    required this.isPlaying,
    required this.onPlay,
    required this.onRemove,
  });

  final DailyInsight insight;
  final bool isPlaying;
  final VoidCallback onPlay;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _StashPalette.paper,
        borderRadius: AppRadii.br16,
        border: Border.all(color: _StashPalette.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  insight.category.toUpperCase(),
                  style: AppTypography.captionUpper.copyWith(
                    color: _StashPalette.coralDark,
                  ),
                ),
              ),
              IconButton(
                tooltip: isPlaying ? 'Stop reading' : 'Read aloud',
                onPressed: onPlay,
                icon: Icon(
                  isPlaying
                      ? Icons.stop_circle_outlined
                      : Icons.play_circle_outline,
                ),
                color: isPlaying ? _StashPalette.coralDark : _StashPalette.ink,
              ),
              IconButton(
                tooltip: 'Remove from stash',
                onPressed: onRemove,
                icon: const Icon(Icons.bookmark_remove_outlined),
                color: _StashPalette.ink,
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            insight.title,
            style: AppTypography.h4.copyWith(
              color: _StashPalette.ink,
              height: 1.3,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            insight.content,
            style: AppTypography.body.copyWith(
              color: _StashPalette.muted,
              height: 1.5,
            ),
            maxLines: 4,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }
}
