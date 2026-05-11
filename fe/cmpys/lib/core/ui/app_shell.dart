import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../app/design_tokens.dart';
import '../../app/router.dart';

/// Main app shell with product-deck glass navigation.
class AppShell extends StatelessWidget {
  const AppShell({super.key, required this.navigationShell});

  final StatefulNavigationShell navigationShell;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: navigationShell,
      extendBody: true, // content extends behind the blurred nav bar
      floatingActionButton: FloatingActionButton(
        backgroundColor: AppColors.brandAccent,
        foregroundColor: Colors.white,
        elevation: 0,
        shape: const StadiumBorder(),
        onPressed: () {
          HapticFeedback.lightImpact();
          context.goToChat();
        },
        child: const Icon(PhosphorIconsBold.chatCircle),
      ),
      bottomNavigationBar: _GlassNavBar(
        currentIndex: navigationShell.currentIndex,
        onTap: (index) => _onTap(context, index),
      ),
    );
  }

  void _onTap(BuildContext context, int index) {
    HapticFeedback.selectionClick();
    navigationShell.goBranch(
      index,
      initialLocation: index == navigationShell.currentIndex,
    );
  }
}

/// Glassmorphism bottom navigation bar with frosted-glass effect.
class _GlassNavBar extends StatelessWidget {
  const _GlassNavBar({required this.currentIndex, required this.onTap});

  final int currentIndex;
  final ValueChanged<int> onTap;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 24, sigmaY: 24),
        child: Container(
          decoration: BoxDecoration(
            color: AppColors.surface.withValues(alpha: 0.88),
            border: Border(
              top: BorderSide(
                color: AppColors.glassBorder.withValues(alpha: 0.9),
                width: 0.8,
              ),
            ),
            boxShadow: [
              BoxShadow(
                color: AppColors.charcoal.withValues(alpha: 0.08),
                blurRadius: 24,
                offset: const Offset(0, -10),
              ),
            ],
          ),
          child: SafeArea(
            top: false,
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 56, maxHeight: 80),
              child: Padding(
                padding: const EdgeInsets.only(top: 10),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: [
                    _NavItem(
                      icon: PhosphorIconsBold.house,
                      iconOutline: PhosphorIconsRegular.house,
                      label: 'MIRROR',
                      isSelected: currentIndex == 0,
                      onTap: () => onTap(0),
                    ),
                    _NavItem(
                      icon: PhosphorIconsBold.trendUp,
                      iconOutline: PhosphorIconsRegular.trendUp,
                      label: 'PATH',
                      isSelected: currentIndex == 1,
                      onTap: () => onTap(1),
                    ),
                    _NavItem(
                      icon: PhosphorIconsBold.cpu,
                      iconOutline: PhosphorIconsRegular.cpu,
                      label: 'STUDIO',
                      isSelected: currentIndex == 2,
                      onTap: () => onTap(2),
                    ),
                    _NavItem(
                      icon: PhosphorIconsBold.vault,
                      iconOutline: PhosphorIconsRegular.vault,
                      label: 'VAULT',
                      isSelected: currentIndex == 3,
                      onTap: () => onTap(3),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Individual navigation item with bold/regular icon toggle.
class _NavItem extends StatelessWidget {
  const _NavItem({
    required this.icon,
    required this.iconOutline,
    required this.label,
    required this.isSelected,
    required this.onTap,
  });

  final IconData icon; // bold fill
  final IconData iconOutline; // regular outline
  final String label;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: label,
      selected: isSelected,
      button: true,
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minWidth: 48, maxWidth: 72),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            mainAxisSize: MainAxisSize.min,
            children: [
              AnimatedSwitcher(
                duration: AppDurations.fast,
                child: Icon(
                  isSelected ? icon : iconOutline,
                  key: ValueKey(isSelected),
                  size: 24,
                  color: isSelected
                      ? AppColors.brandAccent
                      : AppColors.textTertiary,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                label,
                style: AppTypography.captionUpper.copyWith(
                  fontSize: 10,
                  color: isSelected
                      ? AppColors.brandAccent
                      : AppColors.textTertiary,
                  fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
