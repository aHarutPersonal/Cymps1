import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:go_router/go_router.dart';

import '../../../app/assets.dart';
import '../../../app/design_tokens.dart';
import '../../../app/router.dart';
import '../../../core/notifications/notification_provider.dart';
import '../../../core/ui/cmpys_button.dart';

import '../../../core/ui/cmpys_chip.dart';
import '../../../core/ui/list_tile_card.dart';
import '../../../core/ui/loading_state.dart';
import '../../../core/ui/progress_ring.dart';
import '../../auth/controllers/auth_controller.dart';
import '../../auth/controllers/session_controller.dart';
import '../../comparison/controllers/comparison_controller.dart';

abstract final class _ProfilePalette {
  static const canvas = AppColors.bg;
  static const paper = Color(0xFFFFFFFF);
  static const ink = AppColors.textPrimary;
  static const muted = AppColors.textSecondary;
  static const line = AppColors.border;
  static const coralDark = AppColors.brandAccentDark;
}

void _showProfileConsoleSheet(
  BuildContext context, {
  required String title,
  required String message,
  String actionLabel = 'Got it',
}) {
  showModalBottomSheet<void>(
    context: context,
    backgroundColor: Colors.transparent,
    builder: (context) {
      return Container(
        margin: const EdgeInsets.all(AppSpacing.s16),
        padding: const EdgeInsets.all(AppSpacing.s20),
        decoration: BoxDecoration(
          color: _ProfilePalette.paper,
          borderRadius: AppRadii.br24,
          border: Border.all(color: _ProfilePalette.line),
          boxShadow: AppShadows.lg,
        ),
        child: SafeArea(
          top: false,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 42,
                height: 4,
                decoration: BoxDecoration(
                  color: _ProfilePalette.line,
                  borderRadius: AppRadii.brFull,
                ),
              ),
              const SizedBox(height: AppSpacing.s20),
              Text(title, style: AppTypography.h3),
              const SizedBox(height: AppSpacing.s8),
              Text(
                message,
                style: AppTypography.body.copyWith(
                  color: _ProfilePalette.muted,
                ),
              ),
              const SizedBox(height: AppSpacing.s20),
              CmpysButton(
                label: actionLabel,
                size: CmpysButtonSize.medium,
                onPressed: () => Navigator.pop(context),
              ),
            ],
          ),
        ),
      );
    },
  );
}

