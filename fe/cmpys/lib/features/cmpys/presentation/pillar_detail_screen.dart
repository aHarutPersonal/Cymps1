import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../../app/design_tokens.dart';
import '../../../core/ui/app_shell.dart';
import '../../../core/ui/cmpys/cmpys_primitives.dart';
import '../data/cmpys_seed.dart';
import '../state/cmpys_store.dart';
import 'detail_screens.dart';

/// CMPYS pillar detail — color-block header, why, daily rituals + one-time steps.
/// Reads/writes the shared store so completion is consistent with Plan & Today.
class PillarDetailScreen extends ConsumerWidget {
  const PillarDetailScreen({super.key, required this.pillar});
  final CmpysPillar pillar;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tasks = ref.watch(cmpysStoreProvider.select((s) => s.tasks));
    final once = pillar.items.where((it) => it.repeat == CmpysRepeat.once).toList();
    final daily =
        pillar.items.where((it) => it.repeat == CmpysRepeat.daily).toList();
    final weekly =
        pillar.items.where((it) => it.repeat == CmpysRepeat.weekly).toList();
    final done = once.where((it) => tasks[it.id] ?? false).length;
    final pct = once.isEmpty ? 0 : (done / once.length * 100).round();

    return Scaffold(
      backgroundColor: AppColors.paper,
      body: CustomScrollView(
        slivers: [
          SliverToBoxAdapter(child: _header(context, done, once.length, pct)),
          SliverPadding(
            padding: EdgeInsets.fromLTRB(18, 18, 18, AppShell.bottomNavClearance(context)),
            sliver: SliverList.list(
              children: [
                _whyCard(),
                if (daily.isNotEmpty) ...[
                  const SizedBox(height: 18),
                  _sectionHeader(PhosphorIconsRegular.arrowClockwise, 'Daily rituals',
                      daily.length),
                  const SizedBox(height: 10),
                  ...daily.map((it) => _itemTile(context, ref, it, tasks)),
                ],
                if (weekly.isNotEmpty) ...[
                  const SizedBox(height: 18),
                  _sectionHeader(
                      PhosphorIconsRegular.calendarBlank, 'Weekly rituals', weekly.length),
                  const SizedBox(height: 10),
                  ...weekly.map((it) => _itemTile(context, ref, it, tasks)),
                ],
                if (once.isNotEmpty) ...[
                  const SizedBox(height: 18),
                  _sectionHeader(null, 'Steps — once', once.length),
                  const SizedBox(height: 10),
                  ...once.map((it) => _itemTile(context, ref, it, tasks)),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _header(BuildContext context, int done, int total, int pct) {
    final top = MediaQuery.of(context).padding.top;
    return Container(
      padding: EdgeInsets.fromLTRB(20, top + 12, 20, 24),
      decoration: BoxDecoration(color: pillar.accent),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Material(
                color: Colors.transparent,
                child: InkWell(
                  onTap: () => Navigator.of(context).maybePop(),
                  borderRadius: BorderRadius.circular(999),
                  child: Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.18),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.chevron_left_rounded,
                        color: Colors.white, size: 22),
                  ),
                ),
              ),
              const Spacer(),
              Text(pillar.kicker.toUpperCase(),
                  style: AppTypography.kicker.copyWith(
                      color: Colors.white.withValues(alpha: 0.8))),
            ],
          ),
          const SizedBox(height: 20),
          Text(pillar.title,
              style: AppTypography.h1.copyWith(
                  color: Colors.white,
                  fontSize: 30,
                  height: 1.15,
                  letterSpacing: -0.5)),
          const SizedBox(height: 10),
          Text(pillar.why,
              style: AppTypography.body.copyWith(
                  color: Colors.white.withValues(alpha: 0.85),
                  fontSize: 14,
                  height: 1.5)),
          const SizedBox(height: 16),
          Row(
            children: [
              Text('$done of $total steps done',
                  style: AppTypography.caption.copyWith(
                      color: Colors.white.withValues(alpha: 0.9), fontSize: 12.5)),
              const Spacer(),
              Text('$pct%',
                  style: AppTypography.captionMedium.copyWith(
                      color: Colors.white, fontWeight: FontWeight.w700)),
            ],
          ),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: LinearProgressIndicator(
              value: pct / 100,
              minHeight: 7,
              backgroundColor: Colors.white.withValues(alpha: 0.25),
              valueColor: const AlwaysStoppedAnimation<Color>(Colors.white),
            ),
          ),
        ],
      ),
    );
  }

  Widget _whyCard() {
    return CmpysCardSurface(
      color: pillar.accent.withValues(alpha: 0.08),
      border: false,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CmpysKicker('Why this pillar', color: pillar.accent),
          const SizedBox(height: 8),
          Text(pillar.why,
              style: AppTypography.body
                  .copyWith(fontSize: 15, height: 1.55, color: AppColors.ink)),
        ],
      ),
    );
  }

  Widget _sectionHeader(IconData? icon, String label, int n) {
    return Row(
      children: [
        if (icon != null) ...[
          Icon(icon, size: 14, color: AppColors.ink3),
          const SizedBox(width: 6),
        ],
        Text(label, style: AppTypography.h3.copyWith(fontSize: 18)),
        const SizedBox(width: 8),
        Text('$n',
            style: AppTypography.captionMedium
                .copyWith(color: AppColors.ink3, fontWeight: FontWeight.w600)),
      ],
    );
  }

  Widget _itemTile(BuildContext context, WidgetRef ref, CmpysPlanItem it,
      Map<String, bool> tasks) {
    final done = tasks[it.id] ?? false;
    IconData icon;
    switch (it.kind) {
      case CmpysItemKind.read:
        icon = PhosphorIconsRegular.fileText;
        break;
      case CmpysItemKind.video:
        icon = PhosphorIconsFill.playCircle;
        break;
      case CmpysItemKind.book:
        icon = PhosphorIconsRegular.bookOpen;
        break;
      case CmpysItemKind.task:
        icon = PhosphorIconsRegular.target;
        break;
    }
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: CmpysCardSurface(
        pad: const EdgeInsets.fromLTRB(14, 12, 12, 12),
        onTap: () => openCmpysPlanItem(context, it, pillar: pillar),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: pillar.accent.withValues(alpha: 0.14),
                borderRadius: BorderRadius.circular(11),
              ),
              child: Icon(icon, size: 18, color: pillar.accent),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(it.title,
                      style: AppTypography.bodyMedium.copyWith(
                          fontSize: 15.5,
                          decoration: done ? TextDecoration.lineThrough : null,
                          color: done ? AppColors.ink3 : AppColors.ink)),
                  const SizedBox(height: 4),
                  Text('${it.minutes} min · ${it.tag ?? it.kind.name.toUpperCase()}',
                      style: AppTypography.caption
                          .copyWith(color: AppColors.ink3, fontSize: 12)),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: GestureDetector(
                onTap: () =>
                    ref.read(cmpysStoreProvider.notifier).toggleTask(it.id),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 220),
                  width: 28,
                  height: 28,
                  decoration: BoxDecoration(
                    color: done ? pillar.accent : Colors.transparent,
                    shape: BoxShape.circle,
                    border: Border.all(
                        color: done ? pillar.accent : AppColors.hair2, width: 2),
                  ),
                  child: done
                      ? const Icon(Icons.check_rounded,
                          size: 16, color: Colors.white)
                      : null,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
