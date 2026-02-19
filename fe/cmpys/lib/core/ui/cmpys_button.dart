import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../../app/design_tokens.dart';

enum CmpysButtonVariant { primary, secondary, ghost, danger }

enum CmpysButtonSize { small, medium, large }

/// Primary button component.
class CmpysButton extends StatelessWidget {
  const CmpysButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.variant = CmpysButtonVariant.primary,
    this.size = CmpysButtonSize.large,
    this.icon,
    this.iconRight,
    this.isLoading = false,
    this.isExpanded = true,
    this.disabled = false,
  });

  final String label;
  final VoidCallback? onPressed;
  final CmpysButtonVariant variant;
  final CmpysButtonSize size;
  final String? icon;
  final String? iconRight;
  final bool isLoading;
  final bool isExpanded;
  final bool disabled;

  @override
  Widget build(BuildContext context) {
    final isDisabled = disabled || isLoading || onPressed == null;

    final (height, textStyle, iconSize, padding) = switch (size) {
      CmpysButtonSize.small => (
          40.0,
          AppTypography.buttonSmall,
          16.0,
          AppSpacing.ph16,
        ),
      CmpysButtonSize.medium => (
          48.0,
          AppTypography.buttonSmall,
          18.0,
          AppSpacing.ph20,
        ),
      CmpysButtonSize.large => (
          52.0,
          AppTypography.button,
          20.0,
          AppSpacing.ph24,
        ),
    };

    final (bgColor, fgColor, borderColor) = _getColors(isDisabled);

    Widget child = Row(
      mainAxisSize: isExpanded ? MainAxisSize.max : MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        if (isLoading) ...[
          SizedBox(
            width: iconSize,
            height: iconSize,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: fgColor,
            ),
          ),
          const SizedBox(width: AppSpacing.s8),
        ] else if (icon != null) ...[
          SvgPicture.asset(
            icon!,
            width: iconSize,
            height: iconSize,
            colorFilter: ColorFilter.mode(fgColor, BlendMode.srcIn),
          ),
          const SizedBox(width: AppSpacing.s8),
        ],
        Text(
          label,
          style: textStyle.copyWith(color: fgColor),
        ),
        if (iconRight != null && !isLoading) ...[
          const SizedBox(width: AppSpacing.s8),
          SvgPicture.asset(
            iconRight!,
            width: iconSize,
            height: iconSize,
            colorFilter: ColorFilter.mode(fgColor, BlendMode.srcIn),
          ),
        ],
      ],
    );

    return SizedBox(
      width: isExpanded ? double.infinity : null,
      height: height,
      child: Material(
        color: bgColor,
        borderRadius: AppRadii.br12,
        child: InkWell(
          onTap: isDisabled ? null : onPressed,
          borderRadius: AppRadii.br12,
          child: Container(
            padding: padding,
            decoration: BoxDecoration(
              borderRadius: AppRadii.br12,
              border: borderColor != null
                  ? Border.all(color: borderColor)
                  : null,
            ),
            child: child,
          ),
        ),
      ),
    );
  }

  (Color bg, Color fg, Color? border) _getColors(bool isDisabled) {
    if (isDisabled) {
      return switch (variant) {
        CmpysButtonVariant.primary => (
            AppColors.textPrimary.withOpacity(0.3),
            AppColors.bgTrue.withOpacity(0.5),
            null,
          ),
        CmpysButtonVariant.secondary => (
            Colors.transparent,
            AppColors.textSecondary.withOpacity(0.5),
            AppColors.borderLight,
          ),
        CmpysButtonVariant.ghost => (
            Colors.transparent,
            AppColors.textSecondary.withOpacity(0.5),
            null,
          ),
        CmpysButtonVariant.danger => (
            AppColors.error.withOpacity(0.3),
            AppColors.textPrimary.withOpacity(0.5),
            null,
          ),
      };
    }

    return switch (variant) {
      CmpysButtonVariant.primary => (
          AppColors.textPrimary, // White bg
          AppColors.bgTrue, // Black text
          null,
        ),
      CmpysButtonVariant.secondary => (
          Colors.transparent,
          AppColors.textPrimary,
          AppColors.borderFocus, // 15% white border
        ),
      CmpysButtonVariant.ghost => (
          Colors.transparent,
          AppColors.textPrimary,
          null,
        ),
      CmpysButtonVariant.danger => (
          AppColors.error,
          AppColors.textPrimary,
          null,
        ),
    };
  }
}

/// Icon-only button.
class CmpysIconButton extends StatelessWidget {
  const CmpysIconButton({
    super.key,
    required this.icon,
    required this.onPressed,
    this.size = 40,
    this.iconSize = 20,
    this.backgroundColor,
    this.iconColor,
    this.showBorder = true,
    this.tooltip,
  });

  final String icon;
  final VoidCallback? onPressed;
  final double size;
  final double iconSize;
  final Color? backgroundColor;
  final Color? iconColor;
  final bool showBorder;
  final String? tooltip;

  @override
  Widget build(BuildContext context) {
    final button = Material(
      color: backgroundColor ?? Colors.transparent,
      shape: CircleBorder(
        side: showBorder
            ? const BorderSide(color: AppColors.borderLight)
            : BorderSide.none,
      ),
      child: InkWell(
        onTap: onPressed,
        customBorder: const CircleBorder(),
        child: SizedBox(
          width: size,
          height: size,
          child: Center(
            child: SvgPicture.asset(
              icon,
              width: iconSize,
              height: iconSize,
              colorFilter: ColorFilter.mode(
                iconColor ?? AppColors.textPrimary,
                BlendMode.srcIn,
              ),
            ),
          ),
        ),
      ),
    );

    if (tooltip != null) {
      return Tooltip(message: tooltip!, child: button);
    }

    return button;
  }
}

/// Floating action button.
class CmpysFab extends StatelessWidget {
  const CmpysFab({
    super.key,
    required this.icon,
    required this.onPressed,
    this.label,
    this.backgroundColor,
    this.iconColor,
  });

  final String icon;
  final VoidCallback onPressed;
  final String? label;
  final Color? backgroundColor;
  final Color? iconColor;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: backgroundColor ?? AppColors.textPrimary,
      borderRadius: label != null ? AppRadii.br12 : AppRadii.brFull,
      elevation: 0,
      child: InkWell(
        onTap: onPressed,
        borderRadius: label != null ? AppRadii.br12 : AppRadii.brFull,
        child: Container(
          height: 52,
          padding: EdgeInsets.symmetric(
            horizontal: label != null ? AppSpacing.s20 : AppSpacing.s16,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              SvgPicture.asset(
                icon,
                width: 24,
                height: 24,
                colorFilter: ColorFilter.mode(
                  iconColor ?? AppColors.bgTrue,
                  BlendMode.srcIn,
                ),
              ),
              if (label != null) ...[
                const SizedBox(width: AppSpacing.s8),
                Text(
                  label!,
                  style: AppTypography.button.copyWith(
                    color: iconColor ?? AppColors.bgTrue,
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
