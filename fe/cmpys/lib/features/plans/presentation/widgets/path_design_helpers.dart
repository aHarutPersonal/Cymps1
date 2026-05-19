import 'package:flutter/material.dart';

import '../../../../app/design_tokens.dart';
import '../../../../core/ui/learning_resource_card.dart';
import '../../models/plan_models.dart';

class PathSyntheticStep {
  const PathSyntheticStep({
    required this.title,
    this.subtitle,
    this.completed = false,
  });

  final String title;
  final String? subtitle;
  final bool completed;
}

class PathSyntheticMaterial {
  const PathSyntheticMaterial({
    required this.label,
    required this.kindLabel,
    required this.title,
    required this.subtitle,
    required this.color,
  });

  final String label;
  final String kindLabel;
  final String title;
  final String subtitle;
  final Color color;
}

String pathWeekTitle(int week, List<PlanItem> items, {WeekSummary? summary}) {
  final theme = _compactPlanText(summary?.theme);
  if (theme != null && theme.isNotEmpty) return theme;

  final mission = _firstNonEmpty(
    items.map((item) => item.primaryMission ?? item.title),
  );
  if (mission != null) return _cleanWeekTitle(week, mission);

  if (week <= 4) return 'Baseline proof';
  if (week <= 8) return 'Public practice';
  return 'Compounding output';
}

String pathWeekSummary(int week, List<PlanItem> items, {WeekSummary? summary}) {
  final text = _compactPlanText(summary?.summary);
  if (text != null && text.isNotEmpty) return text;
  if (items.isEmpty) return 'A quiet week ready for your next plan item.';

  final hours = items.fold<double>(
    0,
    (sum, item) => sum + (item.estimatedHours ?? 0),
  );
  final proof = _firstNonEmpty(items.map((item) => item.successMetric));
  if (proof != null) return proof;
  if (hours > 0) {
    return '${hours.round()} focused hours across ${items.length} plan items.';
  }
  return '${items.length} plan items with concrete proof to publish.';
}

String pathItemSubtitle(PlanItem item) {
  final due = item.dueDate;
  final successMetric = _compactPlanText(item.successMetric);
  if (successMetric != null && successMetric.isNotEmpty) {
    return successMetric;
  }
  final description = _compactPlanText(item.description);
  if (description != null && description.isNotEmpty) {
    return description;
  }
  if (due != null) return 'Proof artifact due ${_formatDueDate(due)}.';
  return 'Turn this into a visible proof artifact.';
}

String pathItemTitle(PlanItem item) {
  return _compactPlanText(item.title) ?? 'Untitled plan item';
}

bool pathItemHasRenderableContent(PlanItem item) {
  return _compactPlanText(item.title) != null ||
      _compactPlanText(item.primaryMission) != null ||
      _compactPlanText(item.successMetric) != null ||
      _compactPlanText(item.description) != null ||
      _compactPlanText(item.resourceTitle) != null;
}

String pathItemKind(PlanItem item) {
  final raw = item.category?.trim().isNotEmpty == true
      ? item.category!.trim()
      : item.type.trim();
  if (raw.isEmpty) return 'Plan item';
  return raw
      .replaceAll('_', ' ')
      .split(' ')
      .where((part) => part.isNotEmpty)
      .map((part) => part[0].toUpperCase() + part.substring(1).toLowerCase())
      .join(' ');
}

List<PathSyntheticStep> pathSyntheticSteps(PlanItem item) {
  final mission = _compactPlanText(item.primaryMission);
  final proof = _compactPlanText(item.successMetric);
  final friction = _compactPlanText(item.predictedFriction);
  final solution = _compactPlanText(item.frictionSolution);
  final description = _compactPlanText(item.description);

  final steps = <PathSyntheticStep>[
    PathSyntheticStep(
      title: mission?.isNotEmpty == true
          ? mission!
          : 'Capture the current baseline',
      subtitle: description?.isNotEmpty == true ? description : null,
      completed: item.progressPercent >= 34,
    ),
    PathSyntheticStep(
      title: proof?.isNotEmpty == true ? proof! : 'Publish one proof artifact',
      subtitle: item.resourceTitle,
      completed: item.progressPercent >= 67,
    ),
  ];

  if (friction?.isNotEmpty == true || solution?.isNotEmpty == true) {
    steps.add(
      PathSyntheticStep(
        title: solution?.isNotEmpty == true
            ? solution!
            : 'Remove the predictable blocker',
        subtitle: friction,
        completed: item.isCompleted,
      ),
    );
  } else {
    steps.add(
      PathSyntheticStep(
        title: 'Log the result and next move',
        subtitle: 'Use the outcome to tighten the next week.',
        completed: item.isCompleted,
      ),
    );
  }

  return steps;
}

