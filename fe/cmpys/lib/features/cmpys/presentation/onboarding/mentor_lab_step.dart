import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../../../app/design_tokens.dart';
import '../../../../core/network/api_error.dart';
import '../../../../core/ui/cmpys/cmpys_primitives.dart';
import '../../../../core/ui/motion/motion_config.dart';
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

class _CmpysMentorLabStepState extends ConsumerState<CmpysMentorLabStep>
    with WidgetsBindingObserver {
  final PageController _cards = PageController();
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
  bool _jobFailed = false;
  bool _resultsComplete = false;
  int _pollFailures = 0;
  int _attempt = 0;

  static const _cardsContent = <_MentorLabCard>[
    _MentorLabCard.voice(
      eyebrow: 'WHY ROLE MODELS WORK',
      speaker: 'Seneca',
      descriptor: 'Stoic philosopher · Letter 11, c. 63 AD',
      quote:
          '“Choose a master whose life, conversation, and soul-expressing face have satisfied you; picture him always to yourself as your protector or your pattern.”',
      takeaway:
          'A role model gives you a standard to measure decisions against—not a life to copy blindly.',
      portraitAsset: 'assets/images/voices/seneca.jpg',
      source: 'Moral Letters to Lucilius, Letter 11',
    ),
    _MentorLabCard.voice(
      eyebrow: 'LEARNING IS CUMULATIVE',
      speaker: 'Isaac Newton',
      descriptor: 'Mathematician & physicist · 1676',
      quote:
          '“If I have seen further it is by standing on the shoulders of Giants.”',
      takeaway:
          'Progress starts by studying what great people already discovered, then building beyond it in your own context.',
      portraitAsset: 'assets/images/voices/isaac_newton.jpg',
      source: 'Letter to Robert Hooke, 5 February 1676',
    ),
    _MentorLabCard.voice(
      eyebrow: 'CHOOSE YOUR HEROES CAREFULLY',
      speaker: 'Warren Buffett',
      descriptor: 'Investor · Columbia Business School, 2015',
      quote:
          '“Be careful how you choose your heroes because that’s how you’re going to turn out.”',
      takeaway:
          'Choose heroes for character, not fame. The behavior you admire and study quietly becomes your own standard.',
      portraitAsset: 'assets/images/voices/warren_buffett.jpg',
      source: 'Columbia Business School, “Fast Forward,” 2015',
      portraitContain: true,
    ),
  ];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _resultsComplete =
        !widget.draft.resultsFailed &&
        widget.draft.comparisonMd?.trim().isNotEmpty == true &&
        widget.draft.blueprintMd?.trim().isNotEmpty == true;
    _cardTimer = Timer.periodic(const Duration(seconds: 18), (_) {
      if (!mounted ||
          !_cards.hasClients ||
          _error != null ||
          _planReady ||
          !MotionConfig.enabled(context)) {
        return;
      }
      final next = (_cardIndex + 1) % _cardsContent.length;
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
    WidgetsBinding.instance.removeObserver(this);
    _cardTimer?.cancel();
    _jobTimer?.cancel();
    _cards.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      final jobId = _pollingJobId;
      if (jobId != null && !_planReady && !_jobFailed) {
        _startJobPolling(jobId, reconnect: true);
      }
    }
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
    _jobTimer = null;
    _pollingJobId = null;
    final attempt = ++_attempt;
    final savedJob = widget.draft.planJobId;
    final recoverPlan =
        _resultsComplete &&
        (_jobFailed || savedJob == null || savedJob.isEmpty);
    var requestStage = 'results';
    setState(() {
      _starting = true;
      _jobCompleted = false;
      _planReady = false;
      _error = null;
      _pollFailures = 0;
      _jobFailed = false;
      // A failed attempt may have reached a later stage than its valid saved
      // work. Start at the confirmed results boundary; the next server status
      // restores any further progress that actually survived the retry.
      _progress = _resultsComplete ? 62 : 6;
      _status = recoverPlan
          ? 'Reconnecting to your saved session…'
          : 'Organizing what you shared…';
      widget.draft.resultsFailed = false;
    });

    try {
      if (recoverPlan) {
        requestStage = 'saved_session';
        var idolId = widget.draft.backendIdolId;
        var targetAge = widget.draft.age;
        if (idolId == null || idolId.isEmpty) {
          // Older drafts may not retain the server mentor identity. New
          // restores and intake completion already have it, so restarting a
          // failed plan does not depend on another session read.
          final session = await ref
              .read(sessionRepositoryProvider)
              .getSession(sessionId);
          if (!mounted || attempt != _attempt) return;
          idolId = session.selectedIdol?.id;
          targetAge = session.userAge;
          widget.draft.backendIdolId = idolId;
        }
        if (idolId == null || idolId.isEmpty) {
          throw StateError('Missing mentor');
        }
        requestStage = 'plan_restart';
        _setStage('Restarting the unfinished plan steps…', 62);
        final jobId = await ref
            .read(planRepositoryProvider)
            .generatePlan(
              idolId: idolId,
              targetAge: targetAge,
              sessionId: sessionId,
            );
        if (!mounted || attempt != _attempt) return;
        if (jobId.isEmpty) throw StateError('Missing plan job');
        widget.draft.planJobId = jobId;
        _setStage('Continuing your saved plan…', 62);
        _startJobPolling(jobId);
        return;
      }
      if (_resultsComplete && savedJob?.isNotEmpty == true) {
        _setStage('Checking your saved plan…', 62);
        _startJobPolling(savedJob!);
        return;
      }
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
      if (!mounted || attempt != _attempt) return;
      _resultsComplete = true;
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
      if (!mounted || attempt != _attempt || _planReady) return;
      // Log only diagnostic metadata, never the session, answers, response
      // body, or credentials. A server error during the saved-session lookup
      // must be distinguishable from a plan dispatch failure.
      debugPrint(
        'Mentor lab request failed: stage=$requestStage type=${e.runtimeType}'
        '${e is ApiError ? ' status=${e.statusCode} code=${e.code}' : ''}',
      );
      widget.draft.resultsFailed = true;
      // A running plan remains recoverable even if the results connection
      // closes. Do not discard its polling handle.
      if (recoverPlan) _jobFailed = true;
      setState(() {
        _error = switch (requestStage) {
          'saved_session' =>
            'Your saved session couldn’t be loaded. Your answers are safe. Try again.',
          'plan_restart' =>
            'Your plan couldn’t restart. Your progress is saved. Try again.',
          _ =>
            'Your answers are saved. Reconnect to continue from the last completed step.',
        };
      });
    } finally {
      if (mounted) setState(() => _starting = false);
    }
  }

  void _startJobPolling(String jobId, {bool reconnect = false}) {
    if (_planReady ||
        (!reconnect &&
            _pollingJobId == jobId &&
            (_jobTimer?.isActive ?? false))) {
      return;
    }
    _jobTimer?.cancel();
    _pollingJobId = jobId;
    _jobTimer = Timer.periodic(
      const Duration(seconds: 3),
      (_) => _checkPlanJob(jobId),
    );
    _checkPlanJob(jobId);
  }

  Future<void> _checkPlanJob(String jobId) async {
    if (_checkingJob || !mounted || _planReady) return;
    _checkingJob = true;
    try {
      final job = await ref.read(planRepositoryProvider).getJobStatus(jobId);
      if (!mounted || _pollingJobId != jobId) return;
      if (_pollFailures > 0) {
        _pollFailures = 0;
        setState(() => _error = null);
      }
      if (job.isCompleted) {
        _jobCompleted = true;
        _markReadyIfComplete();
        if (!_planReady) {
          _setStage('Finalizing your mentor brief…', 99);
        }
      } else if (job.isFailed) {
        _jobTimer?.cancel();
        _jobTimer = null;
        _jobFailed = true;
        setState(() {
          _error = 'Your plan paused. Continue to retry the unfinished steps.';
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
    } catch (error) {
      if (!mounted || _pollingJobId != jobId) return;
      _pollFailures++;
      if (error is ApiError && error.statusCode == 404) {
        _jobTimer?.cancel();
        _jobTimer = null;
        _jobFailed = true;
        setState(
          () => _error =
              'Your saved plan needs to be reconnected. Your answers are safe.',
        );
      } else if (_pollFailures >= 3) {
        _jobTimer?.cancel();
        _jobTimer = null;
        setState(
          () => _error =
              'We can’t check your plan right now. Check your connection and continue.',
        );
      }
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
    _jobTimer = null;
    setState(() {
      _planReady = true;
      _progress = 100;
      _status = 'Your roadmap is ready. Lessons are preparing.';
      _error = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.dark,
      child: Material(
        color: AppColors.paper,
        child: SafeArea(
          child: Column(
            children: [
              Expanded(
                child: SingleChildScrollView(
                  key: const Key('mentor-lab-content'),
                  padding: const EdgeInsets.fromLTRB(22, 18, 22, 24),
                  child: Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 520),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _header(),
                          const SizedBox(height: 26),
                          _preparationStatus(),
                          const SizedBox(height: 22),
                          _perspectiveNavigation(),
                          const SizedBox(height: 10),
                          LayoutBuilder(
                            builder: (context, constraints) => SizedBox(
                              height: _perspectiveHeight(constraints.maxWidth),
                              child:
                                  NotificationListener<ScrollStartNotification>(
                                    onNotification: (notification) {
                                      if (notification.dragDetails != null) {
                                        _cardTimer?.cancel();
                                      }
                                      return false;
                                    },
                                    child: PageView.builder(
                                      controller: _cards,
                                      itemCount: _cardsContent.length,
                                      onPageChanged: (index) =>
                                          setState(() => _cardIndex = index),
                                      itemBuilder: (_, index) =>
                                          _voiceCard(_cardsContent[index]),
                                    ),
                                  ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
              ConstrainedBox(
                constraints: BoxConstraints(
                  maxHeight: MediaQuery.sizeOf(context).height * 0.38,
                ),
                child: SingleChildScrollView(child: _footer()),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _header() {
    return Row(
      children: [
        CmpysMentorAvatar(
          slug: widget.idol.slug,
          initials: widget.idol.initials,
          color: AppColors.green2,
          tint: AppColors.card,
          size: 42,
          border: Border.all(color: AppColors.hair2),
        ),
        const SizedBox(width: 11),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'YOUR MENTOR',
                style: AppTypography.monoLabel.copyWith(
                  fontSize: 9,
                  letterSpacing: 1.3,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                widget.idol.name,
                style: AppTypography.bodyMedium.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 12),
        Container(width: 29, height: 2, color: AppColors.ochre2),
      ],
    );
  }

  Widget _preparationStatus() {
    final paused = _error != null;
    final largeText = MediaQuery.textScalerOf(context).scale(14) > 19;
    final status = paused
        ? _jobFailed
              ? 'Plan paused. Your progress is saved.'
              : 'Connection interrupted. Your progress is saved.'
        : _status;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          largeText
              ? _planReady
                    ? 'Your plan\nis ready.'
                    : paused
                    ? 'Progress\nsaved.'
                    : 'Preparing\nyour plan.'
              : _planReady
              ? 'Your next chapter\nis ready.'
              : paused
              ? 'Pick up where\nyou left off.'
              : 'Your plan,\ntaking shape.',
          style: AppTypography.display.copyWith(
            fontSize: largeText ? 26 : 34,
            height: 1.08,
            letterSpacing: -1.0,
          ),
        ),
        const SizedBox(height: 15),
        Semantics(
          liveRegion: true,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Icon(
                  paused
                      ? Icons.pause_circle_outline_rounded
                      : _planReady
                      ? Icons.check_circle_outline_rounded
                      : Icons.auto_awesome_outlined,
                  key: paused ? const Key('mentor-lab-paused') : null,
                  size: 17,
                  color: paused ? AppColors.ochre2 : AppColors.green2,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  status,
                  style: AppTypography.captionMedium.copyWith(
                    color: AppColors.ink2,
                    height: 1.45,
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 13),
        ClipRRect(
          borderRadius: BorderRadius.circular(999),
          child: LinearProgressIndicator(
            key: const Key('mentor-lab-progress'),
            value: _progress / 100,
            // Progress comes from completed pipeline milestones, not elapsed
            // time. Keep the actual phase more prominent than a percentage.
            semanticsLabel: paused
                ? 'Saved progress, preparation paused'
                : 'Plan preparation: $_status',
            semanticsValue: _planReady
                ? 'Ready'
                : paused
                ? 'Paused'
                : 'In progress',
            minHeight: 4,
            backgroundColor: AppColors.hair2,
            valueColor: AlwaysStoppedAnimation<Color>(
              paused ? AppColors.ink3 : AppColors.green2,
            ),
          ),
        ),
        const SizedBox(height: 9),
        Text(
          '12 weeks · Focused lessons · Practical work',
          style: AppTypography.caption.copyWith(fontSize: 11.5),
        ),
      ],
    );
  }

  void _showPerspective(int index) {
    _cardTimer?.cancel();
    final next = (index + _cardsContent.length) % _cardsContent.length;
    if (MotionConfig.enabled(context)) {
      _cards.animateToPage(
        next,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOutCubic,
      );
    } else {
      _cards.jumpToPage(next);
    }
  }

  Widget _perspectiveNavigation() {
    return Row(
      children: [
        Expanded(
          child: Text(
            'ON LEARNING FROM OTHERS',
            style: AppTypography.monoLabel.copyWith(
              fontSize: 9,
              letterSpacing: 0.7,
            ),
          ),
        ),
        const SizedBox(width: 8),
        Text(
          '${(_cardIndex + 1).toString().padLeft(2, '0')} / 03',
          style: AppTypography.monoLabel.copyWith(fontSize: 10),
        ),
        const SizedBox(width: 3),
        IconButton(
          tooltip: 'Previous perspective',
          onPressed: () => _showPerspective(_cardIndex - 1),
          icon: const Icon(Icons.chevron_left_rounded, size: 20),
          color: AppColors.ink2,
          visualDensity: VisualDensity.compact,
        ),
        IconButton(
          tooltip: 'Next perspective',
          onPressed: () => _showPerspective(_cardIndex + 1),
          icon: const Icon(Icons.chevron_right_rounded, size: 20),
          color: AppColors.ink2,
          visualDensity: VisualDensity.compact,
        ),
      ],
    );
  }

  TextStyle get _quoteStyle => AppTypography.ideaCardBody.copyWith(
    fontSize: 21,
    fontWeight: FontWeight.w500,
    fontStyle: FontStyle.normal,
    height: 1.4,
    color: AppColors.ink,
  );
  TextStyle get _speakerStyle => AppTypography.display.copyWith(
    fontSize: 23,
    height: 1.1,
    letterSpacing: -0.4,
  );
  TextStyle get _sourceStyle => AppTypography.caption.copyWith(
    fontSize: 10.5,
    height: 1.4,
    color: AppColors.ink3,
  );
  TextStyle get _descriptorStyle => AppTypography.caption.copyWith(
    fontSize: 11,
    height: 1.4,
    color: AppColors.ink2,
  );

  // Keep the three perspectives the same height without a large empty panel.
  // Measure their actual typography so large text remains fully scrollable.
  double _perspectiveHeight(double width) {
    double measure(String text, TextStyle style, double availableWidth) {
      final painter = TextPainter(
        text: TextSpan(text: text, style: style),
        textScaler: MediaQuery.textScalerOf(context),
        textDirection: Directionality.of(context),
      )..layout(maxWidth: availableWidth.clamp(1, double.infinity));
      final height = painter.height;
      painter.dispose();
      return height;
    }

    // Two pixels of horizontal page margin plus border/padding on both sides.
    final contentWidth = width - 42;
    var height = 0.0;
    for (final voice in _cardsContent) {
      final identityHeight =
          measure(voice.speaker, _speakerStyle, contentWidth - 98) +
          7 +
          measure(voice.descriptor, _descriptorStyle, contentWidth - 98);
      final candidate =
          40 +
          identityHeight.clamp(88, double.infinity) +
          18 +
          measure(voice.quote, _quoteStyle, contentWidth) +
          18 +
          1 +
          12 +
          measure('Source: ${voice.source}', _sourceStyle, contentWidth - 21);
      if (candidate > height) height = candidate;
    }
    return height.ceilToDouble() + 4;
  }

  Widget _voiceCard(_MentorLabCard voice) {
    return Container(
      key: Key('mentor-lab-perspective-${voice.speaker}'),
      margin: const EdgeInsets.symmetric(horizontal: 1),
      padding: const EdgeInsets.all(19),
      decoration: BoxDecoration(
        color: AppColors.card,
        border: Border.all(color: AppColors.hair2.withValues(alpha: 0.75)),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(voice.speaker, style: _speakerStyle),
                    const SizedBox(height: 7),
                    Text(voice.descriptor, style: _descriptorStyle),
                  ],
                ),
              ),
              const SizedBox(width: 16),
              Semantics(
                key: Key('mentor-voice-${voice.speaker}'),
                label: 'Portrait of ${voice.speaker}',
                image: true,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: ColoredBox(
                    color: AppColors.paper2,
                    child: Image.asset(
                      voice.portraitAsset,
                      width: 82,
                      height: 88,
                      fit: voice.portraitContain
                          ? BoxFit.contain
                          : BoxFit.cover,
                      alignment: Alignment.topCenter,
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          Text(voice.quote, style: _quoteStyle),
          const Spacer(),
          const SizedBox(height: 18),
          const Divider(height: 1, thickness: 1, color: AppColors.hair),
          const SizedBox(height: 12),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(
                PhosphorIconsRegular.bookOpenText,
                size: 14,
                color: AppColors.ochre2,
              ),
              const SizedBox(width: 7),
              Expanded(
                child: Text('Source: ${voice.source}', style: _sourceStyle),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _footer() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(22, 14, 22, 16),
      decoration: const BoxDecoration(
        color: AppColors.paper,
        border: Border(top: BorderSide(color: AppColors.hair2)),
      ),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: _error != null
              ? Column(
                  children: [
                    Text(
                      _error!,
                      textAlign: TextAlign.center,
                      style: AppTypography.caption.copyWith(
                        color: AppColors.ink2,
                        height: 1.4,
                      ),
                    ),
                    const SizedBox(height: 12),
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
                  variant: CmpysBtnVariant.primary,
                  size: CmpysBtnSize.lg,
                  full: true,
                  disabled: !_planReady,
                  trailingIcon: _planReady ? Icons.arrow_forward_rounded : null,
                  onTap: _planReady ? widget.onDone : null,
                  child: Text(
                    _planReady ? 'Enter CMPYS' : 'Your plan is building…',
                  ),
                ),
        ),
      ),
    );
  }
}

class _MentorLabCard {
  const _MentorLabCard.voice({
    required this.eyebrow,
    required this.speaker,
    required this.descriptor,
    required this.quote,
    required this.takeaway,
    required this.portraitAsset,
    required this.source,
    this.portraitContain = false,
  });

  final String eyebrow,
      speaker,
      descriptor,
      quote,
      takeaway,
      portraitAsset,
      source;
  final bool portraitContain;
}
