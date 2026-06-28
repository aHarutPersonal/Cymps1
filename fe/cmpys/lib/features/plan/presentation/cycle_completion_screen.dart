import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../../app/design_tokens.dart';
import '../../../core/ui/cmpys/cmpys_primitives.dart';
import '../../cmpys/state/cmpys_store.dart';
import '../data/plan_repository.dart';
import '../models/plan_models.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Repo interface — pure, no Flutter dependency.
// ─────────────────────────────────────────────────────────────────────────────

/// Minimal interface consumed by [CycleCompletionPresenter].
/// [PlanRepository] satisfies this interface — pass an instance directly.
abstract class CycleCompletionRepo {
  Future<({String narrative, String? capstoneTitle})> fetchCycleSummary(
      String id);
  Future<String> generateNext(String id);
}

// ─────────────────────────────────────────────────────────────────────────────
// Pure presenter — no Flutter dependency, fully unit-testable.
// ─────────────────────────────────────────────────────────────────────────────

class CycleCompletionPresenter {
  CycleCompletionPresenter({
    required this.planId,
    required this.repo,
    required this.onJobId,
  });

  final String planId;
  final CycleCompletionRepo repo;

  /// Called with the new generation job id when [startNextCycle] succeeds.
  final void Function(String jobId) onJobId;

  String narrative = '';
  String? capstoneTitle;

  /// Loads the cycle summary from the repo into [narrative] / [capstoneTitle].
  Future<void> start() async {
    final s = await repo.fetchCycleSummary(planId);
    narrative = s.narrative;
    capstoneTitle = s.capstoneTitle;
  }

  /// Enqueues the next 12-week plan cycle, forwards the job id to [onJobId],
  /// and returns it. A non-empty job id is required for the polling path.
  Future<String> startNextCycle() async {
    final job = await repo.generateNext(planId);
    if (job.isNotEmpty) onJobId(job);
    return job;
  }
}

/// Thin adapter so [PlanRepository] satisfies [CycleCompletionRepo] without
/// a circular import (repo is in data/, interface is in presentation/).
class _PlanRepoBridge implements CycleCompletionRepo {
  const _PlanRepoBridge(this._repo);
  final PlanRepository _repo;

  @override
  Future<({String narrative, String? capstoneTitle})> fetchCycleSummary(
          String id) =>
      _repo.fetchCycleSummary(id);

  @override
  Future<String> generateNext(String id) => _repo.generateNext(id);
}

// ─────────────────────────────────────────────────────────────────────────────
// Public entry-point
// ─────────────────────────────────────────────────────────────────────────────

/// Show the cycle-completion recap sheet for [plan].
///
/// Loads the narrative + optional capstone title from the backend via
/// [PlanRepository.fetchCycleSummary], then presents a CTA —
/// "Start your next 12 weeks" — which calls [generateNext] and forwards the
/// returned job id to [cmpysStoreProvider].setPlanJobId so the existing
/// polling path in [CurrentPlanController] drives the new cycle.
Future<void> showCycleCompletion(
  BuildContext context, {
  required BackendPlan plan,
  required WidgetRef ref,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: AppColors.paper,
    barrierColor: const Color(0x6B16161C),
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(26)),
    ),
    builder: (ctx) => _CycleCompletionBody(plan: plan, ref: ref),
  );
}

// ─────────────────────────────────────────────────────────────────────────────
// Widget
// ─────────────────────────────────────────────────────────────────────────────

class _CycleCompletionBody extends StatefulWidget {
  const _CycleCompletionBody({required this.plan, required this.ref});

  final BackendPlan plan;
  final WidgetRef ref;

  @override
  State<_CycleCompletionBody> createState() => _CycleCompletionBodyState();
}