List<PathSyntheticMaterial> pathSyntheticMaterials(PlanItem item) {
  final materials = <PathSyntheticMaterial>[];
  final type = item.type.toLowerCase();

  if (item.resourceTitle?.trim().isNotEmpty ?? false) {
    materials.add(
      PathSyntheticMaterial(
        label: _materialLabelForType(type),
        kindLabel: _materialTitleForType(type),
        title: _materialTitleForType(type),
        subtitle: item.resourceTitle!.trim(),
        color: _materialColorForType(type),
      ),
    );
  }

  if (type.contains('video')) {
    materials.add(
      const PathSyntheticMaterial(
        label: 'V',
        kindLabel: 'Video',
        title: 'Video',
        subtitle: 'Watch the teardown and capture notes',
        color: AppColors.mint,
      ),
    );
  } else {
    materials.add(
      const PathSyntheticMaterial(
        label: 'A',
        kindLabel: 'Article',
        title: 'Article',
        subtitle: 'Read in-app markdown and highlight proof loops',
        color: AppColors.brandAccent,
      ),
    );
  }

  materials.add(
    const PathSyntheticMaterial(
      label: 'E',
      kindLabel: 'Exercise',
      title: 'Exercise',
      subtitle: 'Fill the worksheet and ship one small result',
      color: AppColors.peach,
    ),
  );

  final unique = <String, PathSyntheticMaterial>{};
  for (final material in materials) {
    unique['${material.title}:${material.subtitle}'] = material;
  }
  return unique.values.take(3).toList();
}

PathSyntheticMaterial pathMaterialFromPlanMaterial(PlanMaterial material) {
  final type = material.type.toJson();
  return PathSyntheticMaterial(
    label: _materialLabelForType(type),
    kindLabel: material.kindLabel,
    title: material.title,
    subtitle: material.displaySubtitle,
    color: _materialColorForType(type),
  );
}

class PathGlassPanel extends StatelessWidget {
  const PathGlassPanel({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(AppSpacing.s20),
    this.margin,
    this.onTap,
    this.borderColor,
    this.backgroundColor,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final EdgeInsetsGeometry? margin;
  final VoidCallback? onTap;
  final Color? borderColor;
  final Color? backgroundColor;

  @override
  Widget build(BuildContext context) {
    final content = AnimatedContainer(
      duration: AppDurations.normal,
      margin: margin,
      padding: padding,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            backgroundColor ?? AppColors.surfaceHighlight,
            AppColors.surface.withValues(alpha: 0.55),
          ],
        ),
        borderRadius: AppRadii.br24,
        border: Border.all(color: borderColor ?? AppColors.glassBorder),
        boxShadow: [
          BoxShadow(
            color: AppColors.brandAccent.withValues(alpha: 0.08),
            blurRadius: 32,
            offset: const Offset(0, 18),
          ),
        ],
      ),
      child: child,
    );

    if (onTap == null) return content;
    return Material(
      color: Colors.transparent,
      child: InkWell(borderRadius: AppRadii.br24, onTap: onTap, child: content),
    );
  }
}

class PathPill extends StatelessWidget {
  const PathPill({
    super.key,
    required this.label,
    this.color = AppColors.brandAccent,
    this.filled = false,
    this.icon,
  });

