import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../../app/design_tokens.dart';
import '../../../app/router.dart';
import '../../../core/ui/app_shell.dart';
import '../../../core/ui/cmpys/cmpys_primitives.dart';
import '../../../core/ui/motion/page_transition.dart';
import '../../auth/controllers/auth_controller.dart';
import '../../auth/controllers/session_controller.dart';
import '../data/cmpys_seed.dart';
import '../state/cmpys_store.dart';
import 'detail_screens.dart';
import 'idol_detail_screen.dart';
import 'record_screen.dart';

/// CMPYS You tab — profile, stats, library, account, logout.
class CmpysYouScreen extends ConsumerWidget {
  const CmpysYouScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final st = ref.watch(cmpysStoreProvider);
    final idol = st.idol;
    final name = st.user.name.isEmpty ? 'Your name' : st.user.name;
    final daily = cmpysPlan.pillars.expand((p) => p.items).toList();
    final doneCount = daily.where((it) => st.tasks[it.id] ?? false).length;
    final planPct = daily.isEmpty ? 0 : (doneCount / daily.length * 100).round();

    return Scaffold(
      backgroundColor: AppColors.paper,
      body: SafeArea(
        bottom: false,
        child: ListView(
          padding: EdgeInsets.fromLTRB(18, 14, 18, AppShell.bottomNavClearance(context)),
          children: [
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      CmpysKicker('Profile'),
                      const SizedBox(height: 4),
                      Text('You',
                          style: AppTypography.display.copyWith(
                              fontSize: 30, letterSpacing: -0.5, height: 1.1)),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: _circleAction(PhosphorIconsRegular.gearSix, () {
                    Navigator.of(context).push(CmpysPageRoute(
                        builder: (_) => const CmpysSettingsScreen()));
                  }),
                ),
              ],
            ),
            const SizedBox(height: 16),
            _profileCard(context, st, idol, name),
            const SizedBox(height: 18),
            Row(
              children: [
                Expanded(
                    child: _stat('${st.streak}', 'Day streak',
                        PhosphorIconsRegular.flame, AppColors.ochre)),
                const SizedBox(width: 10),
                Expanded(
                    child: _stat('$planPct%', 'Plan done',
                        PhosphorIconsRegular.target, AppColors.green)),
                const SizedBox(width: 10),
                Expanded(
                    child: _stat('${st.notes.length}', 'Notes',
                        PhosphorIconsRegular.note, AppColors.blue)),
              ],
            ),
            const SizedBox(height: 22),
            const Padding(
                padding: EdgeInsets.only(left: 2), child: CmpysKicker('Library')),
            const SizedBox(height: 10),
            CmpysCardSurface(
              pad: const EdgeInsets.symmetric(horizontal: 14),
              child: Column(
                children: [
                  _row(context, PhosphorIconsFill.sparkle, 'Your record',
                      '${st.achievements.length}',
                      () => Navigator.of(context).push(CmpysPageRoute(
                          builder: (_) => const CmpysRecordScreen())),
                      first: true),
                  _row(context, PhosphorIconsRegular.note, 'Notes',
                      '${st.notes.length}',
                      () => Navigator.of(context).push(CmpysPageRoute(
                          builder: (_) => const CmpysNotesScreen()))),
                  _row(context, PhosphorIconsRegular.bookmarkSimple, 'Saved',
                      '${st.saved.length}',
                      () => Navigator.of(context).push(CmpysPageRoute(
                          builder: (_) => const CmpysSavedScreen()))),
                  _row(context, PhosphorIconsRegular.quotes, 'Idea reels',
                      null, () => context.goToIdeas(),
                      last: true),
                ],
              ),
            ),
            const SizedBox(height: 18),
            const Padding(
                padding: EdgeInsets.only(left: 2), child: CmpysKicker('Account')),
            const SizedBox(height: 10),
            CmpysCardSurface(
              pad: const EdgeInsets.symmetric(horizontal: 14),
              child: Column(
                children: [
                  _row(context, PhosphorIconsRegular.user, 'Edit profile', null,
                      () => Navigator.of(context).push(CmpysPageRoute(
                          builder: (_) => const CmpysEditProfileScreen())),
                      first: true),
                  _row(context, PhosphorIconsRegular.scales, 'Change mentor',
                      null,
                      () => Navigator.of(context).push(CmpysPageRoute(
                          builder: (_) => const CmpysMentorPickerScreen()))),
                  _row(context, PhosphorIconsRegular.gearSix, 'Settings', null,
                      () => Navigator.of(context).push(CmpysPageRoute(
                          builder: (_) => const CmpysSettingsScreen())),
                      last: true),
                ],
              ),
            ),
            const SizedBox(height: 18),
            CmpysCardSurface(
              pad: const EdgeInsets.symmetric(horizontal: 14),
              child: _row(context, PhosphorIconsRegular.signOut, 'Log out', null,
                  () => _confirmLogout(context, ref),
                  first: true, last: true, danger: true),
            ),
            const SizedBox(height: 22),
            Center(
              child: Text('CMPYS · v1.0',
                  style: AppTypography.monoLabel
                      .copyWith(color: AppColors.ink3, fontSize: 10.5)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _circleAction(IconData icon, VoidCallback onTap) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(999),
        child: Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: AppColors.card,
            shape: BoxShape.circle,
            border: Border.all(color: AppColors.hair),
          ),
          child: Icon(icon, color: AppColors.ink2, size: 20),
        ),
      ),
    );
  }

  Widget _profileCard(
      BuildContext context, CmpysState st, CmpysIdol idol, String name) {
    final initial = st.user.name.isNotEmpty ? st.user.name[0].toUpperCase() : 'Y';
    return CmpysCardSurface(
      raised: true,
      pad: const EdgeInsets.fromLTRB(18, 24, 18, 22),
      child: Column(
        children: [
          CmpysMonogram(
            initials: initial,
            size: 84,
            color: AppColors.ochre2,
            tint: AppColors.ochreSoft,
          ),
          const SizedBox(height: 12),
          Text(name,
              style: AppTypography.display.copyWith(
                  fontSize: 24, fontWeight: FontWeight.w700, height: 1.1)),
          const SizedBox(height: 3),
          Text('Age ${st.user.age} · Day ${st.dayNum} on CMPYS',
              style: AppTypography.caption
                  .copyWith(color: AppColors.ink2, fontSize: 13.5)),
          const SizedBox(height: 14),
          GestureDetector(
            onTap: () => Navigator.of(context).push(CmpysPageRoute(
                builder: (_) => CmpysIdolDetailScreen(idol: idol))),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: idol.tint,
                borderRadius: BorderRadius.circular(999),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  CmpysMentorAvatar(
                    slug: idol.slug,
                    initials: idol.initials,
                    color: idol.color,
                    tint: Colors.white,
                    size: 20,
                  ),
                  const SizedBox(width: 7),
                  Text('Mentored by ${idol.short}',
                      style: AppTypography.captionMedium.copyWith(
                          color: idol.color, fontWeight: FontWeight.w700)),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _stat(String n, String label, IconData icon, Color color) {
    return Container(
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: AppRadii.card,
        border: Border.all(color: AppColors.hair),
      ),
      child: Column(
        children: [
          Icon(icon, size: 19, color: color),
          const SizedBox(height: 5),
          Text(n,
              style: AppTypography.display.copyWith(
                  fontSize: 24,
                  fontWeight: FontWeight.w700,
                  height: 1,
                  color: AppColors.ink)),
          const SizedBox(height: 3),
          Text(label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppTypography.caption
                  .copyWith(color: AppColors.ink3, fontSize: 11)),
        ],
      ),
    );
  }

  Widget _row(BuildContext context, IconData icon, String label, String? detail,
      VoidCallback onTap,
      {bool first = false, bool last = false, bool danger = false}) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        decoration: BoxDecoration(
          border: first
              ? null
              : const Border(top: BorderSide(color: AppColors.hair)),
        ),
        padding: const EdgeInsets.symmetric(vertical: 13),
        child: Row(
          children: [
            Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                color: danger ? AppColors.claySoft : AppColors.paper2,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon,
                  size: 18, color: danger ? AppColors.danger : AppColors.ink2),
            ),
            const SizedBox(width: 13),
            Expanded(
              child: Text(label,
                  style: AppTypography.bodyMedium.copyWith(
                      fontSize: 15.5,
                      color: danger ? AppColors.danger : AppColors.ink,
                      fontWeight:
                          danger ? FontWeight.w700 : FontWeight.w600)),
            ),
            if (detail != null) ...[
              Text(detail,
                  style: AppTypography.caption
                      .copyWith(color: AppColors.ink3, fontSize: 14)),
              const SizedBox(width: 6),
            ],
            if (!danger)
              const Icon(Icons.chevron_right_rounded,
                  size: 18, color: AppColors.hair2),
          ],
        ),
      ),
    );
  }

  Future<void> _confirmLogout(BuildContext context, WidgetRef ref) async {
    await showCmpysSheet(
      context,
      title: 'Log out of CMPYS?',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Container(
                width: 46,
                height: 46,
                decoration: BoxDecoration(
                  color: AppColors.claySoft,
                  borderRadius: BorderRadius.circular(13),
                ),
                child: const Icon(PhosphorIconsRegular.signOut,
                    color: AppColors.danger, size: 22),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  'Your progress is saved to this device. You can pick up right where you left off.',
                  style: AppTypography.body.copyWith(
                      color: AppColors.ink2, fontSize: 14, height: 1.45),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          CmpysButton(
            variant: CmpysBtnVariant.danger,
            full: true,
            onTap: () async {
              Navigator.of(context).pop();
              // Wipe local state so the next account never inherits this
              // user's mentor, achievements, notes, or saved items.
              await ref.read(cmpysStoreProvider.notifier).reset();
              await ref.read(authControllerProvider.notifier).logout();
              ref.read(sessionControllerProvider.notifier).onLogout();
              if (context.mounted) context.go(AppRoutes.auth);
            },
            child: const Text('Log out'),
          ),
          const SizedBox(height: 10),
          CmpysButton(
            variant: CmpysBtnVariant.ghost,
            full: true,
            onTap: () => Navigator.of(context).pop(),
            child: const Text('Stay logged in'),
          ),
        ],
      ),
    );
  }
}
