import 'dart:async';

import 'package:flutter/widgets.dart';

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
  static ({DateTime firstBuiltAt, Duration visitWindow})? maybeOf(
    BuildContext context,
  ) {
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
      firstBuiltAt != oldWidget.firstBuiltAt ||
      visitWindow != oldWidget.visitWindow;
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
    return _StableReveal(
      skip: _played,
      delay: Entrance.delayFor(widget.index),
      duration: AppDurations.normal,
      distance: 12,
      fadeWhenReduced: true,
      child: widget.child,
    );
  }
}

/// A short one-time reveal for content produced by a user interaction.
/// Reduced-motion users see the child immediately with no transition.
class FeedbackReveal extends StatelessWidget {
  const FeedbackReveal({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) =>
      _StableReveal(duration: AppDurations.fast, distance: 8, child: child);
}

/// Keep the same element hierarchy through completion and preference changes.
/// Removing effect wrappers would dispose stateful children, including editors.
class _StableReveal extends StatefulWidget {
  const _StableReveal({
    required this.duration,
    required this.distance,
    required this.child,
    this.delay = Duration.zero,
    this.skip = false,
    this.fadeWhenReduced = false,
  });

  final Duration duration;
  final Duration delay;
  final double distance;
  final bool skip;
  final bool fadeWhenReduced;
  final Widget child;

  @override
  State<_StableReveal> createState() => _StableRevealState();
}

class _StableRevealState extends State<_StableReveal>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _fade;
  Timer? _delay;
  bool _started = false;
  bool _motionEnabled = true;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: widget.duration);
    _fade = _controller.drive(CurveTween(curve: AppCurves.easeOut));
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _motionEnabled = MotionConfig.enabled(context);
    if (!_started) {
      _started = true;
      if (widget.skip || (!_motionEnabled && !widget.fadeWhenReduced)) {
        _controller.value = 1;
      } else if (_motionEnabled && widget.delay > Duration.zero) {
        _delay = Timer(widget.delay, () => _controller.forward());
      } else {
        _controller.forward();
      }
    } else if (!_motionEnabled) {
      // Enabling reduced motion also finishes a pending stagger immediately.
      _delay?.cancel();
      _controller.value = 1;
    }
  }

  @override
  void dispose() {
    _delay?.cancel();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: _fade,
    builder: (context, child) => FadeTransition(
      opacity: _fade,
      child: Transform.translate(
        offset: Offset(
          0,
          _motionEnabled ? widget.distance * (1 - _fade.value) : 0,
        ),
        child: child,
      ),
    ),
    child: widget.child,
  );
}

/// Wraps a screen's top-level children in a staggered entrance cascade.
abstract final class EntranceGroup {
  /// Bare spacers (a [SizedBox] with no child) pass through unwrapped and
  /// don't consume a stagger index, so visible cards stay ~50ms apart
  /// regardless of how many spacers separate them.
  static bool _isBareSpacer(Widget child) =>
      child is SizedBox && child.child == null;

  static List<Widget> wrap(List<Widget> children) {
    var index = 0;
    return [
      for (final child in children)
        if (_isBareSpacer(child))
          child
        else
          Entrance(index: index++, child: child),
    ];
  }
}
