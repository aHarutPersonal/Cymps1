import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../../app/assets.dart';
import '../../app/design_tokens.dart';
import 'cmpys_card.dart';

/// List tile card for settings, idol cards, etc.
class ListTileCard extends StatelessWidget {
  const ListTileCard({
    super.key,
    required this.title,
    this.subtitle,
    this.leading,
    this.trailing,
    this.onTap,
    this.showChevron = false,
    this.padding,
    this.backgroundColor,
    this.titleStyle,
    this.subtitleStyle,
  });

  final String title;
  final String? subtitle;
  final Widget? leading;
  final Widget? trailing;
  final VoidCallback? onTap;
  final bool showChevron;
  final EdgeInsets? padding;
  final Color? backgroundColor;
  final TextStyle? titleStyle;
  final TextStyle? subtitleStyle;

  @override
  Widget build(BuildContext context) {
    return CmpysCard(
      onTap: onTap,
      backgroundColor: backgroundColor,
      padding:
          padding ??
          const EdgeInsets.symmetric(
            horizontal: AppSpacing.s16,
            vertical: AppSpacing.s12,
          ),
      child: Row(
        children: [
          if (leading != null) ...[
            leading!,
            const SizedBox(width: AppSpacing.s12),
          ],
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  title,
                  style: titleStyle ?? AppTypography.bodyMedium,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                if (subtitle != null) ...[
                  const SizedBox(height: AppSpacing.s4),
                  Text(
                    subtitle!,
                    style:
                        subtitleStyle ??
                        AppTypography.caption.copyWith(
                          color: AppColors.textSecondary,
                        ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ],
            ),
          ),
          if (trailing != null) ...[
            const SizedBox(width: AppSpacing.s12),
            trailing!,
          ],
          if (showChevron) ...[
            const SizedBox(width: AppSpacing.s8),
            SvgPicture.asset(
              AppAssets.iconChevronRight,
              width: 20,
              height: 20,
              colorFilter: const ColorFilter.mode(
                AppColors.textTertiary,
                BlendMode.srcIn,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Avatar for list tiles with CachedNetworkImage support.
class ListTileAvatar extends StatelessWidget {
  const ListTileAvatar({
    super.key,
    this.imageUrl,
    this.initials,
    this.icon,
    this.size = 44,
    this.backgroundColor,
    this.foregroundColor,
  });

  final String? imageUrl;
  final String? initials;
  final String? icon;
  final double size;
  final Color? backgroundColor;
  final Color? foregroundColor;

  @override
  Widget build(BuildContext context) {
    final borderRadius = BorderRadius.circular(size / 3);

    // If we have an image URL, use CachedNetworkImage
    if (imageUrl != null && imageUrl!.isNotEmpty) {
      return ClipRRect(
        borderRadius: borderRadius,
        child: CachedNetworkImage(
          imageUrl: imageUrl!,
          width: size,
          height: size,
          fit: BoxFit.cover,
          placeholder: (context, url) => _buildPlaceholder(borderRadius),
          errorWidget: (context, url, error) => _buildFallback(borderRadius),
        ),
      );
    }

    return _buildFallback(borderRadius);
  }

  Widget _buildPlaceholder(BorderRadius borderRadius) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: backgroundColor ?? AppColors.surface2,
        borderRadius: borderRadius,
      ),
      child: Center(
        child: SizedBox(
          width: size * 0.4,
          height: size * 0.4,
          child: const CircularProgressIndicator(
            strokeWidth: 2,
            color: AppColors.textTertiary,
          ),
        ),
      ),
    );
  }

  Widget _buildFallback(BorderRadius borderRadius) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: backgroundColor ?? AppColors.surface2,
        borderRadius: borderRadius,
      ),
      child: Center(
        child: icon != null
            ? SvgPicture.asset(
                icon!,
                width: size * 0.5,
                height: size * 0.5,
                colorFilter: ColorFilter.mode(
                  foregroundColor ?? AppColors.textSecondary,
                  BlendMode.srcIn,
                ),
              )
            : initials != null && initials!.isNotEmpty
            ? Text(
                initials!,
                style: AppTypography.bodyMedium.copyWith(
                  color: foregroundColor ?? AppColors.textPrimary,
                  fontSize: size * 0.35,
                ),
              )
            : SvgPicture.asset(
                AppAssets.iconUser,
                width: size * 0.5,
                height: size * 0.5,
                colorFilter: ColorFilter.mode(
                  foregroundColor ?? AppColors.textSecondary,
                  BlendMode.srcIn,
                ),
              ),
      ),
    );
  }
}

/// Gradient avatar for premium items with optional image.
class GradientAvatar extends StatelessWidget {
  const GradientAvatar({
    super.key,
    required this.initials,
    this.imageUrl,
    this.size = 44,
    this.gradient,
  });

  final String initials;
  final String? imageUrl;
  final double size;
  final Gradient? gradient;

  @override
  Widget build(BuildContext context) {
    final borderRadius = BorderRadius.circular(size / 3);

    // If we have an image URL, use CachedNetworkImage
    if (imageUrl != null && imageUrl!.isNotEmpty) {
      return ClipRRect(
        borderRadius: borderRadius,
        child: CachedNetworkImage(
          imageUrl: imageUrl!,
          width: size,
          height: size,
          fit: BoxFit.cover,
          placeholder: (context, url) => _buildGradientAvatar(borderRadius),
          errorWidget: (context, url, error) =>
              _buildGradientAvatar(borderRadius),
        ),
      );
    }

    return _buildGradientAvatar(borderRadius);
  }

  Widget _buildGradientAvatar(BorderRadius borderRadius) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        gradient:
            gradient ??
            const LinearGradient(
              colors: [AppColors.accent, AppColors.accentLight],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
        borderRadius: borderRadius,
        boxShadow: [
          BoxShadow(
            color: AppColors.accent.withValues(alpha: 0.3),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Center(
        child: Text(
          initials,
          style: AppTypography.bodyMedium.copyWith(
            color: AppColors.textPrimary,
            fontSize: size * 0.35,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }
}

/// Settings list tile with icon.
abstract final class _SettingsTilePalette {
  static const ink = AppColors.textPrimary;
  static const muted = AppColors.textSecondary;
  static const line = AppColors.border;
  static const coral = AppColors.brandAccent;
}

class SettingsTile extends StatelessWidget {
  const SettingsTile({
    super.key,
    required this.title,
    required this.icon,
    this.subtitle,
    this.onTap,
    this.trailing,
    this.iconColor,
    this.showDivider = true,
  });

  final String title;
  final String icon;
  final String? subtitle;
  final VoidCallback? onTap;
  final Widget? trailing;
  final Color? iconColor;
  final bool showDivider;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.s4,
                vertical: AppSpacing.s12,
              ),
              child: Row(
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: (iconColor ?? _SettingsTilePalette.coral)
                          .withValues(alpha: 0.1),
                      borderRadius: AppRadii.br12,
                    ),
                    child: Center(
                      child: SvgPicture.asset(
                        icon,
                        width: 20,
                        height: 20,
                        colorFilter: ColorFilter.mode(
                          iconColor ?? _SettingsTilePalette.coral,
                          BlendMode.srcIn,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.s12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          style: AppTypography.bodyMedium.copyWith(
                            color: _SettingsTilePalette.ink,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        if (subtitle != null)
                          Text(
                            subtitle!,
                            style: AppTypography.caption.copyWith(
                              color: _SettingsTilePalette.muted,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                      ],
                    ),
                  ),
                  trailing ??
                      SvgPicture.asset(
                        AppAssets.iconChevronRight,
                        width: 20,
                        height: 20,
                        colorFilter: const ColorFilter.mode(
                          _SettingsTilePalette.muted,
                          BlendMode.srcIn,
                        ),
                      ),
                ],
              ),
            ),
          ),
        ),
        if (showDivider)
          const Divider(
            height: 1,
            indent: 52,
            color: _SettingsTilePalette.line,
          ),
      ],
    );
  }
}

/// Idol selection card.
class IdolCard extends StatelessWidget {
  const IdolCard({
    super.key,
    required this.name,
    required this.initials,
    this.subtitle,
    this.imageUrl,
    this.onTap,
    this.isSelected = false,
    this.trailing,
  });

  final String name;
  final String initials;
  final String? subtitle;
  final String? imageUrl;
  final VoidCallback? onTap;
  final bool isSelected;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return CmpysCard(
      onTap: onTap,
      borderColor: isSelected ? AppColors.accent : null,
      borderWidth: isSelected ? 1.5 : 1,
      padding: const EdgeInsets.all(AppSpacing.s12),
      child: Row(
        children: [
          // Always use GradientAvatar which now supports images with fallback
          GradientAvatar(initials: initials, imageUrl: imageUrl, size: 48),
          const SizedBox(width: AppSpacing.s12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  style: AppTypography.bodyMedium,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                if (subtitle != null) ...[
                  const SizedBox(height: AppSpacing.s2),
                  Text(
                    subtitle!,
                    style: AppTypography.caption.copyWith(
                      color: AppColors.textSecondary,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ],
            ),
          ),
          if (trailing != null) trailing!,
          if (isSelected && trailing == null)
            SvgPicture.asset(
              AppAssets.iconCheckCircle,
              width: 24,
              height: 24,
              colorFilter: const ColorFilter.mode(
                AppColors.accent,
                BlendMode.srcIn,
              ),
            ),
        ],
      ),
    );
  }
}
