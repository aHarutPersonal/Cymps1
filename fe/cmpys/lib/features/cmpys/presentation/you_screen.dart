import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/design_tokens.dart';
import '../../../app/router.dart';
import '../../../core/ui/app_shell.dart';
import '../../../core/ui/motion/motion_config.dart';
import '../../../core/ui/motion/page_transition.dart';
import '../../../core/ui/v3/v3.dart';
import '../../auth/controllers/auth_controller.dart';
import '../../auth/controllers/session_controller.dart';
import '../../plan/presentation/reading_library_screen.dart';
import '../../plan/state/current_plan_provider.dart';
import '../data/cmpys_seed.dart';
import '../state/cmpys_store.dart';
import '../state/plan_data.dart';
import '../state/today_data.dart';
import 'detail_screens.dart';
import 'onboarding/mentor_image.dart';
import 'record_screen.dart';

/// CMPYS You tab (`v3/you.jsx` YouTab): the profile header with the edit
/// sheet, three stat cards, the mentor portrait (opens Mentor context),
/// Library rows, the device-only Settings card and Log out.
///
/// The design's "Change" mentor action is left out: the store's mentor is
/// also the session identity, so switching it on the device orphans the plan
/// (the plan provider rejects it and its retry generates a new, paid plan).
///
/// Stats are real figures only: overall plan progress
/// ([planOverallProgress] over [currentPlanProvider]), the current streak
/// ([todayStreakProvider]; "—" while it loads or fails) and the wins on the
/// record ([CmpysStore]).
class CmpysYouScreen extends ConsumerWidget {
  const CmpysYouScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final st = ref.watch(
      cmpysStoreProvider.select(
        (s) => (
          idol: s.idol,
          user: s.user,
          notes: s.notes.length,
          saved: s.saved.length,
          wins: s.achievements.length,
        ),
      ),
    );
    final plan = ref.watch(currentPlanProvider.select((s) => s.plan));
    final streak = ref.watch(todayStreakProvider).valueOrNull?.current;
    final planPct = plan == null
        ? 0
        : (planOverallProgress(plan) * 100).round();
    final top = math.max(MediaQuery.paddingOf(context).top + 8, 20.0);

