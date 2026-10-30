import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/design_tokens.dart';
import '../../../core/ui/motion/page_transition.dart';
import '../../../core/ui/v3/v3.dart';
import '../data/plan_repository.dart';
import '../models/learning_support.dart';
import '../models/plan_models.dart';
import 'book_companion_screen.dart';
import 'material_video_screen.dart';

/// Optional support loads independently; never changes lesson completion.
class LearningSupportSection extends ConsumerStatefulWidget {
  const LearningSupportSection({
    super.key,
    required this.itemId,
    required this.stepId,
    this.theme = ReaderTheme.light,
  });
  final String itemId, stepId;
  final ReaderTheme theme;
  @override
  ConsumerState<LearningSupportSection> createState() =>
      _LearningSupportSectionState();
}

class _LearningSupportSectionState
    extends ConsumerState<LearningSupportSection> {
  LearningSupport? _support;
  Timer? _timer;
  int _polls = 0;
  @override
  void initState() {
    super.initState();
    _load(true);
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _load(bool prepare) async {
    try {
      final support = await ref
          .read(planRepositoryProvider)
          .getLearningSupport(
            widget.itemId,
            stepId: widget.stepId,
            prepare: prepare,
          );
      if (!mounted) return;
      setState(() => _support = support);
      if (support.checking && _polls++ < 50) {
        _timer = Timer(const Duration(seconds: 12), () => _load(false));
      }
    } catch (_) {
      /* Optional resources must never interrupt the tutorial. */
    }
  }

  @override
  Widget build(BuildContext context) {
    final support = _support;
    if (support == null) return const SizedBox.shrink();
    final idea = support.idea;
    if (idea == null && support.videos.isEmpty) return const SizedBox.shrink();
    return DefaultTextStyle.merge(
      style: TextStyle(color: widget.theme.fg),
      child: Padding(
        padding: const EdgeInsets.only(top: 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'EXPLORE FURTHER · OPTIONAL',
              style: AppTypography.kick.copyWith(color: widget.theme.fg2),
            ),
            if (idea != null) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  color: widget.theme.card,
                  borderRadius: BorderRadius.circular(18),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'From ${idea['bookTitle']}',
                      style: AppTypography.sans(12, FontWeight.w600),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      idea['title'] as String,
                      style: AppTypography.sans(18, FontWeight.w600),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      idea['text'] as String,
                      style: AppTypography.sans(15).copyWith(height: 1.5),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      'CMPYS connection: ${idea['application']}',
                      style: AppTypography.sans(14).copyWith(height: 1.5),
                    ),
                    const SizedBox(height: 12),
                    V3Button(
                      kind: V3ButtonKind.iris,
                      onPressed: () {
                        final book = support.books.firstWhere(
                          (b) => b.id == idea['bookId'],
                        );
                        Navigator.of(context).push(
                          CmpysPageRoute<void>(
                            builder: (_) => BookCompanionScreen(
                              itemId: widget.itemId,
                              material: PlanMaterialDetail(
                                title: book.title,
                                type: 'book',
                                authorOrCreator: book.author,
                              ),
                              initialBook: book,
                            ),
                          ),
                        );
                      },
                      child: const Text('Explore book tutorials'),
                    ),
                  ],
                ),
              ),
            ],
            for (final video in support.videos) ...[
              const SizedBox(height: 14),
              Text(
                video.material.title,
                style: AppTypography.sans(17, FontWeight.w600),
              ),
              const SizedBox(height: 5),
              Text(
                '${video.material.authorOrCreator}${video.material.durationMinutes == null ? '' : ' · ${video.material.durationMinutes} min'}',
                style: AppTypography.sans(13).copyWith(color: widget.theme.fg2),
              ),
              const SizedBox(height: 8),
              Text(
                video.material.reason ?? '',
                style: AppTypography.sans(15).copyWith(height: 1.5),
              ),
              const SizedBox(height: 10),
              V3Button(
                onPressed: () => Navigator.of(context).push(
                  CmpysPageRoute<void>(
                    builder: (_) => MaterialVideoScreen(
                      material: video.material,
                      videoId: video.id,
                      tryAfter: video.tryAfter,
                      verification: video.verification,
                      evidenceUrl: video.evidenceUrl,
                    ),
                  ),
                ),
                child: const Text('Watch video'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
