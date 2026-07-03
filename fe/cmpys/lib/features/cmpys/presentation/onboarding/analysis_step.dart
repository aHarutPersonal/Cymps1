import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app/design_tokens.dart';
import '../../../../core/ui/cmpys/cmpys_markdown.dart';
import '../../../../core/ui/cmpys/cmpys_primitives.dart';
import '../../../session/data/session_repository.dart';
import '../../data/cmpys_seed.dart';
import 'results_streamer.dart';

/// AI analysis — streams the real `/generate-results` comparison.
///
/// Think phase shows the backend's live status messages over the green wash;
/// the verdict reveal renders the LLM's comparison markdown as it streams.
/// The same stream continues into the blueprint section in the background and
/// lands in [CmpysOnboardingDraft.blueprintMd] for the plan-gen step.
///
/// No canned verdict exists — on failure the user gets an explicit retry.
class CmpysAnalysisStep extends ConsumerStatefulWidget {
  const CmpysAnalysisStep({
    super.key,
    required this.idol,
    required this.draft,
    required this.onDone,
  });

  final CmpysIdol idol;
  final CmpysOnboardingDraft draft;
  final VoidCallback onDone;

  @override
  ConsumerState<CmpysAnalysisStep> createState() => _CmpysAnalysisStepState();
}