void _showNotificationSettingsSheet(BuildContext context, WidgetRef ref) {
  showModalBottomSheet<void>(
    context: context,
    backgroundColor: Colors.transparent,
    builder: (context) {
      return Consumer(
        builder: (context, ref, _) {
          final settingsAsync = ref.watch(notificationSettingsProvider);
          return Container(
            margin: const EdgeInsets.all(AppSpacing.s16),
            padding: const EdgeInsets.all(AppSpacing.s20),
            decoration: BoxDecoration(
              color: _ProfilePalette.paper,
              borderRadius: AppRadii.br24,
              border: Border.all(color: _ProfilePalette.line),
              boxShadow: AppShadows.lg,
            ),
            child: SafeArea(
              top: false,
              child: settingsAsync.when(
                loading: () => const Padding(
                  padding: EdgeInsets.all(24),
                  child: Center(child: CircularProgressIndicator()),
                ),
                error: (error, _) => Text(
                  'Could not load notification settings: $error',
                  style: AppTypography.body.copyWith(color: AppColors.error),
                ),
                data: (settings) => Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 42,
                      height: 4,
                      decoration: BoxDecoration(
                        color: _ProfilePalette.line,
                        borderRadius: AppRadii.brFull,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.s20),
                    Text('Daily reminder', style: AppTypography.h3),
                    const SizedBox(height: AppSpacing.s8),
                    Text(
                      'Use reminders as the trigger for Today: daily focus, reading, and reflection.',
                      style: AppTypography.body.copyWith(
                        color: _ProfilePalette.muted,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.s16),
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Reminder time'),
                      subtitle: Text(settings.timeString),
                      trailing: const Icon(Icons.schedule_outlined),
                      onTap: () async {
                        final picked = await showTimePicker(
                          context: context,
                          initialTime: TimeOfDay(
                            hour: settings.hour,
                            minute: settings.minute,
                          ),
                        );
                        if (picked == null) return;
                        final service = ref.read(notificationServiceProvider);
                        final granted = await service.requestPermissions();
                        if (!granted) return;
                        await service.scheduleDailyReminder(
                          hour: picked.hour,
                          minute: picked.minute,
                        );
                        ref.invalidate(notificationSettingsProvider);
                      },
                    ),
                    const SizedBox(height: AppSpacing.s12),
                    Row(
                      children: [
                        Expanded(
                          child: CmpysButton(
                            label: settings.enabled ? 'Update Time' : 'Enable',
                            size: CmpysButtonSize.medium,
                            onPressed: () async {
                              final service = ref.read(
                                notificationServiceProvider,
                              );
                              final granted = await service
                                  .requestPermissions();
                              if (!granted) return;
                              await service.scheduleDailyReminder(
                                hour: settings.hour,
                                minute: settings.minute,
                              );
                              ref.invalidate(notificationSettingsProvider);
                            },
                          ),
                        ),
                        const SizedBox(width: AppSpacing.s12),
                        Expanded(
                          child: CmpysButton(
                            label: 'Disable',
                            variant: CmpysButtonVariant.secondary,
                            size: CmpysButtonSize.medium,
                            onPressed: settings.enabled
                                ? () async {
                                    await ref
                                        .read(notificationServiceProvider)
                                        .cancelDailyReminder();
                                    ref.invalidate(
                                      notificationSettingsProvider,
                                    );
                                  }
                                : null,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      );
    },
  );
}

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
      ref.read(comparisonControllerProvider.notifier).load();
    });
  }

  @override
  Widget build(BuildContext context) {
    final currentUser = ref.watch(currentUserProvider);
    final sessionController = ref.watch(sessionControllerProvider.notifier);
    final comparisonState = ref.watch(comparisonControllerProvider);

    if (currentUser == null) {
      return const Scaffold(body: LoadingState(message: 'Loading profile...'));
    }

    final userAge = sessionController.userAge ?? 0;

    double progress = 0;
    String? idolName;
    if (comparisonState is ComparisonLoaded) {
      progress = comparisonState.comparison.overallScore / 100;
      idolName = comparisonState.comparison.idolName;
    }

    return Scaffold(
      backgroundColor: _ProfilePalette.canvas,
      body: DecoratedBox(
        decoration: const BoxDecoration(
          color: _ProfilePalette.canvas,
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              AppColors.surfaceHighlight,
              _ProfilePalette.canvas,
              AppColors.bg,
            ],
            stops: [0, 0.52, 1],
          ),
        ),
        child: SafeArea(
          bottom: false,
          child: SingleChildScrollView(
            padding: EdgeInsets.only(bottom: 88),
            child: Column(
              children: [
                // Header
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  child: Column(
                    children: [
                      const SizedBox(height: AppSpacing.s8),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            'Profile',
                            style: AppTypography.h2.copyWith(
                              color: _ProfilePalette.ink,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                          GestureDetector(
                            onTap: () => _showSettings(context),
                            child: Container(
                              width: 40,
                              height: 40,
                              decoration: BoxDecoration(
                                color: _ProfilePalette.paper,
                                shape: BoxShape.circle,
                                border: Border.all(color: _ProfilePalette.line),
                              ),
                              child: const Center(
                                child: Icon(
                                  Icons.settings_outlined,
                                  size: 20,
                                  color: _ProfilePalette.ink,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: AppSpacing.s24),
                // Profile card
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  child: Container(
                    padding: const EdgeInsets.all(24),
                    decoration: BoxDecoration(
                      color: _ProfilePalette.paper,
                      borderRadius: AppRadii.br24,
                      boxShadow: AppShadows.sm,
                      border: Border.all(color: _ProfilePalette.line),
                    ),
                    child: Column(
                      children: [
                        GradientAvatar(
                          initials: _getInitials(
                            currentUser.fullName ?? currentUser.email,
                          ),
                          size: 72,
                        ),
                        const SizedBox(height: AppSpacing.s16),
                        Text(
                          currentUser.fullName ?? 'User',
                          style: AppTypography.h3.copyWith(
                            color: _ProfilePalette.ink,
                          ),
                        ),
                        const SizedBox(height: AppSpacing.s4),
                        Text(
                          currentUser.email,
                          style: AppTypography.caption.copyWith(
                            color: _ProfilePalette.muted,
                          ),
                        ),
                        const SizedBox(height: AppSpacing.s16),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            _StatItem(value: '$userAge', label: 'Age'),
                            Container(
                              width: 1,
                              height: 32,
                              margin: const EdgeInsets.symmetric(
                                horizontal: AppSpacing.s20,
                              ),
                              color: _ProfilePalette.line,
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
                          onPressed: () => _showProfileConsoleSheet(
                            context,
                            title: 'Edit profile',
                            message:
                                'Profile editing will use the same onboarding console so identity, interests, and age stay in sync.',
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: AppSpacing.s24),
                // Interests
                if (currentUser.interests.isNotEmpty) ...[
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 24),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Interests',
                          style: AppTypography.h4.copyWith(
                            color: _ProfilePalette.ink,
                          ),
                        ),
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
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  child: GestureDetector(
                    onTap: () => context.go(AppRoutes.comparison),
                    child: Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: _ProfilePalette.paper,
                        borderRadius: AppRadii.br20,
                        boxShadow: AppShadows.sm,
                        border: Border.all(color: _ProfilePalette.line),
                      ),
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
                                  style: AppTypography.bodyMedium.copyWith(
                                    color: _ProfilePalette.ink,
                                  ),
                                ),
                                const SizedBox(height: AppSpacing.s4),
                                Text(
                                  idolName != null
                                      ? 'Comparing with $idolName'
                                      : 'Select an idol to compare',
                                  style: AppTypography.caption.copyWith(
                                    color: _ProfilePalette.muted,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const Icon(
                            Icons.chevron_right,
                            color: _ProfilePalette.muted,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: AppSpacing.s32),
              ],
            ),
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
    Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (context) => const SettingsScreen()));
  }
}

class _StatItem extends StatelessWidget {
  const _StatItem({required this.value, required this.label});

  final String value;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(
          value,
          style: AppTypography.h3.copyWith(color: _ProfilePalette.ink),
        ),
        Text(
          label,
          style: AppTypography.caption.copyWith(color: _ProfilePalette.muted),
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
      backgroundColor: _ProfilePalette.canvas,
      appBar: AppBar(
        backgroundColor: _ProfilePalette.canvas,
        surfaceTintColor: Colors.transparent,
        scrolledUnderElevation: 0,
        leading: IconButton(
          onPressed: () => Navigator.pop(context),
          icon: const Icon(Icons.arrow_back, color: _ProfilePalette.ink),
        ),
        title: Text(
          'Settings',
          style: AppTypography.h3.copyWith(color: _ProfilePalette.ink),
        ),
      ),
      body: DecoratedBox(
        decoration: const BoxDecoration(
          color: _ProfilePalette.canvas,
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              AppColors.surfaceHighlight,
              _ProfilePalette.canvas,
              AppColors.bg,
            ],
            stops: [0, 0.52, 1],
          ),
        ),
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: AppSpacing.s16),
              Text(
                'ACCOUNT',
                style: AppTypography.captionUpper.copyWith(
                  color: _ProfilePalette.coralDark,
                ),
              ),
              const SizedBox(height: AppSpacing.s12),
              _SettingsGroup(
                children: [
                  SettingsTile(
                    title: 'CMPYS Pro',
                    icon: AppAssets.iconSparkles,
                    subtitle: 'Blueprint, Mirror, Studio, Vault',
                    iconColor: AppColors.peach,
                    onTap: () => context.push(AppRoutes.premium),
                  ),
                  SettingsTile(
                    title: 'Edit Profile',
                    icon: AppAssets.iconUser,
                    onTap: () => _showProfileConsoleSheet(
                      context,
                      title: 'Edit profile',
                      message:
                          'Profile editing will use the same onboarding console so identity, interests, and age stay in sync.',
                    ),
                  ),
                  SettingsTile(
                    title: 'Change Idol',
                    icon: AppAssets.iconUsers,
                    onTap: () => context.push(AppRoutes.idolSuggest),
                  ),
                  SettingsTile(
                    title: 'Notifications',
                    icon: AppAssets.iconBell,
                    subtitle: ref
                        .watch(notificationSettingsProvider)
                        .maybeWhen(
                          data: (settings) => settings.enabled
                              ? 'Daily reminder at ${settings.timeString}'
                              : 'Off',
                          orElse: () => 'Daily focus reminder',
                        ),
                    onTap: () => _showNotificationSettingsSheet(context, ref),
                    showDivider: false,
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.s24),
              Text(
                'PREFERENCES',
                style: AppTypography.captionUpper.copyWith(
                  color: _ProfilePalette.coralDark,
                ),
              ),
              const SizedBox(height: AppSpacing.s12),
              _SettingsGroup(
                children: [
                  SettingsTile(
                    title: 'Appearance',
                    icon: AppAssets.iconEye,
                    subtitle: 'Light',
                    onTap: () => _showProfileConsoleSheet(
                      context,
                      title: 'Appearance',
                      message:
                          'The redesigned app is currently locked to the light paper system.',
                    ),
                  ),
                  SettingsTile(
                    title: 'Language',
                    icon: AppAssets.iconMessageCircle,
                    subtitle: 'English',
                    onTap: () => _showProfileConsoleSheet(
                      context,
                      title: 'Language',
                      message:
                          'English is active for this prototype. Localized mentor prompts can be added later.',
                    ),
                    showDivider: false,
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.s24),
              Text(
                'SUPPORT',
                style: AppTypography.captionUpper.copyWith(
                  color: _ProfilePalette.coralDark,
                ),
              ),
              const SizedBox(height: AppSpacing.s12),
              _SettingsGroup(
                children: [
                  SettingsTile(
                    title: 'Help Center',
                    icon: AppAssets.iconCircleHelp,
                    onTap: () => _showProfileConsoleSheet(
                      context,
                      title: 'Help center',
                      message:
                          'Support articles will live here with account, billing, and learning-resource guidance.',
                    ),
                  ),
                  SettingsTile(
                    title: 'Privacy Policy',
                    icon: AppAssets.iconFileText,
                    onTap: () => _showProfileConsoleSheet(
                      context,
                      title: 'Privacy policy',
                      message:
                          'Privacy policy content will be attached before production release.',
                    ),
                  ),
                  SettingsTile(
                    title: 'Terms of Service',
                    icon: AppAssets.iconFileText,
                    onTap: () => _showProfileConsoleSheet(
                      context,
                      title: 'Terms of service',
                      message:
                          'Terms content will be attached before production release.',
                    ),
                    showDivider: false,
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.s24),
              _SettingsGroup(
                children: [
                  SettingsTile(
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
                ],
              ),
              const SizedBox(height: AppSpacing.s32),
              Center(
                child: Text(
                  'CMPYS v1.0.0',
                  style: AppTypography.caption.copyWith(
                    color: _ProfilePalette.muted,
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

/// Settings card group.
class _SettingsGroup extends StatelessWidget {
  const _SettingsGroup({required this.children});
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: _ProfilePalette.paper,
        borderRadius: AppRadii.br20,
        boxShadow: AppShadows.sm,
        border: Border.all(color: _ProfilePalette.line),
      ),
      child: Column(children: children),
    );
  }
}
