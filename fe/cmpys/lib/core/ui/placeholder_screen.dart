import 'package:flutter/material.dart';

import '../../app/design_tokens.dart';
import 'ambient_background.dart';

/// Placeholder screen for routes under development.
class PlaceholderScreen extends StatelessWidget {
  const PlaceholderScreen({
    super.key,
    required this.title,
    this.subtitle,
    this.icon,
    this.showBackButton = true,
  });

  final String title;
  final String? subtitle;
  final IconData? icon;
  final bool showBackButton;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: showBackButton
          ? AppBar(
              backgroundColor: Colors.transparent,
              surfaceTintColor: Colors.transparent,
              scrolledUnderElevation: 0,
              title: Text(title),
              leading: Navigator.canPop(context)
                  ? IconButton(
                      icon: const Icon(Icons.arrow_back),
                      onPressed: () => Navigator.pop(context),
                    )
                  : null,
            )
          : null,
      backgroundColor: AppColors.bg,
      body: AmbientBackground(
        useSafeArea: false,
        child: Center(
          child: Padding(
            padding: AppSpacing.screenH,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (icon != null) ...[
                  Container(
                    width: 80,
                    height: 80,
                    decoration: BoxDecoration(
                      color: AppColors.surface,
                      borderRadius: AppRadii.br20,
                      border: Border.all(color: AppColors.border),
                      boxShadow: AppShadows.sm,
                    ),
                    child: Icon(icon, size: 40, color: AppColors.accent),
                  ),
                  const SizedBox(height: AppSpacing.s24),
                ],
                Text(
                  showBackButton ? '' : title,
                  style: AppTypography.h2,
                  textAlign: TextAlign.center,
                ),
                if (!showBackButton) const SizedBox(height: AppSpacing.s8),
                if (subtitle != null)
                  Text(
                    subtitle!,
                    style: AppTypography.body.copyWith(
                      color: AppColors.textSecondary,
                    ),
                    textAlign: TextAlign.center,
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
