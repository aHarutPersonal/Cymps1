import 'dart:ui' show lerpDouble;

import 'package:flutter/material.dart' show Material, MaterialType;
import 'package:flutter/widgets.dart';

import '../../../app/design_tokens.dart';
import '../motion/motion_config.dart';

/// `Expand` from `v3/core.jsx` as a page route: a full-screen layer that opens
/// by clipping out from the tapped card's rect, and closes back into it.
///
/// - **Open:** the page is laid out at full size from the first frame and
///   revealed through `inset(...) round 24` growing to the whole screen over
///   .6 s on `--io` (`AppMotion.io`), corner radius 24 → 0.
/// - **Close:** `Navigator.pop` plays the same clip in reverse, back into the
///   card.
/// - **Reduced motion:** the page fades in and out instead (same duration).
/// - The page sits on a [background] `Material` (night by default), so its
///   text gets a proper default style. While it animates the route is not
///   opaque, so the page below stays visible around the clip.
///
/// Measure the card with [rectOf] when it is tapped:
///
/// ```dart
/// Builder(builder: (context) => V3Pressable(
///   onTap: () => Navigator.of(context).push(V3ExpandRoute<void>(
///     from: V3ExpandRoute.rectOf(context),
///     builder: (_) => const MyPreview(),
///   )),
///   child: card,
/// ))
/// ```
///
/// A null [from] opens from a band across the middle of the screen, as the
/// design does when it has no source rect.
class V3ExpandRoute<T> extends PageRoute<T> {
  V3ExpandRoute({
    required this.builder,
    this.from,
    this.background = AppColors.night,
    super.settings,
  });

  /// Builds the page. It is laid out at the full size of the navigator.
  final WidgetBuilder builder;

  /// The card's rect in the navigator's coordinates (see [rectOf]).
  final Rect? from;

  /// Fill behind the page (the design's `bg`).
  final Color background;

  /// Open and close duration.
  static const Duration duration = Duration(milliseconds: 600);

  /// Corner radius of the clip at the card.
  static const double cardRadius = 24;

  /// Key on the clipping widget (for tests).
  static const Key clipKey = Key('v3-expand-clip');

  /// Key on the fade used under reduced motion (for tests).
  static const Key fadeKey = Key('v3-expand-fade');

  /// The rect of the widget behind [context] in the nearest [Navigator]'s
  /// coordinates (the design's `rectIn`), or null before it has been laid out.
  static Rect? rectOf(BuildContext context) {
    final box = context.findRenderObject();
    final navigator = Navigator.maybeOf(context)?.context.findRenderObject();
    if (box is! RenderBox || navigator is! RenderBox) return null;
    if (!box.attached || !box.hasSize || !navigator.attached) return null;
    return box.localToGlobal(Offset.zero, ancestor: navigator) & box.size;
  }

  @override
  Duration get transitionDuration => duration;

  @override
  Duration get reverseTransitionDuration => duration;

  @override
  bool get maintainState => true;

  @override
  bool get barrierDismissible => false;

  @override
  Color? get barrierColor => null;

  @override
  String? get barrierLabel => null;

  @override
  Widget buildPage(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
  ) {
    return Material(
      type: MaterialType.canvas,
      color: background,
      child: builder(context),
    );
  }

  @override
  Widget buildTransitions(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    if (!MotionConfig.enabled(context)) {
      return FadeTransition(
        key: fadeKey,
        opacity: animation.drive(CurveTween(curve: AppMotion.out)),
        child: child,
      );
    }
    final t = animation.drive(CurveTween(curve: AppMotion.io));
    return AnimatedBuilder(
      animation: t,
      child: child,
      builder: (context, child) => ClipRRect(
        key: clipKey,
        clipper: _ExpandClipper(from: from, t: t.value),
        child: child,
      ),
    );
  }
}

/// The design's `inset(top right bottom left round r)`: the rect and the
/// radius are interpolated linearly, like CSS does between two `inset()`s.
class _ExpandClipper extends CustomClipper<RRect> {
  const _ExpandClipper({required this.from, required this.t});

  final Rect? from;
  final double t;

  @override
  RRect getClip(Size size) {
    final full = Offset.zero & size;
    // The design's fallback `{ top: 300, left: 20, right: 20, bottom: 300 }`.
    final start =
        from ??
        Rect.fromCenter(
          center: full.center,
          width: size.width - 40,
          height: 274,
        );
    final rect = Rect.lerp(start, full, t)!;
    final radius = lerpDouble(V3ExpandRoute.cardRadius, 0, t)!;
    return RRect.fromRectAndRadius(rect, Radius.circular(radius));
  }

  @override
  bool shouldReclip(_ExpandClipper old) => old.t != t || old.from != from;
}
