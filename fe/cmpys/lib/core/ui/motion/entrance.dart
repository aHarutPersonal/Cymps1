import 'package:flutter/widgets.dart';
import 'package:flutter_animate/flutter_animate.dart';

import '../../../app/design_tokens.dart';
import 'motion_config.dart';

/// Marks the "visit window" for a subtree of [Entrance] widgets.
///
/// Wrap a screen's scrollable body (the widget whose children are
/// [EntranceGroup.wrap]'d) in one [EntranceScope]. Its [State] records the
/// wall-clock time of its first build; any [Entrance] mounted later looks
/// this timestamp up via [EntranceScope.maybeOf] to decide whether the
/// screen is still in its initial reveal or has been visible for a while.
///
/// Without this, a conditional list that changes shape on an
/// already-visible screen (e.g. a hint banner appearing, a toggle swapping
/// sections) causes newly-inflated trailing children to replay the full
/// fade/slide entrance — a visible "blink out, wait, fade back in" even
/// though the screen itself never left. [Entrance] consults the scope to
/// skip that replay once the visit window has elapsed.
class EntranceScope extends StatefulWidget {
  const EntranceScope({
    super.key,
    this.visitWindow = const Duration(milliseconds: 700),
    required this.child,
  });

  /// How long after the scope's first build an [Entrance] should still be
  /// allowed to animate. Defaults to ~700ms — one full cascade (6 × 50ms
  /// stagger + 300ms fade) plus a small margin. Injectable for tests.
  final Duration visitWindow;

  final Widget child;

  /// Looks up the nearest [EntranceScope]'s first-build timestamp and visit
  /// window, if any. Returns null when there is no ancestor scope.
  static ({DateTime firstBuiltAt, Duration visitWindow})? maybeOf(BuildContext context) {
    final scope = context.getInheritedWidgetOfExactType<_EntranceScopeMarker>();
    if (scope == null) return null;
    return (firstBuiltAt: scope.firstBuiltAt, visitWindow: scope.visitWindow);
  }

  @override
  State<EntranceScope> createState() => _EntranceScopeState();
}

class _EntranceScopeState extends State<EntranceScope> {
  late final DateTime _firstBuiltAt = DateTime.now();

  @override
  Widget build(BuildContext context) {
    return _EntranceScopeMarker(
      firstBuiltAt: _firstBuiltAt,
      visitWindow: widget.visitWindow,
      child: widget.child,
    );
  }
}

class _EntranceScopeMarker extends InheritedWidget {
  const _EntranceScopeMarker({
    required this.firstBuiltAt,
    required this.visitWindow,
    required super.child,
  });

  final DateTime firstBuiltAt;
  final Duration visitWindow;

  @override
  bool updateShouldNotify(_EntranceScopeMarker oldWidget) =>
      firstBuiltAt != oldWidget.firstBuiltAt || visitWindow != oldWidget.visitWindow;
}

/// Fade + 12px slide-up entrance for one child.
///
/// Plays once per screen visit — the animation runs when the element is
/// first built and never re-triggers on rebuilds. Under reduced motion the
/// slide is dropped and only the fade remains.
///
/// If mounted inside an [EntranceScope] whose visit window has already
/// elapsed (i.e. the screen has been visible for a while and this child is
/// appearing because a conditional list changed shape, not because the
/// screen itself just appeared), the entrance is skipped entirely and the
/// child renders statically.
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
  bool _checkedVisitWindow = false;

  /// Looked up on first build (via [EntranceScope.maybeOf], an
  /// InheritedWidget lookup) rather than [initState] — `context` isn't
  /// wired up to the widget tree yet when [initState] runs.
  void _checkVisitWindowOnce(BuildContext context) {
    if (_checkedVisitWindow) return;
    _checkedVisitWindow = true;
    final scope = EntranceScope.maybeOf(context);
    if (scope == null) return;
    final elapsed = DateTime.now().difference(scope.firstBuiltAt);
    if (elapsed > scope.visitWindow) _played = true;
  }

  @override
  Widget build(BuildContext context) {
    _checkVisitWindowOnce(context);
    // A late-mounted child (list-shape change well after the screen's visit
    // window) swaps straight to the bare child — no re-inflate-and-animate.
    // This re-inflates the child subtree fresh each time, which is fine for
    // stateless cards; don't put child-held State under Entrance.
    if (_played) return widget.child;

    final motionEnabled = MotionConfig.enabled(context);
    final delay = motionEnabled ? Entrance.delayFor(widget.index) : Duration.zero;

    final animated = widget.child.animate(
      delay: delay,
      onComplete: (_) {
        if (mounted) setState(() => _played = true);
      },
    )..fadeIn(duration: AppDurations.normal, curve: AppCurves.easeOut);

    if (motionEnabled) {
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
  /// Bare spacers (a [SizedBox] with no child) pass through unwrapped and
  /// don't consume a stagger index, so visible cards stay ~50ms apart
  /// regardless of how many spacers separate them.
  static bool _isBareSpacer(Widget child) => child is SizedBox && child.child == null;

  static List<Widget> wrap(List<Widget> children) {
    var index = 0;
    return [
      for (final child in children)
        if (_isBareSpacer(child)) child else Entrance(index: index++, child: child),
    ];
  }
}