class _CmpysAnalysisStepState extends ConsumerState<CmpysAnalysisStep>
    with TickerProviderStateMixin {
  late final AnimationController _bob;

  String _status = 'Reading your interview…';

  /// Streaming comparison markdown — a [ValueNotifier] so only the markdown
  /// card rebuilds per applied update, not the whole step.
  final ValueNotifier<String> _comparison = ValueNotifier('');
  bool _comparisonDone = false;
  String? _error;

  /// Throttle gate: markdown re-parsing is O(document), so applying every SSE
  /// chunk is O(n²). Chunks land in [_pendingComparison] and get applied at
  /// most once per ~120ms; the final value is always flushed on completion.
  Timer? _throttle;
  String _pendingComparison = '';

  @override
  void initState() {
    super.initState();
    _bob = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2600),
    )..repeat(reverse: true);

    final existing = widget.draft.comparisonMd;
    if (existing != null && existing.isNotEmpty) {
      // Already generated (back-nav / retry path) — show it immediately.
      _comparison.value = existing;
      _pendingComparison = existing;
      _comparisonDone = true;
    } else {
      _start();
    }
  }

  @override
  void dispose() {
    _throttle?.cancel();
    _bob.dispose();
    _comparison.dispose();
    super.dispose();
  }

  void _onComparisonChunk(String acc) {
    widget.draft.comparisonMd = acc;
    _pendingComparison = acc;
    if (_throttle?.isActive ?? false) return; // gate closed — timer flushes
    _applyPendingComparison();
    _throttle = Timer(
        const Duration(milliseconds: 120), _applyPendingComparison);
  }

  void _applyPendingComparison() {
    if (!mounted) return;
    final wasEmpty = _comparison.value.isEmpty;
    _comparison.value = _pendingComparison;
    if (wasEmpty && _pendingComparison.isNotEmpty) {
      setState(() {}); // first text — switch thinking → verdict screen
    }
  }

  void _flushComparison() {
    _throttle?.cancel();
    _applyPendingComparison();
  }

  Future<void> _start() async {
    final sessionId = widget.draft.sessionId;
    if (sessionId == null) {
      setState(() => _error = 'No active session. Go back and try again.');
      return;
    }
    setState(() {
      _error = null;
      widget.draft.resultsFailed = false;
    });

    try {
      final repo = ref.read(sessionRepositoryProvider);
      await streamGenerateResults(
        repo: repo,
        sessionId: sessionId,
        onStatus: (s) {
          if (mounted && s.isNotEmpty) setState(() => _status = s);
        },
        onComparison: _onComparisonChunk,
        onBlueprint: (acc) {
          // Keep flowing into the draft even if this widget gets disposed —
          // the plan-gen step polls the draft for completion.
          widget.draft.blueprintMd = acc;
          if (mounted && !_comparisonDone) {
            _flushComparison();
            setState(() => _comparisonDone = true);
          }
        },
        onPlanJob: (jobId) => widget.draft.planJobId = jobId,
      );
      widget.draft.resultsFailed = false;
      _flushComparison();
      if (mounted) setState(() => _comparisonDone = true);
    } catch (e) {
      widget.draft.resultsFailed = true;
      if (!mounted) return;
      _flushComparison();
      if (_comparison.value.isEmpty) {
        setState(() => _error =
            'The analysis didn’t come through. Check your connection and try again.');
      } else {
        // Comparison made it; blueprint failed — plan-gen step offers retry.
        setState(() => _comparisonDone = true);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_error != null) return _errorScreen();
    if (_comparison.value.isEmpty) return _thinkingScreen();
    return _verdictScreen();
  }

  Widget _errorScreen() {
    return Container(
      decoration: const BoxDecoration(gradient: AppColors.gradGreen),
      child: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.wifi_off_rounded,
                    size: 36, color: Colors.white),
                const SizedBox(height: 16),
                Text(_error!,
                    textAlign: TextAlign.center,
                    style: AppTypography.bodyLarge.copyWith(
                        color: Colors.white, fontSize: 16, height: 1.5)),
                const SizedBox(height: 22),
                CmpysButton(
                  variant: CmpysBtnVariant.dark,
                  size: CmpysBtnSize.lg,
                  leadingIcon: Icons.refresh_rounded,
                  onTap: _start,
                  child: const Text('Try again'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _thinkingScreen() {
    return Container(
      decoration: const BoxDecoration(gradient: AppColors.gradGreen),
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 26),
          child: Column(
            children: [
              const SizedBox(height: 90),
              AnimatedBuilder(
                animation: _bob,
                builder: (_, child) => Transform.translate(
                  offset: Offset(0, -3 * (1 - (_bob.value * 2 - 1).abs())),
                  child: child,
                ),
                child: CmpysMentorAvatar(
                  slug: widget.idol.slug,
                  initials: widget.idol.initials,
                  color: widget.idol.color,
                  tint: Colors.white,
                  size: 84,
                  border: Border.all(color: Colors.white, width: 2),
                ),
              ),
              const SizedBox(height: 28),
              Text(
                'COMPARING YOU WITH ${widget.idol.short.toUpperCase()}',
                style: AppTypography.kicker.copyWith(
                  color: Colors.white.withValues(alpha: 0.7),
                ),
              ),
              const SizedBox(height: 18),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.18),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Row(
                  children: [
                    const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        valueColor:
                            AlwaysStoppedAnimation<Color>(Color(0xFFFFD166)),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        _status,
                        style: AppTypography.body.copyWith(
                          color: Colors.white.withValues(alpha: 0.9),
                          fontSize: 13.5,
                          fontStyle: FontStyle.italic,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const Spacer(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _verdictScreen() {
    return SafeArea(
      child: Column(
        children: [
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(22, 50, 22, 16),
              children: [
                const CmpysKicker('The verdict', color: AppColors.green),
                const SizedBox(height: 10),
                Padding(
                  padding: const EdgeInsets.only(bottom: 14),
                  child: Text(
                    'You vs ${widget.idol.short}, in plain terms.',
                    style: AppTypography.display.copyWith(
                        fontSize: 28,
                        fontWeight: FontWeight.w500,
                        letterSpacing: -0.4,
                        height: 1.3),
                  ),
                ),
                CmpysCardSurface(
                  raised: true,
                  pad: const EdgeInsets.all(20),
                  child: ValueListenableBuilder<String>(
                    valueListenable: _comparison,
                    builder: (_, md, _) => CmpysMarkdown(md),
                  ),
                ),
                if (!_comparisonDone) ...[
                  const SizedBox(height: 14),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const SizedBox(
                        width: 13,
                        height: 13,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          valueColor: AlwaysStoppedAnimation<Color>(
                              AppColors.green),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text('${widget.idol.short} is still writing…',
                          style: AppTypography.caption.copyWith(
                              color: AppColors.ink3, fontSize: 12.5)),
                    ],
                  ),
                ],
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.fromLTRB(22, 12, 22, 26),
            decoration: const BoxDecoration(
              color: AppColors.paper,
              border: Border(top: BorderSide(color: AppColors.hair, width: 1)),
            ),
            child: CmpysButton(
              variant: CmpysBtnVariant.primary,
              size: CmpysBtnSize.lg,
              full: true,
              disabled: !_comparisonDone,
              trailingIcon: Icons.arrow_forward_rounded,
              onTap: _comparisonDone ? widget.onDone : null,
              child: const Text('Build my plan to close the gap'),
            ),
          ),
        ],
      ),
    );
  }
}
