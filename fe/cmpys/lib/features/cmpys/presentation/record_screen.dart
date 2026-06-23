// CMPYS "Your Record" — dual timeline of your wins vs your mentor's ledger at
// the same ages, plus the log-a-win sheet, milestone claim sheet, and the AI
// reassessment overlay. Ported from record.jsx / record-sheets.jsx.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../../app/design_tokens.dart';
import '../../../core/ui/cmpys/cmpys_primitives.dart';
import '../data/cmpys_record_data.dart';
import '../data/cmpys_seed.dart';
import '../state/cmpys_store.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Record screen
// ─────────────────────────────────────────────────────────────────────────────

class CmpysRecordScreen extends ConsumerStatefulWidget {
  const CmpysRecordScreen({super.key});

  @override
  ConsumerState<CmpysRecordScreen> createState() => _CmpysRecordScreenState();
}

class _CmpysRecordScreenState extends ConsumerState<CmpysRecordScreen> {
  String _filter = 'all';

  @override
  Widget build(BuildContext context) {
    final st = ref.watch(cmpysStoreProvider);
    final idol = st.idol;
    final userAge = st.user.age;
    final pending = st.pendingWins().length;

    final ledger = (cmpysIdolLedgers[idol.id] ?? const [])
        .where((e) => e.age <= userAge)
        .toList();
    final wins = st.achievements
        .where((w) => _filter == 'all' || w.dim == _filter)
        .toList();

    // Unique sorted ages across your wins + (when unfiltered) idol ledger.
    final ageSet = <int>{
      ...wins.map((w) => w.age),
      if (_filter == 'all') ...ledger.map((e) => e.age),
    };
    final ages = ageSet.toList()..sort();

    final teaser = _filter == 'all'
        ? ledger.where((e) => e.age == userAge + 1).toList()
        : <LedgerEntry>[];

    return Scaffold(
      backgroundColor: AppColors.paper,
      floatingActionButton: _logWinFab(),
      body: SafeArea(
        bottom: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // header
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 8, 16, 4),
              child: Row(
                children: [
                  _circleBack(),
                  const Spacer(),
                  if (pending > 0)
                    GestureDetector(
                      onTap: _openReassess,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 13, vertical: 8),
                        decoration: BoxDecoration(
                          color: AppColors.blkInk,
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(PhosphorIconsRegular.arrowClockwise,
                                size: 14, color: Colors.white),
                            const SizedBox(width: 6),
                            Text('Reassess',
                                style: AppTypography.captionMedium.copyWith(
                                    color: Colors.white,
                                    fontWeight: FontWeight.w700,
                                    fontSize: 12.5)),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(22, 0, 22, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  CmpysKicker('You & ${idol.short}, age for age'),
                  const SizedBox(height: 4),
                  Text('Your record',
                      style: AppTypography.h1.copyWith(
                          fontSize: 30, letterSpacing: -0.4, height: 1.3)),
                ],
              ),
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(22, 0, 22, 110),
                children: [
                  if (pending > 0) _pendingBanner(idol, pending),
                  _filterChips(),
                  const SizedBox(height: 16),
                  if (ages.isEmpty)
                    _emptyState()
                  else
                    _timeline(ages, wins, ledger, userAge, idol, teaser),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _circleBack() => Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () => Navigator.of(context).maybePop(),
          borderRadius: BorderRadius.circular(999),
          child: Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: AppColors.card,
              shape: BoxShape.circle,
              border: Border.all(color: AppColors.hair),
            ),
            child: const Icon(Icons.chevron_left_rounded,
                size: 22, color: AppColors.ink),
          ),
        ),
      );

  Widget _logWinFab() {
    return Padding(
      padding: const EdgeInsets.only(bottom: 90),
      child: GestureDetector(
        onTap: _openAddWin,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
          decoration: BoxDecoration(
            color: AppColors.blkInk,
            borderRadius: BorderRadius.circular(999),
            boxShadow: const [
              BoxShadow(
                  color: Color(0x47000000), blurRadius: 24, offset: Offset(0, 10)),
            ],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.add_rounded, size: 20, color: Colors.white),
              const SizedBox(width: 6),
              Text('Log a win',
                  style: AppTypography.button.copyWith(fontSize: 15)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _pendingBanner(CmpysIdol idol, int pending) {
    return GestureDetector(
      onTap: _openReassess,
      child: Container(
        margin: const EdgeInsets.only(bottom: 14),
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
        decoration: BoxDecoration(
          color: AppColors.ochreSoft,
          borderRadius: AppRadii.card,
        ),
        child: Row(
          children: [
            const Icon(PhosphorIconsFill.sparkle,
                size: 20, color: AppColors.ochre2),
            const SizedBox(width: 11),
            Expanded(
              child: Text(
                '$pending new ${pending == 1 ? "entry" : "entries"} since ${idol.short}’s last assessment. Ask ${idol.short} to re-score your side.',
                style: AppTypography.captionMedium
                    .copyWith(color: AppColors.ochre2, fontSize: 13, height: 1.4),
              ),
            ),
            const SizedBox(width: 6),
            const Icon(Icons.chevron_right_rounded,
                size: 18, color: AppColors.ochre2),
          ],
        ),
      ),
    );
  }

  Widget _filterChips() {
    return SizedBox(
      height: 36,
      child: ListView(
        scrollDirection: Axis.horizontal,
        children: [
          _chip('All', _filter == 'all', AppColors.green, AppColors.greenSoft,
              () => setState(() => _filter = 'all')),
          for (final d in cmpysDims) ...[
            const SizedBox(width: 8),
            _chip(d.label, _filter == d.id, d.deep, d.tint,
                () => setState(() => _filter = d.id)),
          ],
        ],
      ),
    );
  }

  Widget _chip(String label, bool active, Color color, Color tint,
      VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 9),
        decoration: BoxDecoration(
          color: active ? tint : Colors.transparent,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(
              color: active ? color : AppColors.hair2, width: 1.5),
        ),
        child: Text(label,
            style: AppTypography.bodyMedium.copyWith(
                color: active ? color : AppColors.ink2,
                fontSize: 14,
                fontWeight: FontWeight.w500)),
      ),
    );
  }

  Widget _emptyState() {
    return CmpysCardSurface(
      pad: const EdgeInsets.all(22),
      child: Column(
        children: [
          const Icon(PhosphorIconsRegular.sparkle,
              size: 26, color: AppColors.ink3),
          const SizedBox(height: 12),
          Text('Nothing here yet', style: AppTypography.h3.copyWith(fontSize: 19)),
          const SizedBox(height: 6),
          Text(
            'Log a win in this area and it becomes part of your side of the comparison.',
            textAlign: TextAlign.center,
            style: AppTypography.bodyDim.copyWith(fontSize: 14),
          ),
        ],
      ),
    );
  }

  Widget _timeline(List<int> ages, List<CmpysWin> wins, List<LedgerEntry> ledger,
      int userAge, CmpysIdol idol, List<LedgerEntry> teaser) {
    return Padding(
      padding: const EdgeInsets.only(left: 30, top: 4),
      child: Stack(
        children: [
          // spine
          Positioned(
            left: -21,
            top: 6,
            bottom: 6,
            child: Container(width: 2, color: AppColors.hair2),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (final age in ages)
                _ageGroup(age, wins, ledger, userAge, idol),
              if (teaser.isNotEmpty) _teaser(teaser, userAge, idol),
            ],
          ),
        ],
      ),
    );
  }

  Widget _ageGroup(int age, List<CmpysWin> wins, List<LedgerEntry> ledger,
      int userAge, CmpysIdol idol) {
    final mine = wins.where((w) => w.age == age).toList();
    final his = _filter == 'all'
        ? ledger.where((e) => e.age == age).toList()
        : <LedgerEntry>[];
    final isNow = age == userAge;

    return Padding(
      padding: const EdgeInsets.only(bottom: 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // node + age label
          Stack(
            clipBehavior: Clip.none,
            children: [
              Positioned(
                left: -28,
                top: 2,
                child: Container(
                  width: 20,
                  height: 20,
                  decoration: BoxDecoration(
                    color: isNow ? AppColors.blkInk : AppColors.card,
                    shape: BoxShape.circle,
                    border: isNow
                        ? null
                        : Border.all(color: AppColors.hair2, width: 2),
                  ),
                  alignment: Alignment.center,
                  child: isNow
                      ? Container(
                          width: 7,
                          height: 7,
                          decoration: const BoxDecoration(
                              color: Colors.white, shape: BoxShape.circle),
                        )
                      : null,
                ),
              ),
              Row(
                children: [
                  Text('Age $age',
                      style: AppTypography.h3
                          .copyWith(fontSize: 17, letterSpacing: -0.2)),
                  if (isNow) ...[
                    const SizedBox(width: 8),
                    Text('NOW',
                        style: AppTypography.kicker
                            .copyWith(color: AppColors.ink3, fontSize: 10)),
                  ],
                ],
              ),
            ],
          ),
          const SizedBox(height: 10),
          for (final w in mine) ...[
            _WinCard(win: w),
            const SizedBox(height: 9),
          ],
          for (final e in his) ...[
            _idolRow('${idol.short} at $age: ${e.text}'),
            const SizedBox(height: 9),
          ],
        ],
      ),
    );
  }

