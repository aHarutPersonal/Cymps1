import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' show PathMetric;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/design_tokens.dart';
import '../../../app/router.dart';
import '../../../core/ui/app_shell.dart';
import '../../../core/ui/cmpys/cmpys_markdown.dart';
import '../../../core/ui/motion/motion_config.dart';
import '../../../core/ui/motion/page_transition.dart';
import '../../../core/ui/v3/v3.dart';
import '../data/cmpys_seed.dart';
import '../../session/data/session_repository.dart';
import '../state/cmpys_backend_sync.dart';
import '../state/cmpys_store.dart';
import 'onboarding/mentor_image.dart';
import 'record_screen.dart';

typedef LiveDim = ({
  String id,
  String label,
  int? you,
  int? idol,
  String youNote,
  String idolNote,
  String status,
  String comparisonBasis,
  String youEvidence,
  String idolEvidence,
});

/// How a dimension is shown, from the design's `DIM_STATE`.
enum _DimState {
  comparable('Like for like', AppColors.sage2, AppColors.sageSoft),
  incompatible('Not comparable', AppColors.gold2, AppColors.goldSoft),
  missing('Evidence missing', AppColors.ink2, AppColors.paper2);

  const _DimState(this.label, this.color, this.background);
  final String label;
  final Color color;
  final Color background;

  /// comparable → Like for like; different_basis → Not comparable;
  /// insufficient_* and any unknown status → Evidence missing. A
  /// "comparable" row without both scores has nothing to draw, so it is
  /// treated as missing evidence rather than as a zero.
  static _DimState of(LiveDim d) {
    if (d.status == 'comparable' && d.you != null && d.idol != null) {
      return comparable;
    }
    if (d.status == 'different_basis') return incompatible;
    return missing;
  }
}

/// The starting checks' skill names (`learner_diagnostics[].skill_id`).
const _skillLabels = {
  'profit_vs_cash': 'Profit and cash',
  'maintenance_vs_growth': 'Maintenance and growth spending',
  'pythagorean_calculation': 'Right-triangle calculation',
  'pythagorean_precondition': 'When the triangle rule applies',
  'logical_implication': 'Logical implication',
  'universal_counterexample': 'Testing a universal claim',
  'goal_specific_sample': 'Your work example',
  'goal_specific_validation': 'Checking your work',
};

/// The starting checks' statuses (`learner_diagnostics[].status`). The
/// backend's `unknown` is an answer that wasn't given (or was recorded as
/// missing evidence), so it reads "Not provided yet". `needs_review` is an
/// open answer that isn't auto-graded, so it reads "Reviewed by your mentor";
/// a wrong answer (`needs_practice_on_item`) keeps "Revisit this specific
/// skill" (owner decision 7).
const _checkStatuses = {
  'correct_on_item': 'Correct on this check',
  'needs_practice_on_item': 'Revisit this specific skill',
  'needs_review': 'Reviewed by your mentor',
  'unknown': 'Not provided yet',
  'not_assessed': 'Not checked yet',
};

/// A status this build doesn't know claims nothing about the answer.
const _unknownCheckStatus = 'Not checked yet';

/// Scorer enums and field names that can reach the learner inside
/// comparison evidence and gap text, as plain words.
const _scorerWords = {
  'needs_review': 'needs a closer review',
  'needs_practice_on_item': 'needs practice on this skill',
  'correct_on_item': 'correct on this check',
  'not_assessed': 'not checked yet',
  'insufficient_user_evidence': 'not enough of your evidence',
  'insufficient_evidence': 'not enough evidence',
  'different_basis': 'not comparable',
  'missing_evidence_keys': 'missing answers',
  'missing_evidence': 'missing evidence',
  'learner_diagnostics': 'starting checks',
  'skill_diagnostics': 'starting checks',
  'self_reported': 'self-reported',
  'like_for_like_evidence': 'like-for-like evidence',
};

