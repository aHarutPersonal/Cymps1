import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../../../app/design_tokens.dart';
import '../../../../core/ui/app_shell.dart';
import '../../../../core/ui/cmpys/cmpys_primitives.dart';
import '../../data/cmpys_seed.dart';

/// CMPYS video lesson — design-faithful UI with mock playback state.
///
/// The real-asset playback path lives in `features/plans/.../plan_video_screen`;
/// this screen mirrors the prototype's editorial frame, chapters list, and
/// auto-complete-on-finish behaviour for the in-app design tour.
class CmpysVideoLessonScreen extends StatefulWidget {
  const CmpysVideoLessonScreen({super.key, required this.video});
  final CmpysVideoInfo video;

  @override
  State<CmpysVideoLessonScreen> createState() => _CmpysVideoLessonScreenState();
}

class _CmpysVideoLessonScreenState extends State<CmpysVideoLessonScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctl;
  bool _playing = true;
  bool _finished = false;

  @override
  void initState() {
    super.initState();
    final secs = widget.video.minutes * 60;
    _ctl = AnimationController(
      vsync: this,
      duration: Duration(seconds: secs.clamp(9, 60)),
    )..addStatusListener((s) {
        if (s == AnimationStatus.completed && !_finished) {
          setState(() {
            _finished = true;
            _playing = false;
          });
          showCmpysToast(context, 'Marked as watched',
              icon: Icons.check_rounded, tone: AppColors.green);
        }
      });
    _ctl.forward();
  }

  @override
  void dispose() {
    _ctl.dispose();
    super.dispose();
  }

  void _toggle() {
    setState(() {
      _playing = !_playing;
      if (_playing) {
        _ctl.forward();
      } else {
        _ctl.stop();
      }
    });
  }

  String _fmt(double pct) {
    final totalSecs = _ctl.duration?.inSeconds ?? 0;
    final cur = (totalSecs * pct).round();
    final m = (cur ~/ 60).toString().padLeft(1, '0');
    final s = (cur % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  String _fmtTotal() {
    final totalSecs = _ctl.duration?.inSeconds ?? 0;
    final m = (totalSecs ~/ 60).toString().padLeft(1, '0');
    final s = (totalSecs % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.paper,
      body: SafeArea(
        child: Column(
          children: [
            _topBar(),
            _player(),
            Expanded(child: _details()),
          ],
        ),
      ),
    );
  }

  Widget _topBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
      child: Row(
        children: [
          Material(
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
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              widget.video.channel.toUpperCase(),
              style: AppTypography.kicker,
            ),
          ),
        ],
      ),
    );
  }

  Widget _player() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 18),
      child: AspectRatio(
        aspectRatio: 16 / 9,
        child: Container(
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            color: AppColors.blkInk,
            borderRadius: AppRadii.card,
          ),
          child: Stack(
            children: [
              const DecoratedBox(
                decoration: BoxDecoration(gradient: AppColors.gradInk),
              ),
              Center(
                child: GestureDetector(
                  onTap: _toggle,
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 220),
                    width: 64,
                    height: 64,
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.18),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      _playing ? Icons.pause_rounded : Icons.play_arrow_rounded,
                      color: Colors.white,
                      size: 32,
                    ),
                  ),
                ),
              ),
              // Bottom scrubber
              Positioned(
                left: 14,
                right: 14,
                bottom: 12,
                child: AnimatedBuilder(
                  animation: _ctl,
                  builder: (_, _) {
                    return Column(
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              _fmt(_ctl.value),
                              style: AppTypography.kicker.copyWith(
                                color: Colors.white.withValues(alpha: 0.85),
                                fontSize: 11,
                              ),
                            ),
                            Text(
                              _fmtTotal(),
                              style: AppTypography.kicker.copyWith(
                                color: Colors.white.withValues(alpha: 0.85),
                                fontSize: 11,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        SizedBox(
                          height: 4,
                          child: Stack(
                            alignment: Alignment.centerLeft,
                            children: [
                              Container(
                                decoration: BoxDecoration(
                                  color: Colors.white.withValues(alpha: 0.22),
                                  borderRadius: BorderRadius.circular(999),
                                ),
                              ),
                              FractionallySizedBox(
                                widthFactor: _ctl.value,
                                child: Container(
                                  decoration: BoxDecoration(
                                    color: AppColors.green,
                                    borderRadius: BorderRadius.circular(999),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _details() {
    return SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(22, 18, 22, AppShell.bottomNavClearance(context)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            widget.video.title,
            style: AppTypography.h2.copyWith(
              fontSize: 22,
              letterSpacing: -0.3,
              height: 1.16,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            widget.video.desc,
            style: AppTypography.bodyDim.copyWith(fontSize: 14.5),
          ),
          const SizedBox(height: 22),
          const CmpysKicker('Chapters'),
          const SizedBox(height: 10),
          for (var i = 0; i < widget.video.chapters.length; i++)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: CmpysCardSurface(
                pad: const EdgeInsets.fromLTRB(14, 12, 14, 12),
                onTap: () {},
                child: Row(
                  children: [
                    Container(
                      width: 32,
                      height: 32,
                      decoration: BoxDecoration(
                        color: AppColors.greenSoft,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      alignment: Alignment.center,
                      child: Text(
                        '${i + 1}',
                        style: AppTypography.label.copyWith(
                          color: AppColors.green2,
                          fontSize: 13,
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        widget.video.chapters[i],
                        style:
                            AppTypography.bodyMedium.copyWith(fontSize: 14.5),
                      ),
                    ),
                    const Icon(PhosphorIconsRegular.play,
                        color: AppColors.ink3, size: 16),
                  ],
                ),
              ),
            ),
          if (_finished) ...[
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: BoxDecoration(
                color: AppColors.greenSoft,
                borderRadius: BorderRadius.circular(14),
              ),
              child: Row(
                children: [
                  const Icon(Icons.check_circle_rounded,
                      color: AppColors.green, size: 18),
                  const SizedBox(width: 8),
                  Text(
                    'You finished this lesson.',
                    style: AppTypography.captionMedium.copyWith(
                      color: AppColors.green2,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}
