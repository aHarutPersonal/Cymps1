import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:go_router/go_router.dart';

import '../../app/assets.dart';
import '../../app/design_tokens.dart';

/// Custom app bar matching Figma design.
class CmpysAppBar extends StatelessWidget implements PreferredSizeWidget {
  const CmpysAppBar({
    super.key,
    this.title,
    this.titleWidget,
    this.leading,
    this.showBackButton = true,
    this.actions,
    this.backgroundColor,
    this.centerTitle = false,
    this.elevation = 0,
    this.bottom,
    this.onBackPressed,
  });

  final String? title;
  final Widget? titleWidget;
  final Widget? leading;
  final bool showBackButton;
  final List<Widget>? actions;
  final Color? backgroundColor;
  final bool centerTitle;
  final double elevation;
  final PreferredSizeWidget? bottom;
  final VoidCallback? onBackPressed;

  @override
  Size get preferredSize =>
      Size.fromHeight(kToolbarHeight + (bottom?.preferredSize.height ?? 0));

  @override
  Widget build(BuildContext context) {
    final canPop = context.canPop();

    Widget? leadingWidget = leading;
    if (leadingWidget == null && showBackButton && canPop) {
      leadingWidget = CmpysBackButton(onPressed: onBackPressed);
    }

    return AppBar(
      backgroundColor: backgroundColor ?? AppColors.bg,
      elevation: elevation,
      scrolledUnderElevation: 0,
      centerTitle: centerTitle,
      automaticallyImplyLeading: false,
      leading: leadingWidget,
      leadingWidth: leadingWidget != null ? 56 : 0,
      title:
          titleWidget ??
          (title != null ? Text(title!, style: AppTypography.h3) : null),
      actions: actions != null
          ? [...actions!, const SizedBox(width: AppSpacing.s8)]
          : null,
      bottom: bottom,
    );
  }
}

/// Back button with consistent styling.
class CmpysBackButton extends StatelessWidget {
  const CmpysBackButton({super.key, this.onPressed, this.color});

  final VoidCallback? onPressed;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      onPressed:
          onPressed ??
          () {
            if (context.canPop()) {
              context.pop();
            }
          },
      icon: SvgPicture.asset(
        AppAssets.iconChevronLeft,
        width: 24,
        height: 24,
        colorFilter: ColorFilter.mode(
          color ?? AppColors.textPrimary,
          BlendMode.srcIn,
        ),
      ),
    );
  }
}

/// App bar action button.
class CmpysAppBarAction extends StatelessWidget {
  const CmpysAppBarAction({
    super.key,
    required this.icon,
    required this.onPressed,
    this.badge,
    this.color,
  });

  final String icon;
  final VoidCallback onPressed;
  final int? badge;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        IconButton(
          onPressed: onPressed,
          style: IconButton.styleFrom(
            backgroundColor: AppColors.surface,
            shape: RoundedRectangleBorder(
              borderRadius: AppRadii.br12,
              side: const BorderSide(color: AppColors.border),
            ),
          ),
          icon: SvgPicture.asset(
            icon,
            width: 20,
            height: 20,
            colorFilter: ColorFilter.mode(
              color ?? AppColors.textSecondary,
              BlendMode.srcIn,
            ),
          ),
        ),
        if (badge != null && badge! > 0)
          Positioned(
            right: 6,
            top: 6,
            child: Container(
              padding: const EdgeInsets.all(4),
              decoration: const BoxDecoration(
                color: AppColors.error,
                shape: BoxShape.circle,
              ),
              constraints: const BoxConstraints(minWidth: 16, minHeight: 16),
              child: Text(
                badge! > 99 ? '99+' : badge.toString(),
                style: AppTypography.tiny.copyWith(
                  color: AppColors.textPrimary,
                  fontSize: 9,
                ),
                textAlign: TextAlign.center,
              ),
            ),
          ),
      ],
    );
  }
}

/// Large title header for screens.
class CmpysScreenHeader extends StatelessWidget {
  const CmpysScreenHeader({
    super.key,
    required this.title,
    this.subtitle,
    this.trailing,
  });

  final String title;
  final String? subtitle;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(
        top: AppSpacing.s8,
        bottom: AppSpacing.s24,
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: AppTypography.h1),
                if (subtitle != null) ...[
                  const SizedBox(height: AppSpacing.s4),
                  Text(
                    subtitle!,
                    style: AppTypography.body.copyWith(
                      color: AppColors.textSecondary,
                    ),
                  ),
                ],
              ],
            ),
          ),
          if (trailing != null) trailing!,
        ],
      ),
    );
  }
}