final _snakeToken = RegExp(
  r'(?<![\w/.:@-])[a-z][a-z0-9]*(?:_[a-z0-9]+)+(?![\w/@-])',
);
final _factsNotSupplied = RegExp(
  r"((?:[A-Z][\w’'.-]*\s+)*[A-Z][\w’'.-]*)\s+facts at (\d+) (?:were |was )?not supplied",
);

/// [text] from the comparison scorer (a dimension's evidence, mentor note or
/// gap reason), with its shorthand in plain words (F12). The prompt asks for
/// plain sentences; this is the app's defensive half:
/// - "The relevant learner input has not been established." → "You
///   haven’t shared this yet.";
/// - "{Name} facts at {age} not supplied" → "no verified record of {Name}
///   at {age} for this yet" (capitalised at the start of a sentence);
/// - known enums (`needs_review`, `insufficient_idol_evidence`, skill ids, …)
///   → their words, naming [mentor] where the enum refers to the mentor;
/// - any other snake_case token loses its underscores.
/// Ordinary prose, numbers and links are unchanged.
String plainComparisonText(String text, {required String mentor}) {
  if (text.trim() == 'The relevant learner input has not been established.') {
    return 'You haven’t shared this yet.';
  }
  var out = text.replaceAllMapped(_factsNotSupplied, (m) {
    final start =
        m.start == 0 ||
        RegExp(r'[.!?]\s*$').hasMatch(text.substring(0, m.start));
    return '${start ? 'No' : 'no'} verified record of ${m[1]} at ${m[2]} '
        'for this yet';
  });
  out = out.replaceAllMapped(_snakeToken, (m) {
    final token = m[0]!;
    if (token == 'insufficient_idol_evidence') {
      return 'not enough documented evidence about $mentor';
    }
    final word = _scorerWords[token] ?? _skillLabels[token]?.toLowerCase();
    return word ?? token.replaceAll('_', ' ');
  });
  return out;
}

/// The design's inline quote tint, `oklch(0.78 0.1 42)`.
const _quoteTint = Color(0xFFEEA285);

/// CMPYS Compare tab (v3 `CompareTab`): you and your mentor at the same age,
/// how many dimensions compare like for like, the written perspective, and
/// one row per evidence dimension with a detail sheet.
class CmpysCompareScreen extends ConsumerStatefulWidget {
  const CmpysCompareScreen({super.key});

  @override
  ConsumerState<CmpysCompareScreen> createState() => _CmpysCompareScreenState();
}

