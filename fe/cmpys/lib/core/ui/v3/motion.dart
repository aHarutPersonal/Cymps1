import 'dart:async';

import 'package:flutter/widgets.dart';

import '../../../app/design_tokens.dart';
import '../motion/motion_config.dart';

/// Minimum touch target for every v3 control, in logical points.
const double kV3TapTarget = 44;

/// `.press` from `CMPYS v3.html`: tap-down scales the child to .965 over
/// 160 ms on `--out`, and releases back.
///
/// It also owns the parts every tappable v3 surface shares: a minimum
/// [minTapTarget] hit box (the visual stays centred at its own size),
/// keyboard activation, a focus ring and button semantics. A null [onTap]
/// disables it. With reduced motion the scale is skipped.
class V3Pressable extends StatefulWidget {
  const V3Pressable({
    super.key,
    required this.child,
    required this.onTap,
    this.onLongPress,
    this.pressedScale = 0.965,
    this.minTapTarget = kV3TapTarget,
    this.semanticLabel,
    this.selected,
    this.checked,
    this.inMutuallyExclusiveGroup = false,
    this.button = true,
    this.focusRadius = const BorderRadius.all(Radius.circular(999)),
  });

  final Widget child;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;

  /// Scale while pressed; 1 turns the press feedback off.
  final double pressedScale;

  /// The hit box grows to at least this size in both axes; 0 keeps the
  /// child's own size.
  final double minTapTarget;

  /// Replaces the child's semantics (use for icon-only controls).
  final String? semanticLabel;

  /// Selected state for chips and segments; null leaves it out.
  final bool? selected;

  /// Checked state for toggles such as `V3CheckDot`; null leaves it out.
  final bool? checked;

  /// One of a set where only one can be checked: with [checked] (and
  /// `button: false`) it reads as a radio button.
  final bool inMutuallyExclusiveGroup;

  /// Whether the control reads as a button.
  final bool button;

  /// Shape of the keyboard focus ring around the child.
  final BorderRadius focusRadius;

  @override
  State<V3Pressable> createState() => _V3PressableState();
}

class _V3PressableState extends State<V3Pressable> {
  bool _pressed = false;
  bool _focused = false;

  bool get _enabled => widget.onTap != null || widget.onLongPress != null;

  void _setPressed(bool value) {
    if (_pressed == value) return;
    setState(() => _pressed = value);
  }

  @override
  void didUpdateWidget(V3Pressable oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!_enabled) _pressed = false;
  }

  @override
  Widget build(BuildContext context) {
    final motion = MotionConfig.enabled(context);
    Widget visual = AnimatedScale(
      scale: motion && _pressed ? widget.pressedScale : 1,
      duration: motion ? const Duration(milliseconds: 160) : Duration.zero,
      curve: AppMotion.out,
      // A label replaces the child's own semantics, but not the tap and
      // focus actions contributed by the detectors around it.
      child: ExcludeSemantics(
        excluding: widget.semanticLabel != null,
        child: widget.child,
      ),
    );
    // Always in the tree (only the decoration changes) so gaining focus never
    // remounts the child and resets its state.
    visual = DecoratedBox(
      position: DecorationPosition.foreground,
      decoration: _focused
          ? BoxDecoration(
              border: Border.all(color: AppColors.ember2, width: 2),
              borderRadius: widget.focusRadius,
            )
          : const BoxDecoration(),
      child: visual,
    );
    if (widget.minTapTarget > 0) {
      visual = ConstrainedBox(
        constraints: BoxConstraints(
          minWidth: widget.minTapTarget,
          minHeight: widget.minTapTarget,
        ),
        child: Center(widthFactor: 1, heightFactor: 1, child: visual),
      );
    }

    final gesture = GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: widget.onTap == null ? null : (_) => _setPressed(true),
      onTapUp: widget.onTap == null ? null : (_) => _setPressed(false),
      onTapCancel: widget.onTap == null ? null : () => _setPressed(false),
      onTap: widget.onTap,
      onLongPress: widget.onLongPress,
      child: visual,
    );

    return Semantics(
      container: true,
      button: widget.button,
      enabled: _enabled,
      selected: widget.selected,
      checked: widget.checked,
      inMutuallyExclusiveGroup: widget.inMutuallyExclusiveGroup ? true : null,
      label: widget.semanticLabel,
      child: FocusableActionDetector(
        enabled: widget.onTap != null,
        mouseCursor: _enabled ? SystemMouseCursors.click : MouseCursor.defer,
        actions: <Type, Action<Intent>>{
          ActivateIntent: CallbackAction<ActivateIntent>(
            onInvoke: (_) {
              widget.onTap?.call();
              return null;
            },
          ),
        },
        onShowFocusHighlight: (value) {
          if (_focused != value) setState(() => _focused = value);
        },
        child: gesture,
      ),
    );
  }
}

