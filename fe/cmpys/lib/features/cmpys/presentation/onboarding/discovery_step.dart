import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../../../app/design_tokens.dart';
import '../../../../core/ui/cmpys/cmpys_primitives.dart';
import '../../../session/data/session_repository.dart';
import '../../../session/models/session_models.dart';
import '../../data/cmpys_seed.dart';

/// Idol discovery — LLM-driven, interest-aware.
///
/// On entry, the screen creates a backend agentic session carrying the user's
/// age + interests, then calls the Gemini-powered
/// `/sessions/{id}/suggest-idols` endpoint. While that's in flight, a "thinking"
/// overlay ([CmpysThinkFeed]) narrates the match. The LLM's `confidence`
/// becomes the "% fit" badge and `relevance_summary` becomes the "why" copy —
/// every suggestion is genuinely model-generated from the user's answers.
///
/// There is **no client-side fallback**: if the backend is unreachable the
/// screen shows an explicit error with retry, never synthetic suggestions.
class CmpysDiscoveryStep extends ConsumerStatefulWidget {
  const CmpysDiscoveryStep({
    super.key,
    required this.onPick,
    required this.interests,
    required this.age,
    this.goalId,
    this.existingSessionId,
    this.onSessionCreated,
  });

  final ValueChanged<CmpysIdol> onPick;
  final Set<String> interests;
  final int age;
  final String? goalId;
  final String? existingSessionId;
  final ValueChanged<String>? onSessionCreated;

  @override
  ConsumerState<CmpysDiscoveryStep> createState() =>
      _CmpysDiscoveryStepState();
}

class _CmpysDiscoveryStepState extends ConsumerState<CmpysDiscoveryStep> {
  String _query = '';
  bool _loading = true;
  String? _error;
  List<CmpysIdolSuggestion> _suggestions = const [];

  @override
  void initState() {
    super.initState();
    _loadSuggestions();
  }

  /// LLM suggestions via the backend — the only source. Errors surface with a
  /// retry; we never substitute synthetic content.
  Future<void> _loadSuggestions() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final repo = ref.read(sessionRepositoryProvider);

      // Reuse an existing session if we already made one this run; else start
      // clean: abandon any half-finished session from a previous run (which
      // would otherwise 409 createSession and push us to the offline ranker),
      // then create a fresh idol-selection session carrying the intake.
      String sessionId;
      if (widget.existingSessionId != null) {
        sessionId = widget.existingSessionId!;
      } else {
        await repo.abandonCurrentSession();
        final session = await repo.createSession(
          SessionCreateRequest(
            age: widget.age,
            financialStatus: _financialStatusForGoal(widget.goalId),
            interests: widget.interests.toList(),
            goal: _goalLabelForId(widget.goalId),
          ),
        );
        sessionId = session.id;
        widget.onSessionCreated?.call(sessionId);
      }

      final llm = await repo.suggestIdols(sessionId);
      if (!mounted) return;

      if (llm.isEmpty) {
        throw StateError('no suggestions returned');
      }

