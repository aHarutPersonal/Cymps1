import 'dart:math' as math;

import 'package:flutter/widgets.dart';

import '../../motion/motion_config.dart';

/// The design's `useInView(ref, threshold)`: [builder] gets `visible: false`
/// until [threshold] of the child (or of the viewport, for a child taller
/// than it) is inside the enclosing [Scrollable], then `true` for good.
/// Outside a scroll view, or with reduced motion, it starts visible so blocks
/// render their end state.
///
/// Visibility is checked on scroll and after every frame drawn while the
/// child is still hidden, so a layout shift with no scroll (a text-size
/// change, an image collapsing above) also reveals it. The post-frame check
/// never requests a frame itself, so an idle screen stays idle.
class LessonInView extends StatefulWidget {
  const LessonInView({super.key, required this.builder, this.threshold = .35});

  final Widget Function(BuildContext context, bool visible) builder;
  final double threshold;

  @override
  State<LessonInView> createState() => _LessonInViewState();
}

class _LessonInViewState extends State<LessonInView> {
  bool _visible = false;
  ScrollableState? _scrollable;
  ScrollPosition? _position;
  bool _checkScheduled = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_visible) return;
    final scrollable = Scrollable.maybeOf(context);
    if (!MotionConfig.enabled(context) || scrollable == null) {
      _visible = true;
      _detach();
      return;
    }
    _scrollable = scrollable;
    if (scrollable.position != _position) {
      _position?.removeListener(_check);
      _position = scrollable.position..addListener(_check);
    }
    _scheduleCheck();
  }

  @override
  void didUpdateWidget(LessonInView oldWidget) {
    super.didUpdateWidget(oldWidget);
    _scheduleCheck();
  }

  void _detach() {
    _position?.removeListener(_check);
    _position = null;
    _scrollable = null;
  }

  @override
  void dispose() {
    _detach();
    super.dispose();
  }

  /// Re-checks after the next frame, and after each later frame until the
  /// child is visible.
  void _scheduleCheck() {
    if (_visible || _checkScheduled) return;
    _checkScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _checkScheduled = false;
      if (!mounted || _visible) return;
      _check();
      _scheduleCheck();
    });
  }

  void _check() {
    if (_visible || !mounted) return;
    final box = context.findRenderObject();
    // The scrollable cached in didChangeDependencies: no inherited lookup
    // from inside the scroll listener.
    final viewport = _scrollable?.context.findRenderObject();
    if (box is! RenderBox || !box.attached || !box.hasSize) return;
    if (viewport is! RenderBox || !viewport.attached || !viewport.hasSize) {
      return;
    }
    final top = box.localToGlobal(Offset.zero).dy;
    final viewTop = viewport.localToGlobal(Offset.zero).dy;
    final viewBottom = viewTop + viewport.size.height;
    final height = box.size.height;
    final shown = math.min(top + height, viewBottom) - math.max(top, viewTop);
    if (shown <= 0) return;
    if (height == 0 ||
        shown / height >= widget.threshold ||
        shown >= viewport.size.height * widget.threshold) {
      _detach();
      setState(() => _visible = true);
    }
  }

  @override
  Widget build(BuildContext context) => widget.builder(context, _visible);
}
