import 'package:flutter/widgets.dart';
import 'package:flutter_animate/flutter_animate.dart';

import '../../../app/design_tokens.dart';
import 'motion_config.dart';

/// Fade + 12px slide-up entrance for one child.
///
/// Plays once per screen visit — the animation runs when the element is
/// first built and never re-triggers on rebuilds. Under reduced motion the
/// slide is dropped and only the fade remains.
class Entrance extends StatefulWidget {
  const Entrance({super.key, this.index = 0, required this.child});

  /// Position in an [EntranceGroup] cascade.
  final int index;
  final Widget child;

  /// Items beyond this index animate together (no extra delay), so long
  /// lists never feel sluggish.
  static const int maxStagger = 6;

  static Duration delayFor(int index) =>
      AppDurations.stagger * index.clamp(0, maxStagger);

  @override
  State<Entrance> createState() => _EntranceState();
}

class _EntranceState extends State<Entrance> {
  bool _played = false;

  @override
  Widget build(BuildContext context) {
    if (_played) return widget.child;

    final animated = widget.child.animate(
      delay: Entrance.delayFor(widget.index),
      onComplete: (_) {
        if (mounted) setState(() => _played = true);
      },
    )..fadeIn(duration: AppDurations.normal, curve: AppCurves.easeOut);

    if (MotionConfig.enabled(context)) {
      animated.move(
        begin: const Offset(0, 12),
        end: Offset.zero,
        duration: AppDurations.normal,
        curve: AppCurves.easeOut,
      );
    }
    return animated;
  }
}

/// Wraps a screen's top-level children in a staggered entrance cascade.
abstract final class EntranceGroup {
  static List<Widget> wrap(List<Widget> children) => [
        for (var i = 0; i < children.length; i++)
          Entrance(index: i, child: children[i]),
      ];
}