class _CmpysCompareScreenState extends ConsumerState<CmpysCompareScreen> {
  @override
  Widget build(BuildContext context) {
    final st = ref.watch(cmpysStoreProvider);
    ref.watch(cmpysBackendSyncProvider);
    final scoresSync = ref.watch(cmpysComparisonScoresSyncProvider);
    final idol = st.idol;
    final dims = st.liveDims();
    final age = st.user.age > 0 ? st.user.age : null;
    final perspective = perspectiveParagraphs(st.comparisonMd);
    final diagnostics = st.liveComparisonScores?['learner_diagnostics'];
    final top = math.max(MediaQuery.paddingOf(context).top + 8, 20.0);

    return Scaffold(
      backgroundColor: AppColors.paper,
      body: ListView(
        padding: EdgeInsets.only(bottom: AppShell.bottomNavClearance(context)),
        children: [
          Padding(
            padding: EdgeInsets.fromLTRB(20, top, 20, 0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                V3Rise(child: Text('COMPARE', style: AppTypography.kick)),
                const SizedBox(height: 10),
                V3Rise(
                  delay: const Duration(milliseconds: 50),
                  child: _headline(idol, age),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 22, 20, 0),
            child: V3Rise(
              delay: const Duration(milliseconds: 100),
              child: Center(child: _faces(st.user.name, idol, age)),
            ),
          ),
          if (dims.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 22, 20, 0),
              child: V3Rise(
                delay: const Duration(milliseconds: 160),
                child: _likeForLikeCard(dims),
              ),
            )
          else
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 22, 20, 0),
              child: _comparisonScoresStatus(scoresSync),
            ),
          if (perspective.isNotEmpty)
            V3Rise(
              delay: const Duration(milliseconds: 220),
              child: V3Section(
                title: 'Written perspective',
                child: _perspectiveCard(idol, st.comparisonMd!, perspective),
              ),
            ),
          if (dims.isNotEmpty)
            V3Rise(
              delay: const Duration(milliseconds: 280),
              child: V3Section(
                title: 'Dimensions',
                child: Column(
                  children: [
                    for (var i = 0; i < dims.length; i++)
                      Padding(
                        padding: EdgeInsets.only(top: i == 0 ? 0 : 10),
                        child: V3Rise(
                          delay: Duration(milliseconds: 320 + i * 60),
                          child: _dimRow(dims[i], i, idol, age),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          if (dims.isNotEmpty && diagnostics is List && diagnostics.isNotEmpty)
            V3Section(
              title: 'Your starting checks',
              child: _diagnosticCard(diagnostics),
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
            child: Row(
              children: [
                Expanded(
                  child: V3Button(
                    kind: V3ButtonKind.dark,
                    icon: V3Icons.trophy,
                    full: true,
                    onPressed: () => Navigator.of(context).push(
                      CmpysSheetRoute(
                        builder: (_) => const CmpysRecordScreen(),
                      ),
                    ),
                    child: const Text('Your record'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: V3Button(
                    kind: V3ButtonKind.line,
                    icon: V3Icons.plan,
                    full: true,
                    onPressed: () => context.go(AppRoutes.plan),
                    child: const Text('Plan'),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ── header ──

  /// "You and X, both at age." The age line is dropped, never shown as 0,
  /// when the learner's age is unknown.
  Widget _headline(CmpysIdol idol, int? age) {
    final mentor = idol.short.trim();
    final headline = Text.rich(
      key: const Key('compare-headline'),
      TextSpan(
        children: [
          TextSpan(text: age == null ? 'You and $mentor.' : 'You and $mentor,'),
          if (age != null) ...[
            const TextSpan(text: '\n'),
            TextSpan(
              text: 'both at $age.',
              style: AppTypography.displayItalic(42),
            ),
          ],
        ],
      ),
      style: AppTypography.display(42).copyWith(color: AppColors.ink),
    );
    return Semantics(header: true, child: headline);
  }

  /// The overlapping learner initial, shared age and mentor avatar.
  Widget _faces(String name, CmpysIdol idol, int? age) {
    const big = 104.0;
    const small = 56.0;
    const overlap = 16.0;
    final trimmed = name.trim();
    final initial = trimmed.isEmpty ? '' : trimmed.characters.first;
    final width = age == null
        ? big * 2 - overlap
        : big * 2 + small - overlap * 2;

    BoxDecoration disc(Color color) => BoxDecoration(
      color: color,
      shape: BoxShape.circle,
      border: Border.all(color: AppColors.paper, width: 4),
    );

    final you = Container(
      width: big,
      height: big,
      decoration: disc(AppColors.ink),
      alignment: Alignment.center,
      child: FittedBox(
        fit: BoxFit.scaleDown,
        child: Text(
          initial.toUpperCase(),
          style: AppTypography.display(40).copyWith(color: Colors.white),
        ),
      ),
    );
    final mentor = Container(
      width: big,
      height: big,
      decoration: disc(AppColors.paper),
      child: V3Avatar(
        image: cmpysIdolImage(idol),
        initials: idol.initials,
        tint: idol.tint,
        size: big - 8,
        gray: true,
      ),
    );

    final motion = MotionConfig.enabled(context);
    const ageTop = (big - small) / 2;

    // You fly in from the left and the mentor from the right (`flyL` /
    // `flyR .9s var(--spring) .15s`); then the shared age pops (`pop .6s
    // var(--spring) .85s`) and two ember rings ripple out of it once
    // (`shock .9s .85s`, `shock 1.1s 1s`). Reduced motion: fades only.
    return ExcludeSemantics(
      child: SizedBox(
        width: width,
        height: big,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Positioned(
              left: 0,
              top: 0,
              child: V3Fly(
                key: const Key('compare-fly-you'),
                from: V3FlyFrom.left,
                delay: const Duration(milliseconds: 150),
                child: you,
              ),
            ),
            Positioned(
              right: 0,
              top: 0,
              child: V3Fly(
                key: const Key('compare-fly-mentor'),
                from: V3FlyFrom.right,
                delay: const Duration(milliseconds: 150),
                child: mentor,
              ),
            ),
            if (age != null) ...[
              Positioned(
                left: big - overlap,
                top: ageTop,
                child: _ageIn(
                  motion: motion,
                  child: Container(
                    key: const Key('compare-age-disc'),
                    width: small,
                    height: small,
                    decoration: disc(AppColors.ember),
                    alignment: Alignment.center,
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(
                        '$age',
                        style: AppTypography.sans(18, FontWeight.w700)
                            .merge(AppTypography.tnum)
                            .copyWith(color: Colors.white),
                      ),
                    ),
                  ),
                ),
              ),
              if (motion)
                // The rings sit at inset −4 around the badge.
                Positioned(
                  left: big - overlap - 4,
                  top: ageTop - 4,
                  width: small + 8,
                  height: small + 8,
                  child: const Stack(
                    key: Key('compare-age-rings'),
                    fit: StackFit.expand,
                    children: [
                      V3Shock(delay: Duration(milliseconds: 850)),
                      V3Shock(
                        duration: Duration(milliseconds: 1100),
                        delay: Duration(milliseconds: 1000),
                      ),
                    ],
                  ),
                ),
            ],
          ],
        ),
      ),
    );
  }

  /// The age badge's entrance: `pop .6s var(--spring) .85s both`, or a
  /// plain fade with reduced motion.
  Widget _ageIn({required bool motion, required Widget child}) {
    if (motion) {
      return V3Pop(
        duration: const Duration(milliseconds: 600),
        delay: const Duration(milliseconds: 850),
        child: child,
      );
    }
    return TweenAnimationBuilder<double>(
      key: const Key('compare-age-fade'),
      tween: Tween(begin: 0, end: 1),
      duration: const Duration(milliseconds: 600),
      builder: (context, opacity, child) =>
          Opacity(opacity: opacity, child: child),
      child: child,
    );
  }

  // ── like-for-like count ──

  /// "n of total dimensions compared like for like": solid segments for
  /// comparable dimensions, dashed for the rest. The total is the number of
  /// dimensions in the payload.
  Widget _likeForLikeCard(List<LiveDim> dims) {
    final states = dims.map(_DimState.of).toList();
    final comparable = states.where((s) => s == _DimState.comparable).length;
    return Container(
      key: const Key('compare-like-for-like'),
      padding: const EdgeInsets.all(16),
      decoration: v3Card(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(
                '$comparable',
                key: const Key('compare-comparable-count'),
                style: AppTypography.display(
                  34,
                ).merge(AppTypography.tnum).copyWith(color: AppColors.ink),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  'of ${dims.length} '
                  '${dims.length == 1 ? 'dimension' : 'dimensions'} '
                  'compared like for like',
                  style: AppTypography.sans(14).copyWith(color: AppColors.ink2),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              for (var i = 0; i < states.length; i++)
                Expanded(
                  child: Padding(
                    padding: EdgeInsets.only(left: i == 0 ? 0 : 5),
                    child: V3Pop(
                      duration: const Duration(milliseconds: 450),
                      delay: Duration(milliseconds: 300 + i * 80),
                      child: states[i] == _DimState.comparable
                          ? Container(
                              key: const ValueKey('compare-segment-solid'),
                              height: 8,
                              decoration: BoxDecoration(
                                color: AppColors.ink,
                                borderRadius: BorderRadius.circular(9),
                              ),
                            )
                          : const CustomPaint(
                              key: ValueKey('compare-segment-dashed'),
                              painter: _DashedPillPainter(),
                              child: SizedBox(height: 8),
                            ),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            'Dimensions without comparable evidence are left unscored. '
            'That’s not a zero.',
            style: AppTypography.sans(
              12.5,
            ).copyWith(color: AppColors.ink3, height: 1.45),
          ),
        ],
      ),
    );
  }

  // ── written perspective ──

  Widget _perspectiveCard(
    CmpysIdol idol,
    String markdown,
    List<String> paragraphs,
  ) {
    return V3Pressable(
      key: const Key('compare-perspective-card'),
      onTap: () => _openPerspective(idol, markdown),
      focusRadius: AppRadii.brR,
      child: ClipRRect(
        borderRadius: AppRadii.brR,
        child: Container(
          width: double.infinity,
          color: AppColors.night,
          child: Stack(
            children: [
              const Positioned.fill(child: V3Grain()),
              Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const V3Icon(V3Icons.quote, size: 26, color: _quoteTint),
                    const SizedBox(height: 8),
                    Text(
                      paragraphs.first,
                      maxLines: 5,
                      overflow: TextOverflow.ellipsis,
                      style: AppTypography.read(
                        17,
                      ).copyWith(color: Colors.white, height: 1.6),
                    ),
                    const SizedBox(height: 14),
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            'Read in full',
                            style: AppTypography.sans(
                              13.5,
                              FontWeight.w600,
                            ).copyWith(color: Colors.white),
                          ),
                        ),
                        const SizedBox(width: 4),
                        const V3Icon(
                          V3Icons.right,
                          size: 15,
                          color: Colors.white,
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// The full perspective, rendered as markdown so emphasis, rules and links
  /// survive, in Literata 16.5 / 1.65 as the design's sheet.
  void _openPerspective(CmpysIdol idol, String markdown) {
    unawaited(
      showV3Sheet<void>(
        context,
        title: 'Written perspective',
        max: 0.9,
        builder: (_) => Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            V3Rise(
              child: CmpysMarkdown(
                markdown,
                readerTheme: ReaderTheme.light,
                fontSize: 16.5,
                lineHeight: 1.65,
              ),
            ),
            const SizedBox(height: 14),
            Text(
              'Written by an AI interpretation of ${idol.name}. Historical '
              'claims come from cited biographies; treat them as reported, '
              'not certain.',
              style: AppTypography.sans(
                12,
              ).copyWith(color: AppColors.ink3, height: 1.5),
            ),
          ],
        ),
      ),
    );
  }

  // ── dimensions ──

  String _mentorAtAge(CmpysIdol idol, int? age) =>
      age == null ? idol.short : '${idol.short} at $age';

  Widget _dimRow(LiveDim d, int index, CmpysIdol idol, int? age) {
    final state = _DimState.of(d);
    final basis = plainComparisonText(
      d.comparisonBasis.trim(),
      mentor: idol.short,
    );
    final barDelay = 400 + index * 80;
    return V3Pressable(
      key: const ValueKey('compare-dim-row'),
      onTap: () => _openDim(d, idol, age),
      focusRadius: AppRadii.brR,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(16),
        decoration: v3Card(),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Wrap(
                    alignment: WrapAlignment.spaceBetween,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    spacing: 8,
                    runSpacing: 6,
                    children: [
                      Text(
                        d.label,
                        style: AppTypography.sans(
                          15.5,
                          FontWeight.w600,
                        ).copyWith(color: AppColors.ink),
                      ),
                      FittedBox(fit: BoxFit.scaleDown, child: _tag(state)),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                const V3Icon(V3Icons.right, size: 15, color: AppColors.ink3),
              ],
            ),
            if (state == _DimState.comparable) ...[
              const SizedBox(height: 14),
              _barRow('You', d.you!, AppColors.ember, barDelay, barDelay),
              const SizedBox(height: 8),
              _barRow(
                _mentorAtAge(idol, age),
                d.idol!,
                AppColors.ink,
                barDelay + 120,
                barDelay,
              ),
            ] else if (basis.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(
                basis,
                style: AppTypography.sans(
                  13.5,
                ).copyWith(color: AppColors.ink2, height: 1.45),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _tag(_DimState state) => V3Tag(
    color: state.color,
    background: state.background,
    child: Text(state.label),
  );

  Widget _barRow(
    String who,
    int value,
    Color color,
    int barDelayMs,
    int countDelayMs,
  ) {
    final row = Row(
      children: [
        SizedBox(
          width: 92,
          child: Text(
            who,
            style: AppTypography.sans(
              12.5,
              FontWeight.w500,
            ).copyWith(color: AppColors.ink2),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: V3Bar(
            value: value / 100,
            color: color,
            height: 8,
            delay: Duration(milliseconds: barDelayMs),
          ),
        ),
        const SizedBox(width: 10),
        Container(
          constraints: const BoxConstraints(minWidth: 24),
          alignment: Alignment.centerRight,
          child: V3CountUp(
            to: value,
            delay: Duration(milliseconds: countDelayMs),
            style: AppTypography.sans(
              13,
              FontWeight.w700,
            ).merge(AppTypography.tnum).copyWith(color: AppColors.ink),
          ),
        ),
      ],
    );
    return Semantics(
      label: '$who: $value out of 100',
      excludeSemantics: true,
      child: row,
    );
  }

  void _openDim(LiveDim d, CmpysIdol idol, int? age) {
    unawaited(
      showV3Sheet<void>(
        context,
        title: d.label,
        builder: (_) => _dimDetail(d, idol, age),
      ),
    );
  }

  /// The design's `DimDetail`: Your evidence, the mentor at the same age,
  /// then Uncertainty (comparable) or "Why there’s no score". A section
  /// whose payload text is missing is left out.
  Widget _dimDetail(LiveDim d, CmpysIdol idol, int? age) {
    final state = _DimState.of(d);
    String plain(String text) =>
        plainComparisonText(text.trim(), mentor: idol.short);
    final youNote = plain(d.youNote);
    final idolNote = plain(d.idolNote);
    final basis = plain(d.comparisonBasis);

    Widget score(String who, int value, Color color) => Expanded(
      child: Semantics(
        label: '$who: $value out of 100',
        excludeSemantics: true,
        child: Container(
          key: const ValueKey('compare-score-box'),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppColors.hair),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                who,
                style: AppTypography.sans(
                  12,
                  FontWeight.w600,
                ).copyWith(color: AppColors.ink3),
              ),
              V3CountUp(
                to: value,
                style: AppTypography.display(
                  38,
                ).merge(AppTypography.tnum).copyWith(color: color),
              ),
            ],
          ),
        ),
      ),
    );

    Widget block(String title, String body, {Color? tone}) => Container(
      width: double.infinity,
      margin: const EdgeInsets.only(top: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: tone ?? AppColors.paper,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: AppTypography.sans(
              12,
              FontWeight.w600,
            ).copyWith(color: AppColors.ink2),
          ),
          const SizedBox(height: 4),
          Text(
            body,
            style: AppTypography.sans(
              14.5,
            ).copyWith(color: AppColors.ink, height: 1.5),
          ),
        ],
      ),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        FittedBox(fit: BoxFit.scaleDown, child: _tag(state)),
        if (state == _DimState.comparable)
          Padding(
            padding: const EdgeInsets.only(top: 14),
            child: Row(
              children: [
                score('You', d.you!, AppColors.ember),
                const SizedBox(width: 10),
                score(idol.short, d.idol!, AppColors.ink),
              ],
            ),
          ),
        if (youNote.isNotEmpty) block('Your evidence', youNote),
        if (idolNote.isNotEmpty) block(_mentorAtAge(idol, age), idolNote),
        if (basis.isNotEmpty)
          block(
            state == _DimState.comparable
                ? 'Uncertainty'
                : 'Why there’s no score',
            basis,
            tone: state.background,
          ),
        const SizedBox(height: 12),
        Text(
          'Scores show evidence on a shared scale for this dimension only. '
          'They don’t rank overall ability.',
          style: AppTypography.sans(
            12,
          ).copyWith(color: AppColors.ink3, height: 1.45),
        ),
      ],
    );
  }

  // ── starting skill checks (server diagnostics, kept from v2) ──

  Widget _diagnosticCard(List values) {
    return Container(
      key: const Key('comparison-skill-checks'),
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: v3Card(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final value in values.whereType<Map>())
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(
                '${_skillLabels[value['skill_id']] ?? 'Skill check'}: '
                '${_checkStatuses[value['status']] ?? _unknownCheckStatus}',
                style: AppTypography.sans(
                  14,
                  FontWeight.w500,
                ).copyWith(color: AppColors.ink),
              ),
            ),
          Text(
            'Brief checks guide the next lesson; they do not certify your overall level.',
            style: AppTypography.sans(
              12.5,
            ).copyWith(color: AppColors.ink3, height: 1.45),
          ),
        ],
      ),
    );
  }

  // ── score generation states (no dimensions yet) ──

  Widget _comparisonScoresStatus(
    AsyncValue<ComparisonScoresSyncResult> scoresSync,
  ) {
    return scoresSync.when(
      loading: () => _comparisonScoresCard(
        key: const Key('comparison-scores-pending'),
        title: 'Assessing the evidence for each dimension.',
        subtitle: 'Your written comparison and learning plan remain available.',
        loading: true,
      ),
      error: (error, stackTrace) => _comparisonScoresCard(
        key: const Key('comparison-scores-retry'),
        title: 'We couldn’t refresh your comparison.',
        subtitle: 'Tap to try again now.',
        onRetry: () => ref.invalidate(cmpysComparisonScoresSyncProvider),
      ),
      data: (result) {
        switch (result) {
          case ComparisonScoresSyncResult.unavailable:
            return _comparisonScoresCard(
              key: const Key('comparison-scores-unavailable'),
              title: 'Comparison scores aren’t available yet.',
              subtitle: 'Complete your mentor interview to create them.',
            );
          case ComparisonScoresSyncResult.timedOut:
            return _comparisonScoresCard(
              key: const Key('comparison-scores-retry'),
              title: 'Your comparison is still being prepared.',
              subtitle: 'Tap to check again now.',
              onRetry: () => ref.invalidate(cmpysComparisonScoresSyncProvider),
            );
          case ComparisonScoresSyncResult.failed:
            return _comparisonScoresCard(
              key: const Key('comparison-scores-failed'),
              title: 'Your dimension assessment couldn’t finish.',
              subtitle:
                  'Your written comparison is saved. Tap to retry the assessment.',
              onRetry: () => unawaited(_retryComparisonScores()),
            );
          case ComparisonScoresSyncResult.ready:
            // A ready result normally rebuilds this screen with dimensions.
            // If a malformed payload slipped through, never show a spinner.
            return _comparisonScoresCard(
              key: const Key('comparison-scores-retry'),
              title: 'We couldn’t read your comparison scores.',
              subtitle: 'Tap to refresh them.',
              onRetry: () => ref.invalidate(cmpysComparisonScoresSyncProvider),
            );
        }
      },
    );
  }

  Future<void> _retryComparisonScores() async {
    final sessionId = ref.read(cmpysStoreProvider).sessionId?.trim();
    if (sessionId == null || sessionId.isEmpty) {
      ref.invalidate(cmpysComparisonScoresSyncProvider);
      return;
    }
    try {
      final session = await ref
          .read(sessionRepositoryProvider)
          .retryComparisonScores(sessionId);
      if (!mounted) return;
      ref.read(cmpysStoreProvider.notifier).syncFromSession(session);
      ref.invalidate(cmpysComparisonScoresSyncProvider);
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Could not restart comparison scoring. Try again.'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  Widget _comparisonScoresCard({
    required Key key,
    required String title,
    required String subtitle,
    bool loading = false,
    VoidCallback? onRetry,
  }) {
    final body = Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: v3Card(),
      child: Row(
        children: [
          SizedBox(
            width: 20,
            height: 20,
            child: Center(
              child: loading
                  ? const V3Spinner(color: AppColors.ember)
                  : const V3Icon(
                      V3Icons.refresh,
                      size: 20,
                      color: AppColors.ember,
                    ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: AppTypography.sans(
                    14.5,
                    FontWeight.w600,
                  ).copyWith(color: AppColors.ink),
                ),
                const SizedBox(height: 3),
                Text(
                  subtitle,
                  style: AppTypography.sans(
                    12.5,
                  ).copyWith(color: AppColors.ink3),
                ),
              ],
            ),
          ),
        ],
      ),
    );
    if (onRetry == null) return KeyedSubtree(key: key, child: body);
    return V3Pressable(
      key: key,
      onTap: onRetry,
      focusRadius: AppRadii.brR,
      child: body,
    );
  }
}

/// The written perspective as plain paragraphs for the card preview: split
/// on blank lines; headings and rules (`---`) dropped; quote and list
/// markers removed; links and images unwrapped to their text; inline code
/// and `**`/`__`/`*`/`_` emphasis unwrapped. A literal `*` or `_` that does
/// not delimit emphasis (as in "5 * 3" or "snake_case") is kept.
@visibleForTesting
List<String> perspectiveParagraphs(String? markdown) {
  if (markdown == null || markdown.trim().isEmpty) return const [];
  final heading = RegExp(r'^\s{0,3}#{1,6}\s');
  final rule = RegExp(r'^\s{0,3}([-*_])(?:\s*\1){2,}\s*$');
  final marker = RegExp(r'^\s*(?:>\s?|[-*+]\s+)');
  final link = RegExp(r'!?\[([^\]]*)\]\([^)]*\)');
  final code = RegExp(r'`([^`]*)`');
  final strong = RegExp(r'(\*\*|__)(?=\S)(.+?)(?<=\S)\1');
  final emStar = RegExp(r'(?<![\w*])\*(?=[^\s*])(.+?)(?<=[^\s*])\*(?![\w*])');
  final emUnderscore = RegExp(
    r'(?<![\w_])_(?=[^\s_])(.+?)(?<=[^\s_])_(?![\w_])',
  );
  final out = <String>[];
  for (final block in markdown.split(RegExp(r'\n\s*\n'))) {
    final lines = block
        .split('\n')
        .where((line) => !heading.hasMatch(line) && !rule.hasMatch(line))
        .map((line) => line.replaceFirst(marker, '').trim())
        .where((line) => line.isNotEmpty);
    final text = lines
        .join(' ')
        .replaceAllMapped(link, (m) => m[1]!)
        .replaceAllMapped(code, (m) => m[1]!)
        .replaceAllMapped(strong, (m) => m[2]!)
        .replaceAllMapped(emStar, (m) => m[1]!)
        .replaceAllMapped(emUnderscore, (m) => m[1]!)
        .trim();
    if (text.isNotEmpty) out.add(text);
  }
  return out;
}

/// A pill outline in a 1.5 pt dashed hair2 stroke (`1.5px dashed
/// var(--hair2)`), for a dimension that is not compared like for like.
class _DashedPillPainter extends CustomPainter {
  const _DashedPillPainter();

  static const double _stroke = 1.5;
  static const double _dash = 4;
  static const double _gap = 3;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    final rect = (Offset.zero & size).deflate(_stroke / 2);
    final path = Path()
      ..addRRect(RRect.fromRectAndRadius(rect, const Radius.circular(9)));
    final paint = Paint()
      ..color = AppColors.hair2
      ..style = PaintingStyle.stroke
      ..strokeWidth = _stroke;
    for (final PathMetric metric in path.computeMetrics()) {
      for (var d = 0.0; d < metric.length; d += _dash + _gap) {
        canvas.drawPath(
          metric.extractPath(d, math.min(d + _dash, metric.length)),
          paint,
        );
      }
    }
  }

  @override
  bool shouldRepaint(_DashedPillPainter oldDelegate) => false;
}