      final mapped = llm.map(_mapSuggestion).toList()
        ..sort((a, b) => b.score.compareTo(a.score));
      setState(() {
        _suggestions = mapped;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error =
            'Couldn’t reach your mentor AI. Check your connection and try again.';
      });
    }
  }

  CmpysIdolSuggestion _mapSuggestion(IdolSuggestion s) {
    final idol = cmpysIdolFromSuggestion(
      name: s.name,
      era: s.era,
      summary: s.relevanceSummary,
      domains: s.domains,
      wikidataId: s.wikidataId,
    );
    final score = (s.confidence * 100).clamp(0, 99).round();
    final reason = s.relevanceSummary.trim().isEmpty
        ? 'Chosen by your mentor AI as a strong match for your goals.'
        : s.relevanceSummary.trim();
    return CmpysIdolSuggestion(idol: idol, score: score, reason: reason);
  }

  /// Human-readable goal label sent to the backend verbatim, so prompts see
  /// "Build wealth" rather than a lossy financial-status bucket.
  String? _goalLabelForId(String? goalId) {
    if (goalId == null) return null;
    for (final g in cmpysGoals) {
      if (g.id == goalId) return g.label;
    }
    return null;
  }

  String _financialStatusForGoal(String? goalId) {
    switch (goalId) {
      case 'wealth':
        return 'building_wealth';
      case 'career':
        return 'early_career';
      default:
        return 'not_specified';
    }
  }

  List<CmpysIdolSuggestion> get _filtered {
    if (_query.trim().isEmpty) return _suggestions;
    final q = _query.toLowerCase();
    return _suggestions
        .where((s) =>
            '${s.idol.name} ${s.idol.title} ${s.idol.field}'
                .toLowerCase()
                .contains(q))
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return _thinkingOverlay();
    if (_error != null) return _errorScreen();
    return _discoveryList();
  }

  // ─── error + retry (no synthetic fallback) ──────────────────────────────
  Widget _errorScreen() {
    return SafeArea(
      child: Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 64,
                height: 64,
                decoration: BoxDecoration(
                  color: AppColors.claySoft,
                  borderRadius: BorderRadius.circular(18),
                ),
                child: const Icon(Icons.wifi_off_rounded,
                    size: 28, color: AppColors.danger),
              ),
              const SizedBox(height: 18),
              Text('Your mentor AI is unreachable',
                  textAlign: TextAlign.center,
                  style: AppTypography.h3.copyWith(fontSize: 21, height: 1.3)),
              const SizedBox(height: 8),
              Text(_error!,
                  textAlign: TextAlign.center,
                  style: AppTypography.bodyDim.copyWith(fontSize: 14.5)),
              const SizedBox(height: 22),
              CmpysButton(
                variant: CmpysBtnVariant.primary,
                size: CmpysBtnSize.lg,
                leadingIcon: Icons.refresh_rounded,
                onTap: _loadSuggestions,
                child: const Text('Try again'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ─── thinking overlay (LLM-style) ───────────────────────────────────────
  Widget _thinkingOverlay() {
    return Container(
      decoration: const BoxDecoration(gradient: AppColors.gradGreen),
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 26),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 60),
              Text(
                'MATCHING YOU WITH A MENTOR',
                style: AppTypography.kicker.copyWith(
                  color: Colors.white.withValues(alpha: 0.75),
                ),
              ),
              const SizedBox(height: 10),
              Text(
                'Thinking…',
                style: AppTypography.display.copyWith(
                  color: Colors.white,
                  fontSize: 34,
                  letterSpacing: -0.4,
                  height: 1.3,
                ),
              ),
              const SizedBox(height: 24),
              Container(
                padding: const EdgeInsets.fromLTRB(16, 18, 16, 18),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.18),
                  borderRadius: BorderRadius.circular(20),
                ),
                width: double.infinity,
                constraints: const BoxConstraints(minHeight: 220),
                child: CmpysThinkFeed(
                  lines: cmpysSuggestionThoughts(
                    interests: widget.interests,
                    goalId: widget.goalId,
                  ),
                  // Slow enough that real network latency is usually covered;
                  // the feed loops gently if the call is slower.
                  intervalMs: 700,
                ),
              ),
              const Spacer(),
            ],
          ),
        ),
      ),
    );
  }

  // ─── ranked list ────────────────────────────────────────────────────────
  Widget _discoveryList() {
    final list = _filtered;
    final featured = _suggestions.isNotEmpty ? _suggestions.first : null;
    final rest = list
        .where((s) => featured == null || s.idol.id != featured.idol.id)
        .toList();
    return SafeArea(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(22, 16, 22, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const CmpysKicker('Choose your mentor', color: AppColors.green),
                const SizedBox(height: 8),
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Text(
                    'Who do you want to measure against?',
                    style: AppTypography.display.copyWith(
                      fontSize: 28,
                      fontWeight: FontWeight.w500,
                      letterSpacing: -0.3,
                      height: 1.32,
                    ),
                  ),
                ),
                _aiAttribution(),
                const SizedBox(height: 12),
                _searchField(),
              ],
            ),
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(18, 10, 18, 30),
              children: [
                if (_query.trim().isEmpty && featured != null) ...[
                  _featuredCard(featured),
                  const SizedBox(height: 14),
                ],
                Padding(
                  padding: const EdgeInsets.only(left: 4, bottom: 12),
                  child: CmpysKicker(
                    _query.trim().isEmpty
                        ? 'More matches'
                        : '${list.length} result${list.length == 1 ? "" : "s"}',
                  ),
                ),
                if (rest.isEmpty)
                  _emptyResults()
                else
                  for (final s in rest) ...[
                    _suggestionRow(s),
                    const SizedBox(height: 10),
                  ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _aiAttribution() {
    return Row(
      children: [
        const Icon(PhosphorIconsFill.sparkle, size: 14, color: AppColors.green),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            'Chosen by AI from your interests',
            style: AppTypography.captionMedium.copyWith(
              color: AppColors.green2,
              fontSize: 12.5,
            ),
          ),
        ),
      ],
    );
  }

  Widget _searchField() {
    return Container(
      height: 48,
      padding: const EdgeInsets.symmetric(horizontal: 14),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(13),
        border: Border.all(color: AppColors.hair2, width: 1.5),
      ),
      child: Row(
        children: [
          const Icon(PhosphorIconsRegular.magnifyingGlass,
              size: 19, color: AppColors.ink3),
          const SizedBox(width: 10),
          Expanded(
            child: TextField(
              onChanged: (v) => setState(() => _query = v),
              style: AppTypography.body.copyWith(fontSize: 15.5),
              cursorColor: AppColors.green,
              decoration: const InputDecoration(
                hintText: 'Search people or fields…',
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
                isDense: true,
                contentPadding: EdgeInsets.zero,
              ),
            ),
          ),
          if (_query.isNotEmpty)
            GestureDetector(
              onTap: () => setState(() => _query = ''),
              child: const Icon(PhosphorIconsRegular.x,
                  size: 17, color: AppColors.ink3),
            ),
        ],
      ),
    );
  }

  Widget _featuredCard(CmpysIdolSuggestion suggestion) {
    final idol = suggestion.idol;
    return GestureDetector(
      onTap: () => widget.onPick(idol),
      child: Container(
        padding: const EdgeInsets.fromLTRB(22, 20, 22, 22),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              idol.color,
              Color.alphaBlend(
                Colors.black.withValues(alpha: 0.16),
                idol.color,
              ),
            ],
          ),
          borderRadius: AppRadii.lg,
          boxShadow: [
            BoxShadow(
              color: idol.color.withValues(alpha: 0.28),
              blurRadius: 20,
              offset: const Offset(0, 10),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(
                  'TOP MATCH FOR YOU',
                  style: AppTypography.kicker.copyWith(
                    color: Colors.white.withValues(alpha: 0.78),
                  ),
                ),
                const Spacer(),
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    '${suggestion.score}% fit',
                    style: AppTypography.kicker.copyWith(
                      color: Colors.white,
                      fontSize: 10.5,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                CmpysMentorAvatar(
                  slug: idol.slug,
                  initials: idol.initials,
                  color: idol.color,
                  tint: Colors.white,
                  size: 56,
                  border: Border.all(color: Colors.white, width: 2),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        idol.name,
                        style: AppTypography.h2.copyWith(
                          color: Colors.white,
                          fontSize: 23,
                          letterSpacing: -0.4,
                          height: 1.16,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '${idol.title} · ${idol.tag}',
                        style: AppTypography.caption.copyWith(
                          color: Colors.white.withValues(alpha: 0.85),
                          fontSize: 13,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Text(
              '"${idol.quote}"',
              style: AppTypography.readingQuote.copyWith(
                color: Colors.white,
                fontSize: 16.5,
                height: 1.4,
              ),
            ),
            const SizedBox(height: 14),
            Container(
              padding: const EdgeInsets.fromLTRB(10, 10, 10, 10),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Padding(
                    padding: EdgeInsets.only(top: 1),
                    child: Icon(Icons.auto_awesome_rounded,
                        size: 14, color: Colors.white),
                  ),
                  const SizedBox(width: 7),
                  Expanded(
                    child: Text(
                      suggestion.reason,
                      style: AppTypography.caption.copyWith(
                        color: Colors.white.withValues(alpha: 0.95),
                        fontSize: 12.5,
                        height: 1.4,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'View profile',
                  style: AppTypography.bodyMedium.copyWith(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                    fontSize: 14,
                  ),
                ),
                const SizedBox(width: 4),
                const Icon(Icons.arrow_forward_rounded,
                    size: 16, color: Colors.white),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _suggestionRow(CmpysIdolSuggestion s) {
    final idol = s.idol;
    return CmpysCardSurface(
      pad: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      onTap: () => widget.onPick(idol),
      child: Row(
        children: [
          CmpysMentorAvatar(
            slug: idol.slug,
            initials: idol.initials,
            color: idol.color,
            tint: idol.tint,
            size: 48,
          ),
          const SizedBox(width: 13),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        idol.name,
                        style: AppTypography.h4.copyWith(fontSize: 16.5),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 7, vertical: 3),
                      decoration: BoxDecoration(
                        color: idol.tint,
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Text(
                        '${s.score}%',
                        style: AppTypography.kicker.copyWith(
                          color: idol.color,
                          fontSize: 10,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  '${idol.title} · ${idol.era}',
                  style: AppTypography.caption.copyWith(
                    color: AppColors.ink2,
                    fontSize: 13,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          const Icon(Icons.chevron_right_rounded,
              size: 19, color: AppColors.ink3),
        ],
      ),
    );
  }

  Widget _emptyResults() {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 50, horizontal: 20),
      child: Column(
        children: [
          const Icon(PhosphorIconsRegular.magnifyingGlass,
              size: 34, color: AppColors.hair2),
          const SizedBox(height: 12),
          Text(
            'No one by that name yet.',
            style: AppTypography.bodyMedium.copyWith(
              color: AppColors.ink3,
              fontSize: 15,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Try "investor", "writer", or "science".',
            style: AppTypography.caption.copyWith(
              color: AppColors.ink3,
              fontSize: 13,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}