/// `rise(delay)` from `v3/core.jsx`: fades in while sliding up 14 px over
/// .65 s on `--out`, after [delay]. Hidden until the delay elapses (`both`).
/// With reduced motion the child shows at once.
class V3Rise extends StatefulWidget {
  const V3Rise({
    super.key,
    required this.child,
    this.delay = Duration.zero,
    this.duration = const Duration(milliseconds: 650),
    this.offset = 14,
  });

  final Widget child;
  final Duration delay;
  final Duration duration;

  /// Starting downward offset in logical pixels.
  final double offset;

  @override
  State<V3Rise> createState() => _V3RiseState();
}

class _V3RiseState extends State<V3Rise> with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: widget.duration,
  );
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    if (widget.delay == Duration.zero) {
      _controller.forward();
    } else {
      _timer = Timer(widget.delay, _controller.forward);
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!MotionConfig.enabled(context)) return widget.child;
    return AnimatedBuilder(
      animation: _controller,
      child: widget.child,
      builder: (context, child) {
        final t = AppMotion.out.transform(_controller.value);
        return Opacity(
          opacity: t.clamp(0.0, 1.0),
          child: Transform.translate(
            offset: Offset(0, widget.offset * (1 - t)),
            child: child,
          ),
        );
      },
    );
  }
}

/// `pop` from `CMPYS v3.html`: scale .6 → 1.08 → 1 with a fade-in, on
/// `--spring` (each keyframe leg eased, as CSS does). Plays once when built.
/// With reduced motion the child shows at once.
class V3Pop extends StatefulWidget {
  const V3Pop({
    super.key,
    required this.child,
    this.duration = const Duration(milliseconds: 350),
    this.delay = Duration.zero,
  });

  final Widget child;
  final Duration duration;

  /// Wait before popping (the design's `animation-delay`, fill mode `both`:
  /// hidden at the first keyframe until then). Reduced motion ignores it.
  final Duration delay;

  @override
  State<V3Pop> createState() => _V3PopState();
}

class _V3PopState extends State<V3Pop> with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: widget.duration);
    if (widget.delay == Duration.zero) {
      _controller.forward();
    } else {
      _timer = Timer(widget.delay, _controller.forward);
    }
  }

  static final Animatable<double> _scale = TweenSequence<double>([
    TweenSequenceItem(
      tween: Tween(
        begin: 0.6,
        end: 1.08,
      ).chain(CurveTween(curve: AppMotion.spring)),
      weight: 60,
    ),
    TweenSequenceItem(
      tween: Tween(
        begin: 1.08,
        end: 1.0,
      ).chain(CurveTween(curve: AppMotion.spring)),
      weight: 40,
    ),
  ]);

  static final Animatable<double> _opacity = TweenSequence<double>([
    TweenSequenceItem(
      tween: Tween(
        begin: 0.0,
        end: 1.0,
      ).chain(CurveTween(curve: AppMotion.spring)),
      weight: 60,
    ),
    TweenSequenceItem(tween: ConstantTween(1.0), weight: 40),
  ]);

  @override
  void dispose() {
    _timer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!MotionConfig.enabled(context)) return widget.child;
    return AnimatedBuilder(
      animation: _controller,
      child: widget.child,
      builder: (context, child) => Opacity(
        opacity: _opacity.evaluate(_controller).clamp(0.0, 1.0),
        child: Transform.scale(
          scale: _scale.evaluate(_controller),
          child: child,
        ),
      ),
    );
  }
}
