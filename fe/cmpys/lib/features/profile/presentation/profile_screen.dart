import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:go_router/go_router.dart';

import '../../../app/assets.dart';
import '../../../app/design_tokens.dart';
import '../../../app/router.dart';
import '../../../core/ui/cmpys_button.dart';
import '../../../core/ui/cmpys_card.dart';
import '../../../core/ui/cmpys_chip.dart';
import '../../../core/ui/list_tile_card.dart';
import '../../../core/ui/loading_state.dart';
import '../../../core/ui/progress_ring.dart';
import '../../auth/controllers/auth_controller.dart';
import '../../auth/controllers/session_controller.dart';
import '../../comparison/controllers/comparison_controller.dart';

class ProfileScreen extends ConsumerStatefulWidget {
  const ProfileScreen({super.key});

  @override
  ConsumerState<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends ConsumerState<ProfileScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      // Load comparison data for progress
      ref.read(comparisonControllerProvider.notifier).load();
    });
  }

  @override
  Widget build(BuildContext context) {
    final currentUser = ref.watch(currentUserProvider);
    final sessionController = ref.watch(sessionControllerProvider.notifier);
    final comparisonState = ref.watch(comparisonControllerProvider);

    if (currentUser == null) {
      return const Scaffold(
        body: LoadingState(message: 'Loading profile...'),
      );
    }

    // Calculate user age
    final userAge = sessionController.userAge ?? 0;
    
    // Get comparison progress
    double progress = 0;
    String? idolName;
    if (comparisonState is ComparisonLoaded) {
      progress = comparisonState.comparison.overallScore / 100;
      idolName = comparisonState.comparison.idolName;
    }

    return Scaffold(
      backgroundColor: AppColors.bg,
      body: SafeArea(
        bottom: false,
        child: SingleChildScrollView(
          padding: EdgeInsets.only(bottom: AppSpacing.s100),
          child: Column(
            children: [
              // Header
              Padding(
                padding: AppSpacing.screenH,
                child: Column(
                  children: [
                    const SizedBox(height: AppSpacing.s8),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text('Profile', style: AppTypography.h1),
                        CmpysIconButton(
                          icon: AppAssets.iconSettings,
                          onPressed: () => _showSettings(context),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: AppSpacing.s24),
              // Profile card
              Padding(
                padding: AppSpacing.screenH,
                child: CmpysCard(
                  padding: AppSpacing.p20,
                  child: Column(
                    children: [
                      GradientAvatar(
                        initials: _getInitials(currentUser.fullName ?? currentUser.email),
                        size: 72,
                      ),
                      const SizedBox(height: AppSpacing.s16),
                      Text(
                        currentUser.fullName ?? 'User',
                        style: AppTypography.h2,
                      ),
                      const SizedBox(height: AppSpacing.s4),
                      Text(
                        currentUser.email,
                        style: AppTypography.body.copyWith(
                          color: AppColors.textSecondary,
                        ),
                      ),
                      const SizedBox(height: AppSpacing.s16),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          _StatItem(
                            value: '$userAge',
                            label: 'Age',
                          ),
                          Container(
                            width: 1,
                            height: 32,
                            margin: const EdgeInsets.symmetric(horizontal: AppSpacing.s20),
                            color: AppColors.border,
                          ),
                          _StatItem(
                            value: '${currentUser.interests.length}',
                            label: 'Interests',
                          ),
                        ],
                      ),
                      const SizedBox(height: AppSpacing.s16),
                      CmpysButton(
                        label: 'Edit Profile',
                        variant: CmpysButtonVariant.secondary,
                        size: CmpysButtonSize.medium,
                        icon: AppAssets.iconEdit,
                        onPressed: () {},
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: AppSpacing.s24),
              // Interests
              if (currentUser.interests.isNotEmpty) ...[
                Padding(
                  padding: AppSpacing.screenH,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Interests', style: AppTypography.h4),
                      const SizedBox(height: AppSpacing.s12),
                      Wrap(
                        spacing: AppSpacing.s8,
                        runSpacing: AppSpacing.s8,
                        children: currentUser.interests
                            .map((interest) => CmpysTag(label: interest))
                            .toList(),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: AppSpacing.s24),
              ],
              // Progress overview
              Padding(
                padding: AppSpacing.screenH,
                child: CmpysCard(
                  padding: AppSpacing.p16,
                  onTap: () => context.go(AppRoutes.comparison),
                  child: Row(
                    children: [
                      ProgressRing(
                        progress: progress,
                        size: 64,
                        strokeWidth: 6,
                      ),
                      const SizedBox(width: AppSpacing.s16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Overall Progress',
                              style: AppTypography.bodyMedium,
                            ),
                            const SizedBox(height: AppSpacing.s4),
                            Text(
                              idolName != null
                                  ? 'Comparing with $idolName'
                                  : 'Select an idol to compare',
                              style: AppTypography.caption.copyWith(
                                color: AppColors.textSecondary,
                              ),
                            ),
                          ],
                        ),
                      ),
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
                  ),
                ),
              ),
              const SizedBox(height: AppSpacing.s32),
            ],
          ),
        ),
      ),
    );
  }

  String _getInitials(String name) {
    final parts = name.split(' ');
    if (parts.length >= 2) {
      return '${parts.first[0]}${parts.last[0]}'.toUpperCase();
    }
    if (name.contains('@')) {
      return name.substring(0, 2).toUpperCase();
    }
    return name.substring(0, name.length >= 2 ? 2 : 1).toUpperCase();
  }

  void _showSettings(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => const SettingsScreen(),
      ),
    );
  }
}

class _StatItem extends StatelessWidget {
  const _StatItem({
    required this.value,
    required this.label,
  });

  final String value;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(value, style: AppTypography.h3),
        Text(
          label,
          style: AppTypography.caption.copyWith(
            color: AppColors.textSecondary,
          ),
        ),
      ],
    );
  }
}