  final String label;
  final Color color;
  final bool filled;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      decoration: BoxDecoration(
        color: filled ? color : color.withValues(alpha: 0.10),
        borderRadius: AppRadii.brFull,
        border: Border.all(color: color.withValues(alpha: filled ? 0 : 0.45)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 14, color: filled ? Colors.black : color),
            const SizedBox(width: 6),
          ],
          Text(
            label,
            style: AppTypography.captionMedium.copyWith(
              color: filled ? Colors.black : color,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}

class PathStepLine extends StatelessWidget {
  const PathStepLine({
    super.key,
    required this.index,
    required this.title,
    this.subtitle,
    this.completed = false,
    this.onTap,
  });

  final int index;
  final String title;
  final String? subtitle;
  final bool completed;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: AppRadii.br12,
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.s8),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            AnimatedContainer(
              duration: AppDurations.fast,
              width: 22,
              height: 22,
              margin: const EdgeInsets.only(top: 1),
              decoration: BoxDecoration(
                color: completed ? AppColors.mint : AppColors.mint,
                shape: BoxShape.circle,
                border: completed
                    ? null
                    : Border.all(color: AppColors.mint.withValues(alpha: 0.35)),
              ),
              child: completed
                  ? const Icon(Icons.check, size: 13, color: Colors.black)
                  : null,
            ),
            const SizedBox(width: AppSpacing.s12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Step $index · $title',
                    style: AppTypography.captionMedium.copyWith(
                      color: AppColors.textSecondary,
                      fontWeight: FontWeight.w700,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (subtitle?.trim().isNotEmpty ?? false) ...[
                    const SizedBox(height: 4),
                    Text(
                      subtitle!.trim(),
                      style: AppTypography.caption.copyWith(
                        color: AppColors.textTertiary,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
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
}

class PathMaterialTile extends StatelessWidget {
  const PathMaterialTile({
    super.key,
    required this.material,
    this.onTap,
    this.compact = false,
  });

  final PathSyntheticMaterial material;
  final VoidCallback? onTap;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return LearningResourceCard(
      title: material.title,
      kindLabel: material.kindLabel,
      metaLabel: compact ? null : _compactMeta(material),
      subtitle: material.subtitle,
      icon: _materialIconForLabel(material.label),
      accentColor: material.color,
      onTap: onTap,
    );
  }

  String? _compactMeta(PathSyntheticMaterial material) {
    final subtitle = material.subtitle.trim();
    if (subtitle.endsWith('min') || subtitle.contains(' min ')) {
      return subtitle;
    }
    return null;
  }

  IconData _materialIconForLabel(String label) {
    switch (label) {
      case 'V':
        return Icons.play_circle_outline_rounded;
      case 'B':
        return Icons.menu_book_rounded;
      case 'E':
        return Icons.edit_note_rounded;
      case 'C':
        return Icons.school_rounded;
      case 'S':
        return Icons.search_rounded;
      default:
        return Icons.article_outlined;
    }
  }
}

class PathProgressStrip extends StatelessWidget {
  const PathProgressStrip({
    super.key,
    required this.progress,
    this.color = AppColors.brandAccent,
  });

  final double progress;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: AppRadii.brFull,
      child: LinearProgressIndicator(
        value: progress.clamp(0, 1),
        minHeight: 5,
        backgroundColor: AppColors.surfaceHighlight,
        valueColor: AlwaysStoppedAnimation(color),
      ),
    );
  }
}

class PathEmptyState extends StatelessWidget {
  const PathEmptyState({
    super.key,
    required this.title,
    required this.message,
    this.action,
  });

  final String title;
  final String message;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: AppSpacing.screenH,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 74,
              height: 74,
              decoration: BoxDecoration(
                color: AppColors.brandAccent.withValues(alpha: 0.14),
                borderRadius: AppRadii.br24,
                border: Border.all(
                  color: AppColors.brandAccent.withValues(alpha: 0.24),
                ),
              ),
              child: const Icon(
                Icons.route_outlined,
                color: AppColors.brandAccent,
                size: 34,
              ),
            ),
            const SizedBox(height: AppSpacing.s24),
            Text(title, style: AppTypography.h2, textAlign: TextAlign.center),
            const SizedBox(height: AppSpacing.s8),
            Text(
              message,
              style: AppTypography.body.copyWith(
                color: AppColors.textSecondary,
              ),
              textAlign: TextAlign.center,
            ),
            if (action != null) ...[
              const SizedBox(height: AppSpacing.s32),
              action!,
            ],
          ],
        ),
      ),
    );
  }
}

String _cleanWeekTitle(int week, String title) {
  final cleaned = title
      .replaceFirst(
        RegExp('^Week\\s+$week\\s*[:·-]\\s*', caseSensitive: false),
        '',
      )
      .replaceFirst(RegExp(r'^Week\s+\d+\s*[:·-]\s*', caseSensitive: false), '')
      .trim();
  if (cleaned.isEmpty) return title;
  return cleaned.length > 34 ? '${cleaned.substring(0, 31)}...' : cleaned;
}

String? _firstNonEmpty(Iterable<String?> values) {
  for (final value in values) {
    final trimmed = _compactPlanText(value);
    if (trimmed != null && trimmed.isNotEmpty) return trimmed;
  }
  return null;
}

String? _compactPlanText(String? value) {
  final clean = value
      ?.replaceAll(RegExp(r'[\u200B-\u200D\uFEFF]'), '')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
  if (clean == null || clean.isEmpty) return null;
  return clean;
}

String _formatDueDate(DateTime date) {
  final now = DateTime.now();
  final difference = date.difference(DateTime(now.year, now.month, now.day));
  if (difference.inDays == 0) return 'today';
  if (difference.inDays == 1) return 'tomorrow';
  if (difference.inDays > 1 && difference.inDays <= 7) {
    return 'in ${difference.inDays} days';
  }
  return '${date.month}/${date.day}';
}

String _materialLabelForType(String type) {
  if (type.contains('video')) return 'V';
  if (type.contains('book')) return 'B';
  if (type.contains('exercise') || type.contains('practice')) return 'E';
  if (type.contains('course')) return 'C';
  if (type.contains('search')) return 'S';
  return 'A';
}

String _materialTitleForType(String type) {
  if (type.contains('video')) return 'Video';
  if (type.contains('book')) return 'Book';
  if (type.contains('exercise') || type.contains('practice')) return 'Exercise';
  if (type.contains('course')) return 'Course';
  if (type.contains('search')) return 'Search';
  if (type.contains('lesson')) return 'Lesson';
  return 'Article';
}

Color _materialColorForType(String type) {
  if (type.contains('video')) return AppColors.mint;
  if (type.contains('book')) return AppColors.blue;
  if (type.contains('exercise') || type.contains('practice')) {
    return AppColors.peach;
  }
  if (type.contains('course')) return AppColors.mint;
  return AppColors.brandAccent;
}
