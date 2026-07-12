import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../../../app/design_tokens.dart';
import '../../../../core/ui/cmpys/cmpys_primitives.dart';
import '../../../plan/data/plan_repository.dart';
import '../../../session/data/session_repository.dart';
import '../../data/cmpys_seed.dart';
import 'results_streamer.dart';

/// Post-interview transition that runs the complete results pipeline while the
/// user explores concise, truthful explanations of what CMPYS is building.
///
/// Comparison and blueprint are generated first because they are required
/// strategic inputs to the plan. The staged plan job is then dispatched and
/// polled until the actual 12-week plan is persisted. Entry is enabled only at
/// that point—never after an arbitrary animation or fixed delay.
class CmpysMentorLabStep extends ConsumerStatefulWidget {
  const CmpysMentorLabStep({
    super.key,
    required this.idol,
    required this.draft,
    required this.onDone,
  });

  final CmpysIdol idol;
  final CmpysOnboardingDraft draft;
  final VoidCallback onDone;

  @override
  ConsumerState<CmpysMentorLabStep> createState() => _CmpysMentorLabStepState();
}

class _CmpysMentorLabStepState extends ConsumerState<CmpysMentorLabStep> {
  final PageController _cards = PageController(viewportFraction: 0.88);
  Timer? _cardTimer;
  Timer? _jobTimer;

  int _cardIndex = 0;
  int _progress = 6;
  String _status = 'Organizing what you shared…';
  String? _error;
  String? _pollingJobId;
  bool _checkingJob = false;
  bool _starting = false;
  bool _jobCompleted = false;
  bool _planReady = false;

  static const _benefits = <_MentorBenefit>[
    _MentorBenefit(
      icon: PhosphorIconsRegular.chatCenteredText,
      eyebrow: 'YOUR WORDS BECOME INPUTS',
      title: 'The interview is not a personality quiz.',
      body:
          'Your answers become constraints for the plan: what you want, where you are starting, how much time you can commit, and which obstacles keep repeating. CMPYS uses that context to choose priorities instead of handing everyone the same checklist.',
      proof: 'Personalized from this conversation—not a generic template.',
    ),
    _MentorBenefit(
      icon: PhosphorIconsRegular.path,
      eyebrow: 'MENTOR AS A DECISION LENS',
      title: 'Learn the pattern, not the costume.',
      body:
          'The goal is not to imitate your mentor’s life literally. CMPYS studies relevant decisions, principles, and milestones, then translates those patterns into actions that fit your age, resources, interests, and current goal.',
      proof:
          'Evidence informs the direction; your reality determines the action.',
    ),
    _MentorBenefit(
      icon: PhosphorIconsRegular.numberCircleOne,
      eyebrow: 'ONE WEEK AT A TIME',
      title: 'Focus is part of the product—not a suggestion.',
      body:
          'You receive a complete twelve-week path, but only the current week asks for attention. Finish its mission and the next week unlocks. That keeps the roadmap visible without turning future work into today’s distraction.',
      proof: 'Sequential unlocking protects attention and momentum.',
    ),
    _MentorBenefit(
      icon: PhosphorIconsRegular.bookOpenText,
      eyebrow: 'TEACH, THEN PRACTICE',
      title: 'A lesson should change what you can do.',
      body:
          'Mission lessons combine a substantial explanation, a worked example, likely failure modes, a knowledge check, and guided practice. The target is an honest 40–60 minute learning session—not two minutes of motivational text.',
      proof: 'Deep lessons are paired with a concrete output or decision.',
    ),
    _MentorBenefit(
      icon: PhosphorIconsRegular.repeat,
      eyebrow: 'DAILY RHYTHM, ZERO GUILT',
      title: 'Small repetition supports the mission.',
      body:
          'Daily habits and practices reset every day. They help you rehearse the week’s skill, but they never permanently block the next week. Mission completion advances the plan; daily rhythm builds consistency around it.',
      proof: 'Daily work supports progression—it does not hold it hostage.',
    ),
    _MentorBenefit(
      icon: PhosphorIconsRegular.checkCircle,
      eyebrow: 'PROGRESS YOU CAN PROVE',
      title: 'Every mission ends with observable evidence.',
      body:
          'CMPYS favors binary success criteria: something shipped, written, practiced, explained, or measured. Completed missions can become achievements, giving future comparisons and plans a stronger picture of what you have actually built.',
      proof: 'The plan tracks outputs, not vague feelings of productivity.',
    ),
  ];

  @override
  void initState() {
    super.initState();
    _cardTimer = Timer.periodic(const Duration(seconds: 9), (_) {
      if (!mounted || !_cards.hasClients) return;
      final next = (_cardIndex + 1) % _benefits.length;
      _cards.animateToPage(
        next,
        duration: const Duration(milliseconds: 420),
        curve: Curves.easeOutCubic,
      );
    });
    _startPipeline();
  }

  @override
  void dispose() {
    _cardTimer?.cancel();
    _jobTimer?.cancel();
    _cards.dispose();
    super.dispose();
  }

