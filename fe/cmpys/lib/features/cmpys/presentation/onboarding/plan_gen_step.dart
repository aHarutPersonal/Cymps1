import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../../../app/design_tokens.dart';
import '../../../../core/ui/cmpys/cmpys_primitives.dart';
import '../../../session/data/session_repository.dart';
import '../../data/cmpys_seed.dart';
import 'results_streamer.dart';

/// Plan generation — the real LLM blueprint.
///
/// The blueprint usually streams in the background while the user reads the
/// verdict (the analysis step keeps writing into the draft). This step shows
/// the dark thinking screen until [CmpysOnboardingDraft.blueprintMd] lands,
/// retries the stream on failure, and reveals "Your blueprint is ready".
class CmpysPlanGenStep extends ConsumerStatefulWidget {
  const CmpysPlanGenStep({
    super.key,
    required this.idol,
    required this.draft,
    required this.onDone,
  });
  final CmpysIdol idol;
  final CmpysOnboardingDraft draft;
  final VoidCallback onDone;

  @override
  ConsumerState<CmpysPlanGenStep> createState() => _CmpysPlanGenStepState();
}

class _CmpysPlanGenStepState extends ConsumerState<CmpysPlanGenStep>
    with TickerProviderStateMixin {
  late final AnimationController _bob;
  Timer? _poll;
  String _status = 'Designing your blueprint…';
  bool _retrying = false;

  bool get _ready =>
      widget.draft.blueprintMd != null &&
      widget.draft.blueprintMd!.trim().isNotEmpty &&
      !widget.draft.resultsFailed;

  bool get _failed =>
      widget.draft.resultsFailed &&
      (widget.draft.blueprintMd == null ||
          widget.draft.blueprintMd!.trim().isEmpty);

  @override
  void initState() {
    super.initState();
    _bob = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2600),
    )..repeat(reverse: true);
    // The analysis step's stream may still be writing into the draft; poll.
    _poll = Timer.periodic(const Duration(milliseconds: 400), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _bob.dispose();
    _poll?.cancel();
    super.dispose();
  }

  Future<void> _retry() async {
    final sessionId = widget.draft.sessionId;
    if (sessionId == null || _retrying) return;
    setState(() {
      _retrying = true;
      widget.draft.resultsFailed = false;
      _status = 'Reconnecting to ${widget.idol.short}…';
    });
    try {
      final repo = ref.read(sessionRepositoryProvider);
      await streamGenerateResults(
        repo: repo,
        sessionId: sessionId,
        onStatus: (s) {
          if (mounted && s.isNotEmpty) setState(() => _status = s);
        },
        onComparison: (acc) => widget.draft.comparisonMd = acc,
        onBlueprint: (acc) => widget.draft.blueprintMd = acc,
        onPlanJob: (jobId) => widget.draft.planJobId = jobId,
      );
      widget.draft.resultsFailed = false;
    } catch (e) {
      widget.draft.resultsFailed = true;
    } finally {
      if (mounted) setState(() => _retrying = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_ready) return _readyScreen();
    if (_failed && !_retrying) return _errorScreen();
    return _thinkingScreen();
  }

  Widget _errorScreen() {
    return Container(
      decoration: const BoxDecoration(gradient: AppColors.gradInk),
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
                Text(
                  'Your blueprint didn’t come through. Check your connection and try again.',
                  textAlign: TextAlign.center,
                  style: AppTypography.bodyLarge.copyWith(
                      color: Colors.white, fontSize: 16, height: 1.5),
                ),
                const SizedBox(height: 22),
                CmpysButton(
                  variant: CmpysBtnVariant.primary,
                  size: CmpysBtnSize.lg,
                  leadingIcon: Icons.refresh_rounded,
                  onTap: _retry,
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
      decoration: const BoxDecoration(gradient: AppColors.gradInk),
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
                child: Container(
                  width: 84,
                  height: 84,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.08),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(PhosphorIconsBold.signpost,
                      color: AppColors.green, size: 38),
                ),
              ),
              const SizedBox(height: 28),
              Text(
                'BUILDING WITH ${widget.idol.short.toUpperCase()}',
                style: AppTypography.kicker.copyWith(
                  color: Colors.white.withValues(alpha: 0.55),
                ),
              ),
              const SizedBox(height: 18),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.06),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                      color: Colors.white.withValues(alpha: 0.09)),
                ),
                child: Row(
                  children: [
                    const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        valueColor:
                            AlwaysStoppedAnimation<Color>(AppColors.green),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        _status,
                        style: AppTypography.body.copyWith(
                          color: Colors.white.withValues(alpha: 0.88),
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

  Widget _readyScreen() {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(30),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            TweenAnimationBuilder<double>(
              tween: Tween(begin: 0.5, end: 1.0),
              duration: const Duration(milliseconds: 500),
              curve: AppCurves.spring,
              builder: (_, scale, child) =>
                  Transform.scale(scale: scale, child: child),
              child: Container(
                width: 84,
                height: 84,
                decoration: const BoxDecoration(
                  color: AppColors.greenSoft,
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.check_rounded,
                    size: 44, color: AppColors.green),
              ),
            ),
            const SizedBox(height: 26),
            const CmpysKicker('Your blueprint is ready',
                color: AppColors.green),
            const SizedBox(height: 10),
            Text(
              'Written by ${widget.idol.short}, for you.',
              style: AppTypography.display.copyWith(
                  fontSize: 30,
                  fontWeight: FontWeight.w700,
                  letterSpacing: -0.4,
                  height: 1.3),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 300),
              child: Text(
                'Built from your interview — what to work on, in what order, and why.',
                style: AppTypography.bodyDim,
                textAlign: TextAlign.center,
              ),
            ),
            const SizedBox(height: 30),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 300),
              child: CmpysButton(
                variant: CmpysBtnVariant.primary,
                size: CmpysBtnSize.lg,
                full: true,
                trailingIcon: Icons.arrow_forward_rounded,
                onTap: widget.onDone,
                child: const Text('Enter CMPYS'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
