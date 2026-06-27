// In-app reader for plan materials: full markdown lessons/articles (inline or
// fetched from the shared content-resources store) and Deepstash-style book
// idea cards. Editorial layout matching the CMPYS reading surfaces.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/design_tokens.dart';
import '../../../core/ui/app_shell.dart';
import '../../../core/ui/cmpys/cmpys_markdown.dart';
import '../../../core/ui/cmpys/cmpys_primitives.dart';
import '../data/plan_repository.dart';
import '../models/plan_models.dart';

class MaterialReaderScreen extends ConsumerStatefulWidget {
  const MaterialReaderScreen({super.key, required this.material});

  final PlanMaterialDetail material;

  @override
  ConsumerState<MaterialReaderScreen> createState() =>
      _MaterialReaderScreenState();
}

class _MaterialReaderScreenState extends ConsumerState<MaterialReaderScreen> {
  String? _markdown;
  bool _loading = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    final inline = widget.material.contentMarkdown;
    if (inline != null && inline.trim().isNotEmpty) {
      _markdown = inline;
    } else if (widget.material.contentResourceId != null) {
      _fetchResource();
    }
  }

  Future<void> _fetchResource() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final resource = await ref
          .read(planRepositoryProvider)
          .getContentResource(widget.material.contentResourceId!);
      if (!mounted) return;
      setState(() {
        _markdown = resource.contentMarkdown;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'Couldn’t load this lesson. Check your connection.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final m = widget.material;
    final hasIdeas = m.ideas.isNotEmpty;
    final hasText = _markdown != null && _markdown!.trim().isNotEmpty;

    return Scaffold(
      backgroundColor: AppColors.paper,
      body: SafeArea(
        child: CustomScrollView(
          slivers: [
            SliverAppBar(
              backgroundColor: AppColors.paper,
              surfaceTintColor: Colors.transparent,
              elevation: 0,
              pinned: false,
              floating: true,
              leading: Padding(
                padding: const EdgeInsets.fromLTRB(14, 6, 0, 0),
                child: Material(
                  color: Colors.transparent,
                  child: InkWell(
                    onTap: () => Navigator.of(context).maybePop(),
                    borderRadius: BorderRadius.circular(999),
                    child: Container(
                      width: 38,
                      height: 38,
                      decoration: BoxDecoration(
                        color: AppColors.card,
                        shape: BoxShape.circle,
                        border: Border.all(color: AppColors.hair),
                      ),
                      child: const Icon(Icons.chevron_left_rounded,
                          size: 22, color: AppColors.ink),
                    ),
                  ),
                ),
              ),
            ),
            SliverPadding(
              padding: EdgeInsets.fromLTRB(22, 6, 22, AppShell.bottomNavClearance(context)),
              sliver: SliverList.list(
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 5),
                        decoration: BoxDecoration(
                          color: _kindColor(m.type).withValues(alpha: 0.14),
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: Text(
                          _kindLabel(m.type).toUpperCase(),
                          style: AppTypography.kicker.copyWith(
                              color: _kindColor(m.type), fontSize: 10.5),
                        ),
                      ),
                      if (m.durationMinutes != null) ...[
                        const SizedBox(width: 10),
                        Text('${m.durationMinutes} min',
                            style: AppTypography.caption.copyWith(
                                color: AppColors.ink3, fontSize: 12.5)),
                      ],
                    ],
                  ),
                  const SizedBox(height: 14),
                  Text(m.title,
                      style: AppTypography.h1.copyWith(
                          fontSize: 30, letterSpacing: -0.5, height: 1.12)),
                  if (m.authorOrCreator != null &&
                      m.authorOrCreator!.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    Text('By ${m.authorOrCreator}',
                        style: AppTypography.captionMedium.copyWith(
                            color: AppColors.ink3,
                            fontWeight: FontWeight.w600)),
                  ],
                  const SizedBox(height: 24),
                  if (_loading)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 50),
                      child: Center(
                        child: SizedBox(
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            valueColor: AlwaysStoppedAnimation<Color>(
                                AppColors.green),
                          ),
                        ),
                      ),
                    )
                  else if (_error != null)
                    CmpysCardSurface(
                      onTap: _fetchResource,
                      child: Row(
                        children: [
                          const Icon(Icons.refresh_rounded,
                              size: 18, color: AppColors.ink3),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text('$_error Tap to retry.',
                                style: AppTypography.caption.copyWith(
                                    color: AppColors.ink2, fontSize: 13.5)),
                          ),
                        ],
                      ),
                    )
                  else ...[
                    if (hasText) CmpysMarkdown(_markdown!),
                    if (hasIdeas) ...[
                      if (hasText) const SizedBox(height: 26),
                      const CmpysKicker('Key ideas'),
                      const SizedBox(height: 12),
                      for (final idea in m.ideas) ...[
                        _ideaCard(idea),
                        const SizedBox(height: 12),
                      ],
                    ],
                    if (!hasText && !hasIdeas)
                      Text(
                        m.reason ??
                            'No in-app content for this material yet.',
                        style: AppTypography.bodyDim,
                      ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _ideaCard(BookIdea idea) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: AppColors.gradGreen,
        borderRadius: AppRadii.lg,
        boxShadow: [
          BoxShadow(
              color: AppColors.green2.withValues(alpha: 0.22),
              blurRadius: 16,
              offset: const Offset(0, 8)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(idea.category.toUpperCase(),
              style: AppTypography.kicker
                  .copyWith(color: Colors.white.withValues(alpha: 0.7))),
          const SizedBox(height: 8),
          Text(idea.title,
              style: AppTypography.h3.copyWith(
                  color: Colors.white, fontSize: 18, height: 1.25)),
          const SizedBox(height: 8),
          Text(idea.content,
              style: AppTypography.body.copyWith(
                  color: Colors.white.withValues(alpha: 0.92),
                  fontSize: 14.5,
                  height: 1.5)),
        ],
      ),
    );
  }

  String _kindLabel(String? type) {
    switch (type) {
      case 'book':
        return 'Book';
      case 'article':
        return 'Article';
      case 'in_app_lesson':
        return 'Lesson';
      case 'video':
        return 'Video';
      default:
        return 'Read';
    }
  }

  // Kind accent colors mirror the design's kindMeta:
  // read → blue, video → clay, book/lesson → ochre.
  Color _kindColor(String? type) {
    switch (type) {
      case 'book':
        return AppColors.ochre2;
      case 'video':
        return AppColors.clay;
      case 'in_app_lesson':
        return AppColors.green2;
      case 'article':
      default:
        return AppColors.blue;
    }
  }
}