  Widget _teaser(List<LedgerEntry> teaser, int userAge, CmpysIdol idol) {
    return Opacity(
      opacity: 0.55,
      child: Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Stack(
              clipBehavior: Clip.none,
              children: [
                Positioned(
                  left: -28,
                  top: 2,
                  child: Container(
                    width: 20,
                    height: 20,
                    decoration: BoxDecoration(
                      color: AppColors.paper,
                      shape: BoxShape.circle,
                      border: Border.all(
                          color: AppColors.hair2,
                          width: 2,
                          style: BorderStyle.solid),
                    ),
                  ),
                ),
                Row(
                  children: [
                    Text('Age ${userAge + 1}',
                        style: AppTypography.h3
                            .copyWith(fontSize: 17, letterSpacing: -0.2)),
                    const SizedBox(width: 8),
                    Flexible(
                      child: Text('WHERE ${idol.short.toUpperCase()} WENT NEXT',
                          style: AppTypography.kicker
                              .copyWith(color: AppColors.ink3, fontSize: 10),
                          overflow: TextOverflow.ellipsis),
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 10),
            for (final e in teaser) ...[
              _idolRow(e.text),
              const SizedBox(height: 9),
            ],
          ],
        ),
      ),
    );
  }

  Widget _idolRow(String text) {
    final idol = ref.read(cmpysStoreProvider).idol;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 11),
      decoration: BoxDecoration(
        color: AppColors.greenSoft,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CmpysMentorAvatar(
            slug: idol.slug,
            initials: idol.initials,
            color: idol.color,
            tint: Colors.white,
            size: 22,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(text,
                style: AppTypography.caption.copyWith(
                    color: AppColors.green2,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    height: 1.4)),
          ),
        ],
      ),
    );
  }

  void _openAddWin() {
    showCmpysSheet(
      context,
      title: 'Log a win',
      child: AddWinSheet(presetDim: _filter == 'all' ? null : _filter),
    );
  }

  void _openReassess() {
    Navigator.of(context).push(PageRouteBuilder(
      opaque: false,
      barrierColor: Colors.transparent,
      pageBuilder: (_, _, _) => const ReassessOverlay(),
    ));
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// WinCard (expandable)
// ─────────────────────────────────────────────────────────────────────────────

class _WinCard extends ConsumerStatefulWidget {
  const _WinCard({required this.win});
  final CmpysWin win;

  @override
  ConsumerState<_WinCard> createState() => _WinCardState();
}

class _WinCardState extends ConsumerState<_WinCard> {
  bool _open = false;

  @override
  Widget build(BuildContext context) {
    final w = widget.win;
    final d = dimOf(w.dim);
    final src = cmpysSourceMeta[w.source] ?? cmpysSourceMeta['manual']!;
    final impact = cmpysImpacts.firstWhere((i) => i.v == w.impact,
        orElse: () => cmpysImpacts[0]);

    return CmpysCardSurface(
      pad: const EdgeInsets.all(15),
      onTap: () => setState(() => _open = !_open),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // badges
          Wrap(
            spacing: 8,
            runSpacing: 6,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                decoration: BoxDecoration(
                    color: d.tint, borderRadius: BorderRadius.circular(999)),
                child: Text(d.label,
                    style: AppTypography.kicker.copyWith(
                        color: d.deep, fontSize: 10.5, letterSpacing: 0.6)),
              ),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(src.icon, size: 12, color: AppColors.ink3),
                  const SizedBox(width: 4),
                  Text(src.label,
                      style: AppTypography.caption
                          .copyWith(color: AppColors.ink3, fontSize: 11.5)),
                ],
              ),
              if (!w.assessed)
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
                  decoration: BoxDecoration(
                      color: AppColors.ochreSoft,
                      borderRadius: BorderRadius.circular(999)),
                  child: Text('Awaiting review',
                      style: AppTypography.kicker.copyWith(
                          color: AppColors.ochre2,
                          fontSize: 9.5,
                          letterSpacing: 0.4)),
                ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(w.title,
                    style: AppTypography.h4
                        .copyWith(fontSize: 15.5, height: 1.3)),
              ),
              const SizedBox(width: 10),
              _impactBars(w.impact, d.color),
            ],
          ),
          const SizedBox(height: 4),
          Text(impact.label,
              style: AppTypography.caption
                  .copyWith(color: AppColors.ink3, fontSize: 12)),
          if (_open) ...[
            const SizedBox(height: 12),
            Text(w.note,
                style: AppTypography.body
                    .copyWith(color: AppColors.ink2, fontSize: 13.5)),
            if (w.photo) ...[
              const SizedBox(height: 10),
              _evidencePlaceholder(),
            ],
            if (w.idolNote != null) ...[
              const SizedBox(height: 10),
              _idolNote(w.idolNote!),
            ],
            if (w.source == 'manual' || w.source == 'milestone' || w.source == 'chat') ...[
              const SizedBox(height: 10),
              GestureDetector(
                onTap: () {
                  ref.read(cmpysStoreProvider.notifier).deleteWin(w.id);
                  showCmpysToast(context, 'Entry removed',
                      icon: Icons.close_rounded, tone: AppColors.ink3);
                },
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.close_rounded, size: 13, color: AppColors.ink3),
                    const SizedBox(width: 5),
                    Text('Remove entry',
                        style: AppTypography.caption
                            .copyWith(color: AppColors.ink3, fontSize: 12.5)),
                  ],
                ),
              ),
            ],
          ],
        ],
      ),
    );
  }

  Widget _impactBars(int impact, Color color) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: List.generate(3, (i) {
        final n = i + 1;
        return Container(
          width: 5,
          height: 5 + n * 2.5,
          margin: EdgeInsets.only(right: i == 2 ? 0 : 3),
          decoration: BoxDecoration(
            color: n <= impact ? color : AppColors.hair2,
            borderRadius: BorderRadius.circular(2),
          ),
        );
      }),
    );
  }

  Widget _evidencePlaceholder() {
    return Container(
      height: 84,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFFEAE5D8), Color(0xFFE3DDCD)],
        ),
      ),
      alignment: Alignment.center,
      child: Text('EVIDENCE PHOTO',
          style: AppTypography.kicker.copyWith(color: const Color(0xFF8E876F), fontSize: 10)),
    );
  }

  Widget _idolNote(String note) {
    final idol = ref.read(cmpysStoreProvider).idol;
    return Container(
      padding: const EdgeInsets.fromLTRB(13, 11, 13, 11),
      decoration: BoxDecoration(
        color: AppColors.paper,
        borderRadius: BorderRadius.circular(13),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CmpysMentorAvatar(
            slug: idol.slug,
            initials: idol.initials,
            color: idol.color,
            tint: idol.tint,
            size: 24,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text('"$note"',
                style: AppTypography.readingQuote
                    .copyWith(fontSize: 13.5, height: 1.4)),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Add-win sheet
// ─────────────────────────────────────────────────────────────────────────────

class AddWinSheet extends ConsumerStatefulWidget {
  const AddWinSheet({super.key, this.presetDim});
  final String? presetDim;

  @override
  ConsumerState<AddWinSheet> createState() => _AddWinSheetState();
}

class _AddWinSheetState extends ConsumerState<AddWinSheet> {
  final _title = TextEditingController();
  final _note = TextEditingController();
  late String _dim;
  late int _age;
  int _impact = 2;
  bool _photo = false;

  @override
  void initState() {
    super.initState();
    _dim = widget.presetDim ?? 'knowledge';
    _age = ref.read(cmpysStoreProvider).user.age;
  }

  @override
  void dispose() {
    _title.dispose();
    _note.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final maxAge = ref.read(cmpysStoreProvider).user.age;
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _label('What did you do?'),
          _multiline(_title, 'Describe it in one line'),
          const SizedBox(height: 18),
          _label('Life area'),
          Wrap(
            spacing: 9,
            runSpacing: 9,
            children: cmpysDims.map((d) {
              final on = _dim == d.id;
              return GestureDetector(
                onTap: () => setState(() => _dim = d.id),
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                  decoration: BoxDecoration(
                    color: on ? d.tint : AppColors.card,
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(
                        color: on ? Colors.transparent : AppColors.hair2,
                        width: 1.5),
                  ),
                  child: Text(d.label,
                      style: AppTypography.bodyMedium.copyWith(
                          color: on ? d.deep : AppColors.ink2,
                          fontSize: 13,
                          fontWeight: FontWeight.w700)),
                ),
              );
            }).toList(),
          ),
          const SizedBox(height: 18),
          _label('When'),
          _agePicker(maxAge),
          const SizedBox(height: 18),
          _label('How big was it?'),
          Row(
            children: cmpysImpacts.map((im) {
              final on = _impact == im.v;
              return Expanded(
                child: Padding(
                  padding: EdgeInsets.only(right: im.v == 3 ? 0 : 8),
                  child: GestureDetector(
                    onTap: () => setState(() => _impact = im.v),
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      decoration: BoxDecoration(
                        color: on ? AppColors.greenSoft : AppColors.card,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                            color: on ? AppColors.green : AppColors.hair2,
                            width: 1.5),
                      ),
                      child: Column(
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: List.generate(3, (i) {
                              final n = i + 1;
                              return Container(
                                width: 5,
                                height: 5 + n * 2.5,
                                margin: EdgeInsets.only(right: i == 2 ? 0 : 3),
                                decoration: BoxDecoration(
                                  color: n <= im.v
                                      ? (on ? AppColors.green : AppColors.ink3)
                                      : AppColors.hair2,
                                  borderRadius: BorderRadius.circular(2),
                                ),
                              );
                            }),
                          ),
                          const SizedBox(height: 8),
                          Text(im.label,
                              textAlign: TextAlign.center,
                              style: AppTypography.caption.copyWith(
                                  color: on ? AppColors.green2 : AppColors.ink2,
                                  fontSize: 11.5,
                                  fontWeight: FontWeight.w600)),
                        ],
                      ),
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
          const SizedBox(height: 18),
          _label('The story (optional)'),
          _multiline(_note, 'What it took, why it matters…'),
          const SizedBox(height: 14),
          _EvidenceField(
            on: _photo,
            onToggle: (v) => setState(() => _photo = v),
          ),
          const SizedBox(height: 18),
          CmpysButton(
            variant: CmpysBtnVariant.primary,
            size: CmpysBtnSize.lg,
            full: true,
            disabled: _title.text.trim().isEmpty,
            onTap: _title.text.trim().isEmpty ? null : _save,
            child: const Text('Add to your record'),
          ),
        ],
      ),
    );
  }

  void _save() {
    ref.read(cmpysStoreProvider.notifier).addWin(
          title: _title.text.trim(),
          dim: _dim,
          age: _age,
          impact: _impact,
          note: _note.text.trim(),
          photo: _photo,
          source: 'manual',
        );
    Navigator.of(context).pop();
    showCmpysToast(context, 'Added to your record',
        icon: Icons.check_rounded, tone: AppColors.green);
  }

  Widget _label(String s) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Text(s, style: AppTypography.label.copyWith(fontSize: 14)),
      );

  Widget _multiline(TextEditingController c, String hint) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.paper,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.hair2, width: 1.5),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
      child: TextField(
        controller: c,
        minLines: 2,
        maxLines: 4,
        onChanged: (_) => setState(() {}),
        style: AppTypography.body.copyWith(fontSize: 15),
        cursorColor: AppColors.green,
        decoration: InputDecoration(
          hintText: hint,
          hintStyle: AppTypography.body
              .copyWith(color: AppColors.ink3, fontSize: 15),
          border: InputBorder.none,
          isDense: true,
        ),
      ),
    );
  }

  Widget _agePicker(int maxAge) {
    final isNow = _age >= maxAge;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
      decoration: BoxDecoration(
        color: AppColors.paper,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.hair2, width: 1.5),
      ),
      child: Row(
        children: [
          _stepBtn('−', () => setState(() => _age = _age > 10 ? _age - 1 : 10)),
          Expanded(
            child: Center(
              child: RichText(
                text: TextSpan(children: [
                  TextSpan(
                    text: isNow ? 'Now' : '$_age',
                    style: AppTypography.display
                        .copyWith(fontSize: 24, height: 1, color: AppColors.ink),
                  ),
                  if (!isNow)
                    TextSpan(
                      text: ' years old',
                      style: AppTypography.caption.copyWith(
                          color: AppColors.ink3, fontSize: 13),
                    ),
                ]),
              ),
            ),
          ),
          _stepBtn('+', () => setState(() => _age = _age < maxAge ? _age + 1 : maxAge)),
        ],
      ),
    );
  }

  Widget _stepBtn(String s, VoidCallback onTap) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Container(
          width: 34,
          height: 34,
          decoration: BoxDecoration(
              color: AppColors.paper2, borderRadius: BorderRadius.circular(10)),
          alignment: Alignment.center,
          child: Text(s,
              style: AppTypography.h2
                  .copyWith(fontSize: 20, fontWeight: FontWeight.w600)),
        ),
      ),
    );
  }
}

