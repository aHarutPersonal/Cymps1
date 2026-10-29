import 'package:flutter/widgets.dart';

import '../../../app/design_tokens.dart';
import '../motion/motion_config.dart';
import 'motion.dart';
import 'surfaces.dart';
import 'video.dart';

/// `Portrait({withVideo})` from `v3/core.jsx`: the mentor hero with an
/// optional looping video backdrop.
///
/// With a [video] asset and motion on, the video plays behind the hero
/// (Ken Burns `kbIn 12s ease-out`: 1.12 → 1) and, once it plays, a ringed
/// medallion of [image] pops in at left 22 / top 96 (`pop .8s --spring .3s`)
/// over the design's "video" gradient and grain.
///
/// Until the video plays, if it can't, without a [video], or with reduced
/// motion, it is exactly today's duotone [V3Portrait].
///
/// [child] is laid over everything (use [Positioned] / [Align]).
class V3VideoPortrait extends StatefulWidget {
  const V3VideoPortrait({
    super.key,
    this.image,
    this.video,
    this.height = 320,
    this.radius = 0,
    this.tone = AppColors.iris,
    this.child,
  });

  /// Key on the ringed medallion (present only while the video plays).
  static const medallionKey = ValueKey<String>('v3-video-portrait-medallion');

  final ImageProvider? image;

  /// A bundled video asset (`AppAssets.video*`); null keeps the duotone
  /// portrait.
  final String? video;
  final double height;
  final double radius;
  final Color tone;
  final Widget? child;

  @override
  State<V3VideoPortrait> createState() => _V3VideoPortraitState();
}

// `linear-gradient(180deg, rgba(14,12,20,.45) 0%, rgba(14,12,20,.05) 30%,
// rgba(14,12,20,.35) 60%, rgba(14,12,20,.97) 100%)`.
const LinearGradient _videoShade = LinearGradient(
  begin: Alignment.topCenter,
  end: Alignment.bottomCenter,
  colors: [
    Color(0x730E0C14),
    Color(0x0D0E0C14),
    Color(0x590E0C14),
    Color(0xF70E0C14),
  ],
  stops: [0, 0.3, 0.6, 1],
);

class _V3VideoPortraitState extends State<V3VideoPortrait> {
  bool _playing = false;

  @override
  void didUpdateWidget(V3VideoPortrait oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.video != widget.video) _playing = false;
  }

  @override
  Widget build(BuildContext context) {
    final video = widget.video;
    final duotone = V3Portrait(
      image: widget.image,
      height: widget.height,
      tone: widget.tone,
    );
    if (video == null || !MotionConfig.enabled(context)) {
      return V3Portrait(
        image: widget.image,
        height: widget.height,
        radius: widget.radius,
        tone: widget.tone,
        child: widget.child,
      );
    }
    return ClipRRect(
      borderRadius: BorderRadius.circular(widget.radius),
      child: SizedBox(
        height: widget.height,
        width: double.infinity,
        child: ColoredBox(
          color: AppColors.night,
          child: Stack(
            fit: StackFit.expand,
            children: [
              V3LoopVideo(
                asset: video,
                fallback: duotone,
                initialScale: 1.12,
                scale: 1,
                scaleDuration: const Duration(seconds: 12),
                scaleCurve: Curves.easeOut,
                onReady: (ok) {
                  if (mounted && ok != _playing) {
                    setState(() => _playing = ok);
                  }
                },
              ),
              if (_playing) ...[
                const IgnorePointer(
                  child: DecoratedBox(
                    decoration: BoxDecoration(gradient: _videoShade),
                  ),
                ),
                const V3Grain(),
                Positioned(
                  left: 22,
                  top: 96,
                  child: V3Pop(
                    duration: const Duration(milliseconds: 800),
                    delay: const Duration(milliseconds: 300),
                    child: _Medallion(
                      key: V3VideoPortrait.medallionKey,
                      image: widget.image,
                    ),
                  ),
                ),
              ],
              ?widget.child,
            ],
          ),
        ),
      ),
    );
  }
}

// CSS `grayscale(1) contrast(1.1)`: rgb' = 1.1 · Y − .05 (× 255).
const List<double> _medallionMatrix = [
  1.1 * 0.2126, 1.1 * 0.7152, 1.1 * 0.0722, 0, -12.75, //
  1.1 * 0.2126, 1.1 * 0.7152, 1.1 * 0.0722, 0, -12.75,
  1.1 * 0.2126, 1.1 * 0.7152, 1.1 * 0.0722, 0, -12.75,
  0, 0, 0, 1, 0,
];

/// 92 pt ring (`conic-gradient(from 200deg, ember, gold, iris, ember)`,
/// padding 3) around the grayscale portrait with a 3 pt night border, and
/// `0 16px 40px -10px rgba(0,0,0,.6)` under it.
class _Medallion extends StatelessWidget {
  const _Medallion({super.key, required this.image});

  final ImageProvider? image;

  @override
  Widget build(BuildContext context) {
    final image = this.image;
    return Container(
      width: 92,
      height: 92,
      padding: const EdgeInsets.all(3),
      decoration: const BoxDecoration(
        shape: BoxShape.circle,
        // CSS conic angles start at 12 o'clock, Flutter's sweep at 3.
        gradient: SweepGradient(
          colors: [
            AppColors.ember,
            AppColors.gold,
            AppColors.iris,
            AppColors.ember,
          ],
          transform: GradientRotation((200 - 90) * 3.141592653589793 / 180),
        ),
        boxShadow: [
          BoxShadow(
            color: Color(0x99000000),
            offset: Offset(0, 16),
            blurRadius: 40,
            spreadRadius: -10,
          ),
        ],
      ),
      child: DecoratedBox(
        position: DecorationPosition.foreground,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(color: AppColors.night, width: 3),
        ),
        child: ClipOval(
          child: ColoredBox(
            color: AppColors.night,
            child: image == null
                ? const SizedBox.expand()
                : ColorFiltered(
                    colorFilter: const ColorFilter.matrix(_medallionMatrix),
                    child: Image(
                      image: image,
                      fit: BoxFit.cover,
                      width: double.infinity,
                      height: double.infinity,
                      excludeFromSemantics: true,
                      errorBuilder: (context, error, stack) =>
                          const SizedBox.shrink(),
                    ),
                  ),
          ),
        ),
      ),
    );
  }
}
