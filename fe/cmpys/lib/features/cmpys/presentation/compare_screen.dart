import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../../app/design_tokens.dart';
import '../../../app/router.dart';
import '../../../core/ui/app_shell.dart';
import '../../../core/ui/cmpys/cmpys_markdown.dart';
import '../../../core/ui/cmpys/cmpys_primitives.dart';
import '../data/cmpys_seed.dart';
import '../state/cmpys_store.dart';
import 'record_screen.dart';

typedef LiveDim = ({String id, String label, int you, int idol, String youNote, String idolNote});

/// CMPYS Compare tab — head-to-head gauge, verdict, record entry, radar,
/// expandable dimensions, milestones (claimable), strengths.
class CmpysCompareScreen extends ConsumerStatefulWidget {
  const CmpysCompareScreen({super.key});

  @override
  ConsumerState<CmpysCompareScreen> createState() => _CmpysCompareScreenState();
}

class _CmpysCompareScreenState extends ConsumerState<CmpysCompareScreen> {
  String? _open; // expanded dimension id

  static const _dimShort = {
    'capital': 'Capital',
    'knowledge': 'Knowledge',
    'habits': 'Discipline',
    'network': 'Network',
    'clarity': 'Clarity',
  };

  @override
  Widget build(BuildContext context) {
    final st = ref.watch(cmpysStoreProvider);
    final idol = st.idol;
    final c = cmpysComparison;
    final dims = st.liveDims();
    final ms = st.liveMilestones();
    final cmpAge = st.user.age > 0 ? st.user.age : c.age;
    final youAvg = (dims.map((d) => d.you).reduce((a, b) => a + b) / dims.length).round();
    final idolAvg = (dims.map((d) => d.idol).reduce((a, b) => a + b) / dims.length).round();
    final overall = (youAvg / idolAvg * 100).round();
    final hitCount = ms.where((m) => st.milestones[m.id] ?? false).length;
    final pending = st.pendingWins().length;
    final initial = st.user.name.isNotEmpty ? st.user.name[0].toUpperCase() : 'Y';

    return Scaffold(
      backgroundColor: AppColors.paper,
      body: SafeArea(
        bottom: false,
        child: ListView(
          padding: EdgeInsets.fromLTRB(18, 14, 18, AppShell.bottomNavClearance(context)),
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                CmpysKicker('Both at age $cmpAge'),
                const SizedBox(height: 4),
                Text('You vs ${idol.short}',
                    style: AppTypography.display.copyWith(
                        fontSize: 30, letterSpacing: -0.5, height: 1.1)),
              ],
            ),
            const SizedBox(height: 16),
            _gaugeHero(st, idol, youAvg, idolAvg, overall, initial),
            const SizedBox(height: 14),
            _aiVerdictCard(st, idol),
            const SizedBox(height: 14),
            _recordEntry(st, idol, pending),
            const SizedBox(height: 18),
            _radarCard(idol, dims),
            const SizedBox(height: 16),
            _dimensionRows(dims),
            const SizedBox(height: 22),
            _milestonesSection(st, idol, ms, hitCount, cmpAge),
            const SizedBox(height: 22),
            const Padding(
                padding: EdgeInsets.only(left: 2),
                child: CmpysKicker('Where you’re already ahead')),
            const SizedBox(height: 10),
            ...c.strengths.map(_strengthCard),
            const SizedBox(height: 18),
            CmpysButton(
              variant: CmpysBtnVariant.primary,
              size: CmpysBtnSize.lg,
              full: true,
              leadingIcon: PhosphorIconsBold.signpost,
              onTap: () => context.go(AppRoutes.plan),
              child: const Text('Work the plan to close the gap'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _gaugeHero(CmpysState st, CmpysIdol idol, int youAvg, int idolAvg,
      int overall, String initial) {
    return CmpysCardSurface(
      raised: true,
      pad: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
      child: Row(
        children: [
          _gaugeSide(
            CmpysMonogram(
                initials: initial,
                size: 56,
                color: AppColors.ochre2,
                tint: AppColors.ochreSoft),
            'You, now',
            'INDEX $youAvg',
          ),
          Expanded(
            child: CmpysRing(
              value: overall.toDouble().clamp(0, 100),
              size: 92,
              stroke: 8,
              color: AppColors.ochre,
              track: AppColors.hair,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text('$overall%',
                      style: AppTypography.display.copyWith(
                          fontSize: 24, fontWeight: FontWeight.w800, height: 1)),
                  Text('of ${idol.short}',
                      style: AppTypography.caption.copyWith(
                          color: AppColors.ink3, fontSize: 10.5)),
                ],
              ),
            ),
          ),
          _gaugeSide(
            CmpysMentorAvatar(
                slug: idol.slug,
                initials: idol.initials,
                color: idol.color,
                tint: idol.tint,
                size: 56),
            idol.short,
            'INDEX $idolAvg',
          ),
        ],
      ),
    );
  }

  Widget _gaugeSide(Widget avatar, String label, String index) {
    return SizedBox(
      width: 84,
      child: Column(
        children: [
          avatar,
          const SizedBox(height: 8),
          Text(label,
              textAlign: TextAlign.center,
              style: AppTypography.captionMedium
                  .copyWith(fontSize: 12.5, fontWeight: FontWeight.w700)),
          Text(index,
              style: AppTypography.monoLabel
                  .copyWith(color: AppColors.ink3, fontSize: 10)),
        ],
      ),
    );
  }

  /// The mentor's verdict — the LLM-generated comparison from onboarding.
  /// Shows a preview with "Read the full verdict"; no canned copy exists.
  Widget _aiVerdictCard(CmpysState st, CmpysIdol idol) {
    final md = st.comparisonMd;
    if (md == null || md.trim().isEmpty) {
      return Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
            gradient: AppColors.gradInk, borderRadius: AppRadii.card),
        child: Row(
          children: [
            const Icon(Icons.auto_awesome_rounded,
                size: 20, color: Color(0xFFFFD166)),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                'Your verdict from ${idol.short} hasn’t been generated yet — finish the onboarding interview to get it.',
                style: AppTypography.caption.copyWith(
                    color: Colors.white.withValues(alpha: 0.85),
                    fontSize: 13.5,
                    height: 1.5),
              ),
            ),
          ],
        ),
      );
    }
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
          gradient: AppColors.gradInk, borderRadius: AppRadii.card),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.auto_awesome_rounded,
                  size: 14, color: Color(0xFFFFD166)),
              const SizedBox(width: 6),
              Text('${idol.short.toUpperCase()}’S VERDICT',
                  style: AppTypography.kicker.copyWith(
                      color: Colors.white.withValues(alpha: 0.6))),
            ],
          ),
          const SizedBox(height: 12),
          ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 180),
            child: ClipRect(
              child: ShaderMask(
                shaderCallback: (rect) => const LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Colors.white, Colors.white, Colors.transparent],
                  stops: [0.0, 0.72, 1.0],
                ).createShader(rect),
                blendMode: BlendMode.dstIn,
                child: CmpysMarkdown(md, onDark: true),
              ),
            ),
          ),
          const SizedBox(height: 10),
          GestureDetector(
            onTap: () => Navigator.of(context).push(MaterialPageRoute(
              builder: (_) => CmpysMarkdownScreen(
                kicker: 'From ${idol.short}',
                title: 'The verdict',
                markdown: md,
              ),
            )),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('Read the full verdict',
                    style: AppTypography.bodyMedium.copyWith(
                        color: const Color(0xFFFFD166),
                        fontWeight: FontWeight.w700,
                        fontSize: 14)),
                const SizedBox(width: 4),
                const Icon(Icons.arrow_forward_rounded,
                    size: 16, color: Color(0xFFFFD166)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _recordEntry(CmpysState st, CmpysIdol idol, int pending) {
    return CmpysCardSurface(
      raised: true,
      pad: EdgeInsets.zero,
      child: Column(
        children: [
          GestureDetector(
            onTap: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const CmpysRecordScreen())),
            behavior: HitTestBehavior.opaque,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                        color: AppColors.ochreSoft,
                        borderRadius: BorderRadius.circular(13)),
                    child: const Icon(PhosphorIconsFill.sparkle,
                        size: 20, color: AppColors.ochre2),
                  ),
                  const SizedBox(width: 13),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Your record',
                            style: AppTypography.h4.copyWith(fontSize: 15.5)),
                        const SizedBox(height: 2),
                        Text(
                            '${st.achievements.length} entries · your side of this story',
                            style: AppTypography.caption.copyWith(
                                color: AppColors.ink3, fontSize: 12.5)),
                      ],
                    ),
                  ),
                  if (pending > 0)
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 9, vertical: 4),
                      decoration: BoxDecoration(
                          color: AppColors.ochreSoft,
                          borderRadius: BorderRadius.circular(999)),
                      child: Text('$pending new',
                          style: AppTypography.kicker.copyWith(
                              color: AppColors.ochre2, fontSize: 9.5)),
                    ),
                  const SizedBox(width: 6),
                  const Icon(Icons.chevron_right_rounded,
                      size: 18, color: AppColors.hair2),
                ],
              ),
            ),
          ),
          if (pending > 0)
            GestureDetector(
              onTap: _openReassess,
              behavior: HitTestBehavior.opaque,
              child: Container(
                decoration: const BoxDecoration(
                  color: AppColors.paper,
                  border: Border(top: BorderSide(color: AppColors.hair)),
                  borderRadius:
                      BorderRadius.vertical(bottom: Radius.circular(26)),
                ),
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
                child: Row(
                  children: [
                    const Icon(PhosphorIconsRegular.arrowClockwise,
                        size: 15, color: AppColors.green2),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text('Ask ${idol.short} to reassess your indexes',
                          style: AppTypography.captionMedium.copyWith(
                              color: AppColors.green2,
                              fontWeight: FontWeight.w700,
                              fontSize: 13)),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _radarCard(CmpysIdol idol, List<LiveDim> dims) {
    return CmpysCardSurface(
      child: Column(
        children: [
          Row(
            children: [
              CmpysKicker('The shape of the gap'),
              const Spacer(),
              _legendDot(AppColors.ochre, 'You'),
              const SizedBox(width: 14),
              _legendDot(AppColors.green, idol.short),
            ],
          ),
          const SizedBox(height: 4),
          SizedBox(
            height: 270,
            child: CustomPaint(
              size: const Size.fromHeight(270),
              painter: _RadarPainter(
                  dims: dims
                      .map((d) =>
                          (label: _dimShort[d.id] ?? d.label, you: d.you, idol: d.idol))
                      .toList()),
            ),
          ),
          Text('Tap a dimension below for the story behind it',
              style: AppTypography.caption
                  .copyWith(color: AppColors.ink3, fontSize: 12)),
        ],
      ),
    );
  }

  Widget _legendDot(Color c, String label) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
            width: 10,
            height: 10,
            decoration:
                BoxDecoration(color: c, borderRadius: BorderRadius.circular(3))),
        const SizedBox(width: 6),
        Text(label,
            style: AppTypography.captionMedium.copyWith(fontSize: 12.5)),
      ],
    );
  }

  Widget _dimensionRows(List<LiveDim> dims) {
    return CmpysCardSurface(
      pad: const EdgeInsets.all(6),
      child: Column(
        children: [
          for (var i = 0; i < dims.length; i++) _dimRow(dims[i], first: i == 0),
        ],
      ),
    );
  }

  Widget _dimRow(LiveDim d, {required bool first}) {
    final open = _open == d.id;
    final gap = d.idol - d.you;
    return Container(
      decoration: BoxDecoration(
        border: first
            ? null
            : const Border(top: BorderSide(color: AppColors.hair)),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            GestureDetector(
              onTap: () => setState(() => _open = open ? null : d.id),
              behavior: HitTestBehavior.opaque,
              child: Column(
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(d.label,
                            style: AppTypography.h4.copyWith(fontSize: 15),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 9, vertical: 3),
                        decoration: BoxDecoration(
                            color: AppColors.claySoft,
                            borderRadius: BorderRadius.circular(999)),
                        child: Text('−$gap',
                            style: AppTypography.kicker.copyWith(
                                color: AppColors.clay, fontSize: 10.5)),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  _barWithVal(d.you, AppColors.ochre, AppColors.ochre2),
                  const SizedBox(height: 6),
                  _barWithVal(d.idol, AppColors.green, AppColors.green2),
                ],
              ),
            ),
            if (open) ...[
              const SizedBox(height: 12),
              _noteLine(AppColors.ochre, d.youNote),
              const SizedBox(height: 8),
              _noteLine(AppColors.green, d.idolNote),
            ],
          ],
        ),
      ),
    );
  }

  Widget _barWithVal(int value, Color color, Color valueColor) {
    return Row(
      children: [
        Expanded(child: CmpysBar(value: value.toDouble(), color: color, height: 9)),
        const SizedBox(width: 9),
        SizedBox(
          width: 24,
          child: Text('$value',
              textAlign: TextAlign.right,
              style: AppTypography.monoLabel
                  .copyWith(color: valueColor, fontSize: 11)),
        ),
      ],
    );
  }

  Widget _noteLine(Color dot, String text) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 4, right: 9),
          child: Container(
              width: 9,
              height: 9,
              decoration: BoxDecoration(
                  color: dot, borderRadius: BorderRadius.circular(3))),
        ),
        Expanded(
          child: Text(text,
              style: AppTypography.caption
                  .copyWith(color: AppColors.ink2, fontSize: 13, height: 1.45)),
        ),
      ],
    );
  }

  Widget _milestonesSection(
      CmpysState st, CmpysIdol idol, List<CmpysMilestone> ms, int hitCount, int cmpAge) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 2),
          child: Row(
            children: [
              CmpysKicker('Milestones ${idol.short} hit by $cmpAge'),
              const Spacer(),
              Text('$hitCount/${ms.length}',
                  style: AppTypography.captionMedium.copyWith(
                      color: AppColors.green, fontWeight: FontWeight.w700)),
            ],
          ),
        ),
        const SizedBox(height: 10),
        CmpysCardSurface(
          pad: const EdgeInsets.all(6),
          child: Column(
            children: [
              for (var i = 0; i < ms.length; i++)
                _milestoneRow(st, ms[i], first: i == 0),
            ],
          ),
        ),
      ],
    );
  }

  Widget _milestoneRow(CmpysState st, CmpysMilestone m, {required bool first}) {
    final hit = st.milestones[m.id] ?? false;
    return Container(
      decoration: BoxDecoration(
        border: first
            ? null
            : const Border(top: BorderSide(color: AppColors.hair)),
      ),
      child: GestureDetector(
        onTap: () {
          if (hit) {
            ref.read(cmpysStoreProvider.notifier).toggleMilestone(m.id);
          } else {
            showCmpysSheet(context,
                title: 'Claim this milestone',
                child: ClaimSheet(milestoneId: m.id, label: m.label));
          }
        },
        behavior: HitTestBehavior.opaque,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 13),
          child: Row(
            children: [
              AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                width: 25,
                height: 25,
                decoration: BoxDecoration(
                  color: hit ? AppColors.green : Colors.transparent,
                  shape: BoxShape.circle,
                  border: Border.all(
                      color: hit ? AppColors.green : AppColors.hair2, width: 2),
                ),
                child: hit
                    ? const Icon(Icons.check_rounded, size: 14, color: Colors.white)
                    : null,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(m.label,
                    style: AppTypography.bodyMedium.copyWith(
                        fontSize: 14.5,
                        color: hit ? AppColors.ink3 : AppColors.ink,
                        decoration: hit ? TextDecoration.lineThrough : null)),
              ),
              if (!hit)
                const Icon(Icons.chevron_right_rounded,
                    size: 16, color: AppColors.hair2),
            ],
          ),
        ),
      ),
    );
  }

  Widget _strengthCard(CmpysStrength s) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: CmpysCardSurface(
        color: AppColors.greenSoft,
        border: false,
        pad: const EdgeInsets.all(14),
        child: Row(
          children: [
            const Icon(PhosphorIconsFill.sparkle,
                size: 20, color: AppColors.green),
            const SizedBox(width: 10),
            Expanded(
              child: Text(s.label,
                  style: AppTypography.bodyMedium.copyWith(
                      color: AppColors.green2,
                      fontSize: 14,
                      fontWeight: FontWeight.w600)),
            ),
          ],
        ),
      ),
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