  void _setStage(String status, int progress) {
    if (!mounted || _planReady) return;
    final nextProgress = progress > _progress ? progress : _progress;
    if (_status == status && _progress == nextProgress) return;
    setState(() {
      _status = status;
      _progress = nextProgress;
    });
  }

  Future<void> _startPipeline() async {
    final sessionId = widget.draft.sessionId;
    if (sessionId == null || _starting) {
      if (sessionId == null && mounted) {
        setState(() => _error = 'No active session. Go back and try again.');
      }
      return;
    }

    _jobTimer?.cancel();
    _pollingJobId = null;
    setState(() {
      _starting = true;
      _jobCompleted = false;
      _planReady = false;
      _error = null;
      _progress = 6;
      _status = 'Organizing what you shared…';
      widget.draft.resultsFailed = false;
    });

    try {
      await streamGenerateResults(
        repo: ref.read(sessionRepositoryProvider),
        sessionId: sessionId,
        onSection: (section) {
          if (section == 'comparison') {
            _setStage('Mapping you against ${widget.idol.short}…', 14);
          } else if (section == 'blueprint') {
            _setStage('Turning the comparison into a strategy…', 42);
          }
        },
        onComparison: (value) {
          widget.draft.comparisonMd = value;
          _markReadyIfComplete();
          if (value.isNotEmpty && _progress < 34) {
            _setStage('Your comparison is taking shape…', 34);
          }
        },
        onBlueprint: (value) {
          widget.draft.blueprintMd = value;
          _markReadyIfComplete();
          if (value.isNotEmpty && _progress < 58) {
            _setStage('Your strategic blueprint is taking shape…', 58);
          }
        },
        onPlanJob: (jobId) {
          widget.draft.planJobId = jobId;
          _startJobPolling(jobId);
        },
      );
      widget.draft.resultsFailed = false;
      _markReadyIfComplete();
      final jobId = widget.draft.planJobId;
      if (jobId == null || jobId.isEmpty) {
        throw StateError('The plan job was not created.');
      }
      if (!_planReady) {
        _setStage('Building your twelve-week plan…', 62);
        _startJobPolling(jobId);
      }
    } catch (e) {
      widget.draft.resultsFailed = true;
      _jobTimer?.cancel();
      if (!mounted) return;
      setState(() {
        _error =
            'The mentor lab was interrupted. Your interview is saved—retry to continue from the last completed stage.';
      });
    } finally {
      if (mounted) setState(() => _starting = false);
    }
  }

  void _startJobPolling(String jobId) {
    if (_planReady || (_pollingJobId == jobId && _jobTimer != null)) return;
    _jobTimer?.cancel();
    _pollingJobId = jobId;
    _checkPlanJob(jobId);
    _jobTimer = Timer.periodic(
      const Duration(seconds: 3),
      (_) => _checkPlanJob(jobId),
    );
  }

  Future<void> _checkPlanJob(String jobId) async {
    if (_checkingJob || !mounted || _planReady) return;
    _checkingJob = true;
    try {
      final job = await ref.read(planRepositoryProvider).getJobStatus(jobId);
      if (!mounted || _pollingJobId != jobId) return;
      if (job.isCompleted) {
        _jobCompleted = true;
        _markReadyIfComplete();
        if (!_planReady) {
          _setStage('Finalizing your mentor brief…', 99);
        }
      } else if (job.isFailed) {
        _jobTimer?.cancel();
        setState(() {
          _error =
              'Your comparison is safe, but the plan could not finish. Retry to restart only the missing work.';
        });
      } else if (job.progressPercent > 0) {
        final mapped = 62 + (job.progressPercent * 0.37).round();
        _setStage(
          job.thinkingLine?.trim().isNotEmpty == true
              ? job.thinkingLine!.trim()
              : 'Building your twelve-week plan…',
          mapped.clamp(62, 99),
        );
      }
    } catch (_) {
      // A transient poll failure should not discard a healthy generation
      // stream. The next timer tick retries; the pipeline request itself owns
      // the visible terminal error state.
    } finally {
      _checkingJob = false;
    }
  }