class _CycleCompletionBodyState extends State<_CycleCompletionBody> {
  late final CycleCompletionPresenter _presenter;
  bool _loading = true;
  bool _starting = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    final repoInstance = widget.ref.read(planRepositoryProvider);
    _presenter = CycleCompletionPresenter(
      planId: widget.plan.id,
      repo: _PlanRepoBridge(repoInstance),
      onJobId: (jobId) {
        widget.ref.read(cmpysStoreProvider.notifier).setPlanJobId(jobId);
      },
    );
    _load();
  }

  Future<void> _load() async {
    try {
      await _presenter.start();
      if (!mounted) return;
      setState(() => _loading = false);
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'Couldn\'t load your cycle summary. Please try again.';
      });
    }
  }

  Future<void> _startNextCycle() async {
    if (_starting) return;
    setState(() => _starting = true);
    try {
      await _presenter.startNextCycle();
      if (!mounted) return;
      Navigator.of(context).pop();
    } catch (_) {
      if (!mounted) return;
      showCmpysToast(
        context,
        'Couldn\'t start your next cycle — try again.',
        icon: Icons.error_outline_rounded,
        tone: AppColors.ink2,
      );
      setState(() => _starting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Container(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.92,
        ),
        padding: const EdgeInsets.fromLTRB(18, 10, 18, 34),
        child: _loading
            ? _loadingView()
            : _error != null
                ? _errorView()
                : _content(),
      ),
    );
  }

  Widget _loadingView() {
    return const Padding(
      padding: EdgeInsets.symmetric(vertical: 48),
      child: Center(
        child: SizedBox(
          width: 22,
          height: 22,
          child: CircularProgressIndicator(
            strokeWidth: 2,
            valueColor: AlwaysStoppedAnimation<Color>(AppColors.green),
          ),
        ),
      ),
    );
  }

  Widget _errorView() {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _dragHandle(),
          const Icon(Icons.wifi_off_rounded, size: 32, color: AppColors.ink3),
          const SizedBox(height: 14),
          Text(_error!, textAlign: TextAlign.center, style: AppTypography.bodyDim),
          const SizedBox(height: 18),
          CmpysButton(
            variant: CmpysBtnVariant.primary,
            size: CmpysBtnSize.md,
            leadingIcon: Icons.refresh_rounded,
            onTap: () {
              setState(() {
                _loading = true;
                _error = null;
              });
              _load();
            },
            child: const Text('Try again'),
          ),
        ],
      ),
    );
  }

  Widget _dragHandle() {
    return Center(
      child: Container(
        width: 40,
        height: 5,
        margin: const EdgeInsets.only(bottom: 16, top: 4),
        decoration: BoxDecoration(
          color: AppColors.hair2,
          borderRadius: BorderRadius.circular(999),
        ),
      ),
    );
  }

  Widget _content() {
    final cycleLabel = widget.plan.cycleNumber > 1
        ? 'Cycle ${widget.plan.cycleNumber} complete'
        : 'You finished your first 12 weeks';

    return SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _dragHandle(),

          // Icon badge
          Container(
            width: 52,
            height: 52,
            decoration: const BoxDecoration(
              color: AppColors.greenSoft,
              shape: BoxShape.circle,
            ),
            alignment: Alignment.center,
            child: const Icon(
              PhosphorIconsFill.medalMilitary,
              size: 26,
              color: AppColors.green,
            ),
          ),
          const SizedBox(height: 14),

          CmpysKicker(cycleLabel),
          const SizedBox(height: 6),
          Text(
            'Recap',
            style: AppTypography.h2,
          ),
          const SizedBox(height: 20),

          // Narrative card
          if (_presenter.narrative.isNotEmpty) ...[
            CmpysCardSurface(
              pad: const EdgeInsets.all(16),
              child: Text(
                _presenter.narrative,
                style: AppTypography.body.copyWith(height: 1.6),
              ),
            ),
            const SizedBox(height: 14),
          ],

          // Capstone title
          if (_presenter.capstoneTitle != null &&
              _presenter.capstoneTitle!.isNotEmpty) ...[
            CmpysCardSurface(
              color: AppColors.greenSoft,
              border: false,
              pad: const EdgeInsets.all(16),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(PhosphorIconsFill.trophy,
                      size: 18, color: AppColors.green),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Capstone achievement',
                          style: AppTypography.caption
                              .copyWith(color: AppColors.green2, fontSize: 11),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          _presenter.capstoneTitle!,
                          style: AppTypography.bodyMedium
                              .copyWith(fontSize: 14, height: 1.4),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),
          ],

          const SizedBox(height: 8),

          // CTA
          CmpysButton(
            variant: CmpysBtnVariant.primary,
            size: CmpysBtnSize.lg,
            full: true,
            disabled: _starting,
            leadingIcon: Icons.arrow_forward_rounded,
            onTap: _startNextCycle,
            child: Text(_starting
                ? 'Starting your next cycle…'
                : 'Start your next 12 weeks'),
          ),
          const SizedBox(height: 10),
          CmpysButton(
            variant: CmpysBtnVariant.ghost,
            size: CmpysBtnSize.md,
            full: true,
            onTap: () => Navigator.of(context).pop(),
            child: const Text('Close for now'),
          ),
        ],
      ),
    );
  }
}