    return Scaffold(
      backgroundColor: AppColors.paper,
      body: ListView(
        padding: EdgeInsets.only(bottom: AppShell.bottomNavClearance(context)),
        children: [
          Padding(
            padding: EdgeInsets.fromLTRB(20, top, 20, 0),
            child: _header(context, st.user),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
            child: V3Rise(
              delay: const Duration(milliseconds: 120),
              child: _stats(planPct, streak, st.wins),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
            child: V3Rise(
              delay: const Duration(milliseconds: 160),
              child: _mentor(context, st.idol),
            ),
          ),
          V3Rise(
            delay: const Duration(milliseconds: 200),
            child: V3Section(
              title: 'Library',
              child: _library(context, st.notes, st.saved),
            ),
          ),
          const V3Rise(
            delay: Duration(milliseconds: 240),
            child: V3Section(title: 'Settings', child: _SettingsList()),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 18, 20, 0),
            child: V3Button(
              kind: V3ButtonKind.line,
              full: true,
              semanticLabel: 'Log out',
              onPressed: () => _confirmLogout(context, ref),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  V3Icon(V3Icons.logout, size: 18, color: AppColors.danger),
                  SizedBox(width: 8),
                  Flexible(
                    child: Text(
                      'Log out',
                      style: TextStyle(color: AppColors.danger),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _header(BuildContext context, CmpysUser user) {
    final name = user.name.trim().isEmpty ? 'Your name' : user.name.trim();
    final sub = [
      if (user.age > 0) '${user.age}',
      if (user.interests.isNotEmpty) user.interests.take(2).join(', '),
    ].join(' · ');
    return Row(
      children: [
        V3Pop(
          duration: const Duration(milliseconds: 600),
          child: Container(
            width: 76,
            height: 76,
            decoration: const BoxDecoration(
              color: AppColors.ink,
              shape: BoxShape.circle,
            ),
            alignment: Alignment.center,
            child: Text(
              name.characters.first.toUpperCase(),
              style: AppTypography.display(34).copyWith(color: Colors.white),
            ),
          ),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: V3Rise(
            delay: const Duration(milliseconds: 60),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: AppTypography.display(
                    36,
                  ).copyWith(color: AppColors.ink),
                ),
                if (sub.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(
                      sub,
                      style: AppTypography.sans(
                        13,
                      ).copyWith(color: AppColors.ink3),
                    ),
                  ),
              ],
            ),
          ),
        ),
        const SizedBox(width: 8),
        V3IconButton(
          icon: V3Icons.edit,
          label: 'Edit profile',
          onPressed: () => showCmpysEditProfileSheet(context),
        ),
      ],
    );
  }

  Widget _stats(int planPct, int? streak, int wins) {
    final stats = <({num? value, String label, String Function(double)? fmt})>[
      (value: planPct, label: 'plan complete', fmt: (v) => '${v.round()}%'),
      (value: streak, label: 'day streak', fmt: null),
      (value: wins, label: 'wins recorded', fmt: null),
    ];
    final numberStyle = AppTypography.display(
      32,
    ).merge(AppTypography.tnum).copyWith(color: AppColors.ink);
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var i = 0; i < stats.length; i++) ...[
            if (i > 0) const SizedBox(width: 8),
            Expanded(
              // One stop for screen readers: "35%, plan complete".
              child: MergeSemantics(
                child: Container(
                  padding: const EdgeInsets.fromLTRB(12, 14, 12, 14),
                  decoration: v3Card(),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: Alignment.centerLeft,
                        child: switch (stats[i].value) {
                          final value? => V3CountUp(
                            to: value,
                            delay: Duration(milliseconds: i * 100),
                            format: stats[i].fmt,
                            style: numberStyle,
                          ),
                          // Not known yet (loading or failed), as in v2.
                          null => Text('—', style: numberStyle),
                        },
                      ),
                      const SizedBox(height: 2),
                      Text(
                        stats[i].label,
                        style: AppTypography.sans(
                          11.5,
                        ).copyWith(color: AppColors.ink3),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _mentor(BuildContext context, CmpysIdol idol) {
    return V3Pressable(
      onTap: () => openIdolDetail(context, idol),
      focusRadius: AppRadii.brR,
      child: V3Portrait(
        image: cmpysIdolImage(idol),
        height: 150,
        radius: AppRadii.r,
        tone: idol.color,
        child: Positioned(
          left: 18,
          right: 18,
          bottom: 16,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Your mentor',
                style: AppTypography.sans(
                  12,
                  FontWeight.w600,
                ).copyWith(color: AppColors.nink3),
              ),
              Text(
                idol.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppTypography.display(30).copyWith(color: Colors.white),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _library(BuildContext context, int notes, int saved) {
    void push(Widget screen, {bool sheet = false}) =>
        Navigator.of(context).push(
          sheet
              ? CmpysSheetRoute<void>(builder: (_) => screen)
              : CmpysPageRoute<void>(builder: (_) => screen),
        );
    return ClipRRect(
      borderRadius: AppRadii.brR,
      child: DecoratedBox(
        decoration: v3Card(),
        child: Column(
          children: [
            _YouRow(
              first: true,
              icon: V3Icons.book,
              tone: AppColors.irisSoft,
              label: 'Reading',
              sub: 'Guides, originals, excerpts',
              onTap: () => push(const ReadingLibraryScreen()),
            ),
            _YouRow(
              icon: V3Icons.bulb,
              tone: AppColors.goldSoft,
              label: 'Idea reels',
              onTap: () => context.goToIdeas(),
            ),
            _YouRow(
              icon: V3Icons.trophy,
              tone: AppColors.emberSoft,
              label: 'Your record',
              onTap: () => push(const CmpysRecordScreen(), sheet: true),
            ),
            _YouRow(
              icon: V3Icons.note,
              label: 'Notes',
              sub: '$notes on this device',
              onTap: () => push(const CmpysNotesScreen()),
            ),
            _YouRow(
              icon: V3Icons.bookmark,
              label: 'Saved',
              sub: '$saved on this device',
              onTap: () => push(const CmpysSavedScreen()),
            ),
          ],
        ),
      ),
    );
  }

  /// The "Log out?" sheet. Confirming clears this account's CMPYS data on
  /// this device (so the next account never inherits it), signs out and
  /// returns to auth.
  Future<void> _confirmLogout(BuildContext context, WidgetRef ref) async {
    final confirmed = await showV3Sheet<bool>(
      context,
      title: 'Log out?',
      builder: (sheet) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            // The design says local items "stay on this device", but a
            // deliberate logout clears this account's (account isolation),
            // so the second sentence says so. Wins saved to the account come
            // back into the Record on the next sign-in; device-only wins and
            // notes don't, so the copy still names the whole record.
            'Your plan, practice and reading progress are saved to your '
            'account. Your record, notes and saved items on this device will '
            'be cleared.',
            style: AppTypography.sans(
              14.5,
            ).copyWith(color: AppColors.ink2, height: 1.5),
          ),
          const SizedBox(height: 18),
          _DangerButton(
            label: 'Log out',
            onTap: () => Navigator.of(sheet).pop(true),
          ),
          const SizedBox(height: 8),
          V3Button(
            kind: V3ButtonKind.ghost,
            full: true,
            onPressed: () => Navigator.of(sheet).pop(false),
            child: const Text('Stay signed in'),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;
    // Read everything up front: signing out can unmount this tab.
    final store = ref.read(cmpysStoreProvider.notifier);
    final auth = ref.read(authControllerProvider.notifier);
    final session = ref.read(sessionControllerProvider.notifier);
    final router = GoRouter.maybeOf(context);
    await store.reset();
    await auth.logout();
    await session.onLogout();
    router?.go(AppRoutes.auth);
  }
}

/// The sheet's "Log out": the design's full dark button on a danger fill
/// (V3Button has no colour override).
class _DangerButton extends StatelessWidget {
  const _DangerButton({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return V3Pressable(
      onTap: onTap,
      child: Container(
        height: V3Size.lg.height,
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 22),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: AppColors.danger,
          borderRadius: BorderRadius.circular(999),
        ),
        child: Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: AppTypography.sans(
            15.5,
            FontWeight.w600,
          ).copyWith(color: Colors.white, letterSpacing: -0.005 * 15.5),
        ),
      ),
    );
  }
}

/// The design's `Row`: a 34 pt tinted icon tile, a 15 pt label with an
/// optional 12 pt [sub] line, and a trailing chevron unless [right] is given.
/// Rows after the [first] get a hairline on top. Tappable when [onTap] is set.
class _YouRow extends StatelessWidget {
  const _YouRow({
    required this.icon,
    required this.label,
    this.sub,
    this.right,
    this.onTap,
    this.tone,
    this.first = false,
  });

  final V3Icons icon;
  final String label;
  final String? sub;

  /// Replaces the chevron (a toggle, say).
  final Widget? right;
  final VoidCallback? onTap;

  /// The icon tile's fill (paper2 by default).
  final Color? tone;
  final bool first;

  @override
  Widget build(BuildContext context) {
    final row = Container(
      constraints: const BoxConstraints(minHeight: 60),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
      decoration: BoxDecoration(
        border: first
            ? null
            : const Border(top: BorderSide(color: AppColors.hair)),
      ),
      child: Row(
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: tone ?? AppColors.paper2,
              borderRadius: BorderRadius.circular(11),
            ),
            alignment: Alignment.center,
            child: V3Icon(icon, size: 17, color: AppColors.ink),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: AppTypography.sans(
                    15,
                    FontWeight.w500,
                  ).copyWith(color: AppColors.ink),
                ),
                if (sub != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 1),
                    child: Text(
                      sub!,
                      style: AppTypography.sans(
                        12,
                      ).copyWith(color: AppColors.ink3),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 14),
          right ?? const V3Icon(V3Icons.right, size: 16, color: AppColors.ink3),
        ],
      ),
    );
    if (onTap == null) return row;
    return V3Pressable(
      onTap: onTap,
      pressedScale: 1,
      focusRadius: BorderRadius.zero,
      child: row,
    );
  }
}

/// The design's `Toggle`: a 50×30 switch, sage2 when [on] (hair2 off), its
/// knob sliding on the spring. It carries the toggled state and the tap
/// action but no label: [_toggleRow] merges it with the row's text, so the
/// setting is announced once.
class _Toggle extends StatelessWidget {
  const _Toggle({super.key, required this.on, required this.onTap});

  final bool on;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final motion = MotionConfig.enabled(context);
    return Semantics(
      toggled: on,
      child: V3Pressable(
        onTap: onTap,
        button: false,
        pressedScale: 1,
        child: AnimatedContainer(
          duration: motion ? const Duration(milliseconds: 300) : Duration.zero,
          width: 50,
          height: 30,
          decoration: BoxDecoration(
            color: on ? AppColors.sage2 : AppColors.hair2,
            borderRadius: BorderRadius.circular(99),
          ),
          child: AnimatedAlign(
            duration: motion
                ? const Duration(milliseconds: 350)
                : Duration.zero,
            curve: AppMotion.spring,
            alignment: on ? Alignment.centerRight : Alignment.centerLeft,
            child: Container(
              width: 24,
              height: 24,
              margin: const EdgeInsets.all(3),
              decoration: const BoxDecoration(
                color: Colors.white,
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: Color(0x33000000),
                    offset: Offset(0, 2),
                    blurRadius: 5,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// A settings row whose trailing [_Toggle] flips [setting]: one merged
/// semantics node ("Sound & haptics", toggled, tap toggles).
Widget _toggleRow({
  required String setting,
  required bool on,
  required VoidCallback onTap,
  required V3Icons icon,
  required String label,
  bool first = false,
}) => MergeSemantics(
  child: _YouRow(
    first: first,
    icon: icon,
    label: label,
    right: _Toggle(
      key: ValueKey<String>('you-toggle-$setting'),
      on: on,
      onTap: onTap,
    ),
  ),
);

/// The "Settings" card from the You tab: the one wired toggle, Sound &
/// haptics, kept on this device ([CmpysStore.toggleSetting]), "Privacy &
/// data" (coming soon, a toast) and "About CMPYS" (a toast). The toggles
/// that aren't wired yet (daily reminder, mentor messages, weekly digest)
/// are hidden until they work (owner decision 4).
class _SettingsList extends ConsumerWidget {
  const _SettingsList();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(cmpysStoreProvider.select((s) => s.settings));
    final store = ref.read(cmpysStoreProvider.notifier);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ClipRRect(
          borderRadius: AppRadii.brR,
          child: DecoratedBox(
            decoration: v3Card(),
            child: Column(
              children: [
                _toggleRow(
                  setting: 'haptics',
                  on: s.haptics,
                  onTap: () => store.toggleSetting('haptics'),
                  first: true,
                  icon: V3Icons.sparkle,
                  label: 'Sound & haptics',
                ),
                _YouRow(
                  icon: V3Icons.lock,
                  label: 'Privacy & data',
                  sub: 'Coming soon',
                  onTap: () => showV3Toast(
                    context,
                    'Privacy center is coming soon',
                    icon: V3Icons.info,
                    tone: V3ToastTone.warn,
                  ),
                ),
                _YouRow(
                  icon: V3Icons.info,
                  label: 'About CMPYS',
                  onTap: () => showV3Toast(
                    context,
                    'CMPYS 3.0 · build 2026.10',
                    icon: V3Icons.info,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
