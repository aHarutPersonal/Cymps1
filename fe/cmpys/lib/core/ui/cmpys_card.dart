import 'package:flutter/material.dart';

import '../../app/design_tokens.dart';

/// Card component with consistent styling.
class CmpysCard extends StatelessWidget {
  const CmpysCard({
    super.key,
    required this.child,
    this.onTap,
    this.padding,
    this.margin,
    this.backgroundColor,
    this.borderColor,
    this.borderRadius,
    this.borderWidth = 1,
    this.showBorder = true,
    this.shadow,
  });

  final Widget child;
  final VoidCallback? onTap;
  final EdgeInsets? padding;
  final EdgeInsets? margin;
  final Color? backgroundColor;
  final Color? borderColor;
  final BorderRadius? borderRadius;
  final double borderWidth;
  final bool showBorder;
  final List<BoxShadow>? shadow;

  @override
  Widget build(BuildContext context) {
    final content = Container(
      padding: padding ?? AppSpacing.p20,
      margin: margin,
      decoration: BoxDecoration(
        color: backgroundColor ?? AppColors.surface,
        borderRadius: borderRadius ?? AppRadii.br16,
        border: showBorder
            ? Border.all(
                color: borderColor ?? AppColors.borderLight,
                width: borderWidth,
              )
            : null,
        boxShadow: shadow,
      ),
      child: child,
    );

    if (onTap != null) {
      return GestureDetector(
        onTap: onTap,
        child: content,
      );
    }

    return content;
  }
}

/// Card with gradient border (for accent/premium items).
class CmpysGradientCard extends StatelessWidget {
  const CmpysGradientCard({
    super.key,
    required this.child,
    this.onTap,
    this.padding,
    this.margin,
    this.gradient,
    this.borderRadius,
    this.borderWidth = 1,
  });

  final Widget child;
  final VoidCallback? onTap;
  final EdgeInsets? padding;
  final EdgeInsets? margin;
  final Gradient? gradient;
  final BorderRadius? borderRadius;
  final double borderWidth;

  @override
  Widget build(BuildContext context) {
    final radius = borderRadius ?? AppRadii.br16;
    final defaultGradient = LinearGradient(
      colors: [
        AppColors.emerald.withOpacity(0.3),
        AppColors.blue.withOpacity(0.1),
      ],
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
    );

    Widget content = Container(
      margin: EdgeInsets.all(borderWidth),
      padding: padding ?? AppSpacing.p20,
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(
          radius.topLeft.x - borderWidth,
        ),
      ),
      child: child,
    );

    content = Container(
      margin: margin,
      decoration: BoxDecoration(
        gradient: gradient ?? defaultGradient,
        borderRadius: radius,
      ),
      child: content,
    );

    if (onTap != null) {
      return GestureDetector(
        onTap: onTap,
        child: content,
      );
    }

    return content;
  }
}

/// Section header with optional action.
class CmpysSectionHeader extends StatelessWidget {
  const CmpysSectionHeader({
    super.key,
    required this.title,
    this.action,
    this.onActionTap,
    this.padding,
  });

  final String title;
  final String? action;
  final VoidCallback? onActionTap;
  final EdgeInsets? padding;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: padding ??
          const EdgeInsets.only(
            top: AppSpacing.s24,
            bottom: AppSpacing.s12,
          ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            title.toUpperCase(),
            style: AppTypography.captionUpper,
          ),
          if (action != null)
            GestureDetector(
              onTap: onActionTap,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    action!,
                    style: AppTypography.caption.copyWith(
                      color: AppColors.textSecondary,
                    ),
                  ),
                  const SizedBox(width: AppSpacing.s4),
                  const Icon(
                    Icons.chevron_right,
                    size: 16,
                    color: AppColors.textSecondary,
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