class _EvidenceField extends StatelessWidget {
  const _EvidenceField({required this.on, required this.onToggle});
  final bool on;
  final ValueChanged<bool> onToggle;

  @override
  Widget build(BuildContext context) {
    if (!on) {
      return GestureDetector(
        onTap: () => onToggle(true),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(vertical: 13),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
                color: AppColors.hair2, width: 1.5, style: BorderStyle.solid),
          ),
          alignment: Alignment.center,
          child: Text('+ Add a photo or proof (optional)',
              style:
                  AppTypography.caption.copyWith(color: AppColors.ink3, fontSize: 13.5)),
        ),
      );
    }
    return Stack(
      children: [
        Container(
          height: 92,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            gradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Color(0xFFEAE5D8), Color(0xFFE3DDCD)],
            ),
          ),
          alignment: Alignment.center,
          child: Text('EVIDENCE PHOTO',
              style: AppTypography.kicker
                  .copyWith(color: const Color(0xFF8E876F), fontSize: 10)),
        ),
        Positioned(
          top: 8,
          right: 8,
          child: GestureDetector(
            onTap: () => onToggle(false),
            child: Container(
              width: 28,
              height: 28,
              decoration: BoxDecoration(
                color: const Color(0xBF16161C),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.close_rounded, size: 16, color: Colors.white),
            ),
          ),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Milestone claim sheet (used by Compare)
// ─────────────────────────────────────────────────────────────────────────────

class ClaimSheet extends ConsumerStatefulWidget {
  const ClaimSheet({super.key, required this.milestoneId, required this.label});
  final String milestoneId;
  final String label;

  @override
  ConsumerState<ClaimSheet> createState() => _ClaimSheetState();
}

class _ClaimSheetState extends ConsumerState<ClaimSheet> {
  final _note = TextEditingController();
  late int _age;
  bool _photo = false;

  @override
  void initState() {
    super.initState();
    _age = ref.read(cmpysStoreProvider).user.age;
  }

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final dim = dimOf(cmpysMilestoneDim[widget.milestoneId] ?? 'clarity');
    final maxAge = ref.read(cmpysStoreProvider).user.age;
    final idolShort = ref.read(cmpysStoreProvider).idol.short;
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(14),
            decoration:
                BoxDecoration(color: dim.tint, borderRadius: BorderRadius.circular(16)),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(PhosphorIconsRegular.target, size: 20, color: dim.deep),
                const SizedBox(width: 11),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(widget.label,
                          style: AppTypography.bodyMedium.copyWith(
                              color: dim.deep,
                              fontSize: 14.5,
                              fontWeight: FontWeight.w700)),
                      const SizedBox(height: 2),
                      Text(
                          '$idolShort hit this by ${cmpysComparison.age} · counts toward ${dim.label}',
                          style: AppTypography.caption.copyWith(
                              color: dim.deep.withValues(alpha: 0.75),
                              fontSize: 12)),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 18),
          Text('When did you do it?', style: AppTypography.label.copyWith(fontSize: 14)),
          const SizedBox(height: 8),
          _agePicker(maxAge),
          const SizedBox(height: 18),
          Text('How did it happen?', style: AppTypography.label.copyWith(fontSize: 14)),
          const SizedBox(height: 8),
          Container(
            decoration: BoxDecoration(
              color: AppColors.paper,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: AppColors.hair2, width: 1.5),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
            child: TextField(
              controller: _note,
              minLines: 2,
              maxLines: 4,
              onChanged: (_) => setState(() {}),
              style: AppTypography.body.copyWith(fontSize: 15),
              cursorColor: AppColors.green,
              decoration: InputDecoration(
                hintText: 'A sentence is enough — this is your evidence.',
                hintStyle: AppTypography.body
                    .copyWith(color: AppColors.ink3, fontSize: 15),
                border: InputBorder.none,
                isDense: true,
              ),
            ),
          ),
          const SizedBox(height: 14),
          _EvidenceField(on: _photo, onToggle: (v) => setState(() => _photo = v)),
          const SizedBox(height: 18),
          CmpysButton(
            variant: CmpysBtnVariant.primary,
            size: CmpysBtnSize.lg,
            full: true,
            disabled: _note.text.trim().isEmpty,
            onTap: _note.text.trim().isEmpty ? null : _claim,
            child: Text('Claim it — $idolShort will take note'),
          ),
        ],
      ),
    );
  }

  void _claim() {
    ref.read(cmpysStoreProvider.notifier).claimMilestone(
          widget.milestoneId,
          widget.label,
          age: _age,
          note: _note.text.trim(),
          photo: _photo,
        );
    Navigator.of(context).pop();
    showCmpysToast(context, 'Milestone claimed',
        icon: Icons.check_rounded, tone: AppColors.green);
  }

  Widget _agePicker(int maxAge) {
    final isNow = _age >= maxAge;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
      decoration: BoxDecoration(
        color: AppColors.paper,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.hair2, width: 1.5),
      ),
      child: Row(
        children: [
          _stepBtn('−', () => setState(() => _age = _age > 10 ? _age - 1 : 10)),
          Expanded(
            child: Center(
              child: Text(isNow ? 'Now' : '$_age years old',
                  style: AppTypography.display
                      .copyWith(fontSize: 22, height: 1, color: AppColors.ink)),
            ),
          ),
          _stepBtn('+', () => setState(() => _age = _age < maxAge ? _age + 1 : maxAge)),
        ],
      ),
    );
  }

  Widget _stepBtn(String s, VoidCallback onTap) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Container(
          width: 34,
          height: 34,
          decoration: BoxDecoration(
              color: AppColors.paper2, borderRadius: BorderRadius.circular(10)),
          alignment: Alignment.center,
          child: Text(s,
              style: AppTypography.h2
                  .copyWith(fontSize: 20, fontWeight: FontWeight.w600)),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Reassess overlay
// ─────────────────────────────────────────────────────────────────────────────

class ReassessOverlay extends ConsumerStatefulWidget {
  const ReassessOverlay({super.key});

  @override
  ConsumerState<ReassessOverlay> createState() => _ReassessOverlayState();
}

class _ReassessOverlayState extends ConsumerState<ReassessOverlay> {
  String _phase = 'think';
  late Map<String, int> _deltas;
  late Map<String, int> _beforeShift;

  @override
  void initState() {
    super.initState();
    final st = ref.read(cmpysStoreProvider);
    _deltas = st.assessDeltas();
    _beforeShift = Map<String, int>.from(st.dimShift);
  }

  List<String> get _lines {
    final pendingCount = ref.read(cmpysStoreProvider).pendingWins().length;
    return [
      'Reading your ${pendingCount == 1 ? "new entry" : "$pendingCount new entries"}, one by one…',
      'Weighing each against where I stood at your age…',
      'Some of these move the needle. Updating your indexes…',
    ];
  }

  @override
  Widget build(BuildContext context) {
    final idol = ref.read(cmpysStoreProvider).idol;
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Container(
        decoration: const BoxDecoration(gradient: AppColors.gradInk),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(28),
            child: _phase == 'think'
                ? _thinkPhase(idol)
                : _resultPhase(idol),
          ),
        ),
      ),
    );
  }

  Widget _thinkPhase(CmpysIdol idol) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        CmpysMentorAvatar(
          slug: idol.slug,
          initials: idol.initials,
          color: idol.color,
          tint: idol.tint,
          size: 64,
        ),
        const SizedBox(height: 26),
        Text('REASSESSING YOUR RECORD',
            style: AppTypography.kicker
                .copyWith(color: Colors.white.withValues(alpha: 0.5))),
        const SizedBox(height: 18),
        Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.06),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: Colors.white.withValues(alpha: 0.09)),
          ),
          child: CmpysThinkFeed(
            lines: _lines,
            intervalMs: 950,
            accent: AppColors.green,
            onDone: () {
              if (!mounted) return;
              Future.delayed(const Duration(milliseconds: 700), () {
                if (!mounted) return;
                ref.read(cmpysStoreProvider.notifier).reassess(_deltas);
                setState(() => _phase = 'result');
              });
            },
          ),
        ),
      ],
    );
  }

  Widget _resultPhase(CmpysIdol idol) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        CmpysMentorAvatar(
          slug: idol.slug,
          initials: idol.initials,
          color: idol.color,
          tint: idol.tint,
          size: 64,
        ),
        const SizedBox(height: 22),
        Text('The record moved the needle.',
            textAlign: TextAlign.center,
            style: AppTypography.h2.copyWith(
                color: Colors.white, fontSize: 22, fontWeight: FontWeight.w700)),
        const SizedBox(height: 18),
        for (final entry in _deltas.entries) _deltaRow(entry.key, entry.value),
        const SizedBox(height: 16),
        Text(
          '"Progress you can write down is progress you can trust. Keep the entries coming."',
          textAlign: TextAlign.center,
          style: AppTypography.body.copyWith(
              color: Colors.white.withValues(alpha: 0.65), fontSize: 14),
        ),
        const SizedBox(height: 20),
        CmpysButton(
          variant: CmpysBtnVariant.primary,
          size: CmpysBtnSize.lg,
          full: true,
          onTap: () => Navigator.of(context).maybePop(),
          child: const Text('See the new picture'),
        ),
      ],
    );
  }

  Widget _deltaRow(String dimId, int delta) {
    final base = cmpysComparison.dimensions.firstWhere((d) => d.id == dimId);
    final before = (base.you + (_beforeShift[dimId] ?? 0)).clamp(0, 100);
    final after = (before + delta).clamp(0, 100);
    final meta = dimOf(dimId);
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          Container(
            width: 10,
            height: 10,
            decoration: BoxDecoration(
                color: meta.color, borderRadius: BorderRadius.circular(3)),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(meta.label,
                style: AppTypography.bodyMedium.copyWith(
                    color: Colors.white, fontSize: 14.5)),
          ),
          Text('$before',
              style: AppTypography.monoLabel.copyWith(
                  color: Colors.white.withValues(alpha: 0.55), fontSize: 13)),
          const SizedBox(width: 8),
          Icon(Icons.arrow_forward_rounded,
              size: 14, color: Colors.white.withValues(alpha: 0.4)),
          const SizedBox(width: 8),
          Text('$after',
              style: AppTypography.monoLabel.copyWith(
                  color: AppColors.green,
                  fontSize: 13,
                  fontWeight: FontWeight.w700)),
        ],
      ),
    );
  }
}
