import 'package:flutter/material.dart';

import '../../app/design_tokens.dart';

abstract final class _ResourcePalette {
  static const paper = Color(0xFFFFFFFF);
  static const ink = AppColors.textPrimary;
  static const muted = AppColors.textSecondary;
  static const line = AppColors.border;
}

class LearningResourceCard extends StatelessWidget {
  const LearningResourceCard({
    super.key,
    required this.title,
    required this.kindLabel,
    required this.icon,
    required this.accentColor,
    this.metaLabel,
    this.subtitle,
    this.progressPercent = 0,
    this.isCompleted = false,
    this.isUnavailable = false,
    this.onTap,
    this.trailing,
  });

  final String title;
  final String kindLabel;
  final String? metaLabel;
  final String? subtitle;
  final IconData icon;
  final Color accentColor;
  final int progressPercent;
  final bool isCompleted;
  final bool isUnavailable;
  final VoidCallback? onTap;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final progress = (progressPercent / 100).clamp(0.0, 1.0);
    final statusColor = isCompleted ? AppColors.mint : accentColor;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: AppRadii.br20,
        onTap: isUnavailable ? null : onTap,
        child: AnimatedContainer(
          duration: AppDurations.fast,
          padding: const EdgeInsets.all(AppSpacing.s16),
          decoration: BoxDecoration(
            color: _ResourcePalette.paper.withValues(
              alpha: isUnavailable ? 0.68 : 1,
            ),
            borderRadius: AppRadii.br20,
            border: Border.all(
              color: isUnavailable
                  ? _ResourcePalette.line.withValues(alpha: 0.7)
                  : _ResourcePalette.line,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _ResourceIcon(
                    icon: icon,
                    color: statusColor,
                    muted: isUnavailable,
                  ),
                  const SizedBox(width: AppSpacing.s12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Wrap(
                          spacing: AppSpacing.s8,
                          runSpacing: AppSpacing.s6,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            _ResourcePill(
                              label: isUnavailable
                                  ? 'Unavailable'
                                  : isCompleted
                                  ? 'Completed'
                                  : kindLabel,
                              color: isUnavailable
                                  ? _ResourcePalette.muted
                                  : statusColor,
                            ),
                            if (metaLabel?.trim().isNotEmpty ?? false)
                              Text(
                                metaLabel!.trim(),
                                style: AppTypography.caption.copyWith(
                                  color: _ResourcePalette.muted,
                                ),
                              ),
                          ],
                        ),
                        const SizedBox(height: AppSpacing.s8),
                        Text(
                          title,
                          style: AppTypography.bodyMedium.copyWith(
                            fontWeight: FontWeight.w800,
                            color: isUnavailable
                                ? _ResourcePalette.muted
                                : _ResourcePalette.ink,
                            height: 1.25,
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        if (subtitle?.trim().isNotEmpty ?? false) ...[
                          const SizedBox(height: AppSpacing.s6),
                          Text(
                            subtitle!.trim(),
                            style: AppTypography.caption.copyWith(
                              color: _ResourcePalette.muted,
                              height: 1.35,
                            ),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ],
                    ),
                  ),
                  if (trailing != null) ...[
                    const SizedBox(width: AppSpacing.s8),
                    trailing!,
                  ] else if (onTap != null && !isUnavailable) ...[
                    const SizedBox(width: AppSpacing.s8),
                    Icon(
                      Icons.chevron_right_rounded,
                      size: 22,
                      color: _ResourcePalette.muted,
                    ),
                  ],
                ],
              ),
              if (progressPercent > 0 || isCompleted) ...[
                const SizedBox(height: AppSpacing.s12),
                ClipRRect(
                  borderRadius: AppRadii.brFull,
                  child: LinearProgressIndicator(
                    value: isCompleted ? 1 : progress,
                    minHeight: 4,
                    backgroundColor: _ResourcePalette.line,
                    valueColor: AlwaysStoppedAnimation(statusColor),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _ResourceIcon extends StatelessWidget {
  const _ResourceIcon({
    required this.icon,
    required this.color,
    required this.muted,
  });

  final IconData icon;
  final Color color;
  final bool muted;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 46,
      height: 46,
      decoration: BoxDecoration(
        color: color.withValues(alpha: muted ? 0.08 : 0.16),
        borderRadius: AppRadii.br12,
        border: Border.all(color: color.withValues(alpha: muted ? 0.12 : 0.28)),
      ),
      child: Icon(
        icon,
        color: muted ? _ResourcePalette.muted : color,
        size: 22,
      ),
    );
  }
}

class _ResourcePill extends StatelessWidget {
  const _ResourcePill({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: AppRadii.brFull,
        border: Border.all(color: color.withValues(alpha: 0.28)),
      ),
      child: Text(
        label,
        style: AppTypography.captionUpper.copyWith(
          color: color,
          fontSize: 10,
          letterSpacing: 0.7,
        ),
      ),
    );
  }
}
