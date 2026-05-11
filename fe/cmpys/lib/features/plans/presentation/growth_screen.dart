import 'dart:ui';
import 'package:flutter/material.dart';

import '../../../app/design_tokens.dart';
import '../../feed/presentation/discover_feed_screen.dart';
import 'plans_screen.dart';

class GrowthScreen extends StatefulWidget {
  const GrowthScreen({super.key});

  @override
  State<GrowthScreen> createState() => _GrowthScreenState();
}

class _GrowthScreenState extends State<GrowthScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _tabController.addListener(() => setState(() {})); // To redraw active tab
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      body: SizedBox.expand(
        child: Stack(
          children: [
            TabBarView(
              controller: _tabController,
              children: const [PlansScreen(), DiscoverFeedScreen()],
            ),
            Positioned(
              top: MediaQuery.paddingOf(context).top + 16,
              left: 0,
              right: 0,
              child: Center(child: _buildFloatingSegmentControl()),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFloatingSegmentControl() {
    return ClipRRect(
      borderRadius: AppRadii.brFull,
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
        child: Container(
          padding: const EdgeInsets.all(4),
          decoration: BoxDecoration(
            color: AppColors.surface.withValues(alpha: 0.84),
            borderRadius: AppRadii.brFull,
            border: Border.all(color: AppColors.border, width: 0.5),
            boxShadow: AppShadows.sm,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              _SegmentTab(
                title: 'Journey',
                isActive: _tabController.index == 0,
                onTap: () => _tabController.animateTo(
                  0,
                  duration: AppDurations.fast,
                  curve: Curves.easeOutCubic,
                ),
              ),
              _SegmentTab(
                title: 'Ideas',
                isActive: _tabController.index == 1,
                onTap: () => _tabController.animateTo(
                  1,
                  duration: AppDurations.fast,
                  curve: Curves.easeOutCubic,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SegmentTab extends StatelessWidget {
  const _SegmentTab({
    required this.title,
    required this.isActive,
    required this.onTap,
  });

  final String title;
  final bool isActive;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOutCubic,
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
        decoration: BoxDecoration(
          color: isActive ? AppColors.brandAccent : Colors.transparent,
          borderRadius: AppRadii.brFull,
          boxShadow: isActive ? AppShadows.glowSubtle : null,
        ),
        child: Text(
          title,
          style: AppTypography.captionMedium.copyWith(
            color: isActive ? Colors.white : AppColors.textPrimary,
            fontWeight: isActive ? FontWeight.w700 : FontWeight.w500,
            fontSize: 13,
          ),
        ),
      ),
    );
  }
}