  void _markReadyIfComplete() {
    if (!mounted || !_jobCompleted || _planReady) return;
    final comparisonReady =
        widget.draft.comparisonMd?.trim().isNotEmpty == true;
    final blueprintReady = widget.draft.blueprintMd?.trim().isNotEmpty == true;
    if (!comparisonReady || !blueprintReady) return;
    _jobTimer?.cancel();
    setState(() {
      _planReady = true;
      _progress = 100;
      _status = 'Your plan is ready.';
      _error = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(gradient: AppColors.gradInk),
      child: SafeArea(
        child: Column(
          children: [
            _header(),
            Expanded(
              child: NotificationListener<ScrollStartNotification>(
                onNotification: (notification) {
                  if (notification.dragDetails != null) _cardTimer?.cancel();
                  return false;
                },
                child: PageView.builder(
                  controller: _cards,
                  itemCount: _benefits.length,
                  onPageChanged: (index) => setState(() => _cardIndex = index),
                  itemBuilder: (_, index) =>
                      _benefitCard(_benefits[index], index),
                ),
              ),
            ),
            _pageDots(),
            _footer(),
          ],
        ),
      ),
    );
  }

  Widget _header() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(22, 18, 22, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              CmpysMentorAvatar(
                slug: widget.idol.slug,
                initials: widget.idol.initials,
                color: widget.idol.color,
                tint: Colors.white,
                size: 44,
                border: Border.all(color: Colors.white.withValues(alpha: 0.4)),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'THE MENTOR LAB',
                      style: AppTypography.kicker.copyWith(
                        color: AppColors.green,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      _status,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: AppTypography.bodyMedium.copyWith(
                        color: Colors.white,
                        fontSize: 14,
                      ),
                    ),
                  ],
                ),
              ),
              Text(
                '$_progress%',
                style: AppTypography.captionMedium.copyWith(
                  color: Colors.white,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
          const SizedBox(height: 13),
          ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: LinearProgressIndicator(
              key: const Key('mentor-lab-progress'),
              value: _progress / 100,
              minHeight: 6,
              backgroundColor: Colors.white.withValues(alpha: 0.12),
              valueColor: AlwaysStoppedAnimation<Color>(
                _planReady ? AppColors.green : AppColors.ochre,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _benefitCard(_MentorBenefit benefit, int index) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(6, 10, 6, 12),
      child: Container(
        decoration: BoxDecoration(
          color: AppColors.card,
          borderRadius: BorderRadius.circular(28),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.22),
              blurRadius: 24,
              offset: const Offset(0, 12),
            ),
          ],
        ),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 48,
                    height: 48,
                    alignment: Alignment.center,
                    decoration: const BoxDecoration(
                      color: AppColors.greenSoft,
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      benefit.icon,
                      color: AppColors.green2,
                      size: 23,
                    ),
                  ),
                  const Spacer(),
                  Text(
                    '${index + 1}/${_benefits.length}',
                    style: AppTypography.caption.copyWith(
                      color: AppColors.ink3,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 24),
              Text(
                benefit.eyebrow,
                style: AppTypography.kicker.copyWith(color: AppColors.green2),
              ),
              const SizedBox(height: 9),
              Text(
                benefit.title,
                style: AppTypography.h2.copyWith(
                  fontSize: 25,
                  letterSpacing: -0.35,
                  height: 1.2,
                ),
              ),
              const SizedBox(height: 14),
              Text(
                benefit.body,
                style: AppTypography.body.copyWith(fontSize: 15, height: 1.58),
              ),
              const SizedBox(height: 20),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(15),
                decoration: BoxDecoration(
                  color: AppColors.paper2,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(
                      PhosphorIconsRegular.sparkle,
                      size: 17,
                      color: AppColors.ochre2,
                    ),
                    const SizedBox(width: 9),
                    Expanded(
                      child: Text(
                        benefit.proof,
                        style: AppTypography.captionMedium.copyWith(
                          color: AppColors.ink2,
                          fontSize: 13,
                          height: 1.4,
                        ),
                      ),
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

  Widget _pageDots() {
    return Padding(
      padding: const EdgeInsets.only(top: 2, bottom: 10),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          for (var index = 0; index < _benefits.length; index++)
            AnimatedContainer(
              duration: const Duration(milliseconds: 220),
              width: index == _cardIndex ? 20 : 6,
              height: 6,
              margin: const EdgeInsets.symmetric(horizontal: 3),
              decoration: BoxDecoration(
                color: index == _cardIndex
                    ? AppColors.green
                    : Colors.white.withValues(alpha: 0.24),
                borderRadius: BorderRadius.circular(999),
              ),
            ),
        ],
      ),
    );
  }

  Widget _footer() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(22, 0, 22, 18),
      child: _error != null
          ? Column(
              children: [
                Text(
                  _error!,
                  textAlign: TextAlign.center,
                  style: AppTypography.caption.copyWith(
                    color: Colors.white.withValues(alpha: 0.72),
                    height: 1.4,
                  ),
                ),
                const SizedBox(height: 10),
                CmpysButton(
                  key: const Key('mentor-lab-retry'),
                  variant: CmpysBtnVariant.primary,
                  size: CmpysBtnSize.lg,
                  full: true,
                  disabled: _starting,
                  leadingIcon: Icons.refresh_rounded,
                  onTap: _startPipeline,
                  child: Text(
                    _starting ? 'Restarting…' : 'Continue generation',
                  ),
                ),
              ],
            )
          : CmpysButton(
              key: const Key('mentor-lab-enter'),
              variant: _planReady
                  ? CmpysBtnVariant.primary
                  : CmpysBtnVariant.dark,
              size: CmpysBtnSize.lg,
              full: true,
              disabled: !_planReady,
              trailingIcon: _planReady ? Icons.arrow_forward_rounded : null,
              onTap: _planReady ? widget.onDone : null,
              child: Text(
                _planReady ? 'Enter CMPYS' : 'Your plan is building…',
              ),
            ),
    );
  }
}

class _MentorBenefit {
  const _MentorBenefit({
    required this.icon,
    required this.eyebrow,
    required this.title,
    required this.body,
    required this.proof,
  });

  final IconData icon;
  final String eyebrow;
  final String title;
  final String body;
  final String proof;
}