// Settings Screen
class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: AppColors.bg,
        leading: IconButton(
          onPressed: () => Navigator.pop(context),
          icon: SvgPicture.asset(
            AppAssets.iconChevronLeft,
            width: 24,
            height: 24,
            colorFilter: const ColorFilter.mode(
              AppColors.textPrimary,
              BlendMode.srcIn,
            ),
          ),
        ),
        title: Text('Settings', style: AppTypography.h3),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: AppSpacing.screenH,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: AppSpacing.s16),
              Text(
                'Account',
                style: AppTypography.caption.copyWith(
                  color: AppColors.textSecondary,
                ),
              ),
              const SizedBox(height: AppSpacing.s12),
              CmpysCard(
                padding: EdgeInsets.zero,
                child: Column(
                  children: [
                    SettingsTile(
                      title: 'Edit Profile',
                      icon: AppAssets.iconUser,
                      onTap: () {},
                    ),
                    SettingsTile(
                      title: 'Change Idol',
                      icon: AppAssets.iconUsers,
                      onTap: () => context.push(AppRoutes.idolSuggest),
                    ),
                    SettingsTile(
                      title: 'Notifications',
                      icon: AppAssets.iconBell,
                      onTap: () {},
                      showDivider: false,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: AppSpacing.s24),
              Text(
                'Preferences',
                style: AppTypography.caption.copyWith(
                  color: AppColors.textSecondary,
                ),
              ),
              const SizedBox(height: AppSpacing.s12),
              CmpysCard(
                padding: EdgeInsets.zero,
                child: Column(
                  children: [
                    SettingsTile(
                      title: 'Appearance',
                      icon: AppAssets.iconEye,
                      subtitle: 'Dark',
                      onTap: () {},
                    ),
                    SettingsTile(
                      title: 'Language',
                      icon: AppAssets.iconMessageCircle,
                      subtitle: 'English',
                      onTap: () {},
                      showDivider: false,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: AppSpacing.s24),
              Text(
                'Support',
                style: AppTypography.caption.copyWith(
                  color: AppColors.textSecondary,
                ),
              ),
              const SizedBox(height: AppSpacing.s12),
              CmpysCard(
                padding: EdgeInsets.zero,
                child: Column(
                  children: [
                    SettingsTile(
                      title: 'Help Center',
                      icon: AppAssets.iconCircleHelp,
                      onTap: () {},
                    ),
                    SettingsTile(
                      title: 'Privacy Policy',
                      icon: AppAssets.iconFileText,
                      onTap: () {},
                    ),
                    SettingsTile(
                      title: 'Terms of Service',
                      icon: AppAssets.iconFileText,
                      onTap: () {},
                      showDivider: false,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: AppSpacing.s24),
              CmpysCard(
                padding: EdgeInsets.zero,
                child: SettingsTile(
                  title: 'Sign Out',
                  icon: AppAssets.iconArrowLeft,
                  iconColor: AppColors.error,
                  onTap: () async {
                    await ref.read(authControllerProvider.notifier).logout();
                    if (context.mounted) {
                      context.go(AppRoutes.auth);
                    }
                  },
                  showDivider: false,
                  trailing: const SizedBox.shrink(),
                ),
              ),
              const SizedBox(height: AppSpacing.s32),
              Center(
                child: Text(
                  'CMPYS v1.0.0',
                  style: AppTypography.caption.copyWith(
                    color: AppColors.textTertiary,
                  ),
                ),
              ),
              const SizedBox(height: AppSpacing.s32),
            ],
          ),
        ),
      ),
    );
  }
}