class _RadarPainter extends CustomPainter {
  _RadarPainter({required this.dims});
  final List<({String label, int you, int idol})> dims;

  @override
  void paint(Canvas canvas, Size size) {
    final n = dims.length;
    final cx = size.width / 2;
    final cy = size.height / 2 + 4;
    final radius = math.min(size.width, size.height) / 2 - 30;

    Offset vertex(int i, double r) {
      final angle = -math.pi / 2 + (i * 2 * math.pi / n);
      return Offset(cx + math.cos(angle) * r, cy + math.sin(angle) * r);
    }

    // grid
    final grid = Paint()
      ..color = AppColors.hair2
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    for (final pct in [0.25, 0.5, 0.75, 1.0]) {
      final path = Path();
      for (var i = 0; i < n; i++) {
        final o = vertex(i, radius * pct);
        i == 0 ? path.moveTo(o.dx, o.dy) : path.lineTo(o.dx, o.dy);
      }
      path.close();
      canvas.drawPath(path, grid);
    }
    for (var i = 0; i < n; i++) {
      canvas.drawLine(Offset(cx, cy), vertex(i, radius), grid);
    }

    Path poly(int Function(int) val) {
      final p = Path();
      for (var i = 0; i < n; i++) {
        final o = vertex(i, radius * val(i) / 100);
        i == 0 ? p.moveTo(o.dx, o.dy) : p.lineTo(o.dx, o.dy);
      }
      p.close();
      return p;
    }

    final idolPath = poly((i) => dims[i].idol);
    canvas.drawPath(idolPath, Paint()..color = AppColors.green.withValues(alpha: 0.2));
    canvas.drawPath(
        idolPath,
        Paint()
          ..color = AppColors.green
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.5
          ..strokeJoin = StrokeJoin.round);

    final youPath = poly((i) => dims[i].you);
    canvas.drawPath(youPath, Paint()..color = AppColors.ochre.withValues(alpha: 0.3));
    canvas.drawPath(
        youPath,
        Paint()
          ..color = AppColors.ochre
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.5
          ..strokeJoin = StrokeJoin.round);
    for (var i = 0; i < n; i++) {
      final o = vertex(i, radius * dims[i].you / 100);
      canvas.drawCircle(o, 3.5, Paint()..color = AppColors.ochre);
      canvas.drawCircle(
          o,
          3.5,
          Paint()
            ..color = Colors.white
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.5);
    }

    // labels
    final tp = TextPainter(textDirection: TextDirection.ltr);
    for (var i = 0; i < n; i++) {
      final o = vertex(i, radius + 18);
      tp.text = TextSpan(
        text: dims[i].label,
        style: TextStyle(
            fontFamily: AppTypography.label.fontFamily,
            fontSize: 11.5,
            fontWeight: FontWeight.w700,
            color: AppColors.ink2),
      );
      tp.layout(maxWidth: 90);
      tp.paint(canvas, o.translate(-tp.width / 2, -tp.height / 2));
    }
  }

  @override
  bool shouldRepaint(covariant _RadarPainter old) => old.dims != dims;
}
