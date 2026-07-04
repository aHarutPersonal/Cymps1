import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../app/design_tokens.dart';
import 'motion_config.dart';

/// Shared fade-through page transition — the CMPYS navigation language.
///
/// Incoming content fades in while sliding up slightly; under reduced
/// motion only the fade remains. Exposed for go_router ([page]) and for
/// imperative pushes ([CmpysPageRoute]); modal entry screens use the
/// bottom-sheet-style [CmpysSheetRoute] instead.
abstract final class CmpysPageTransition {
  static const Duration duration = AppDurations.normal;

  static Widget buildTransition(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    final curved = CurvedAnimation(parent: animation, curve: AppCurves.easeOut);
    final fade = FadeTransition(opacity: curved, child: child);
    // Reduced motion intentionally keeps the 300ms duration (fade-only, no
    // slide) per adjudication — only the motion path is removed, not the
    // timing.
    if (!MotionConfig.enabled(context)) return fade;
    return SlideTransition(
      position: Tween<Offset>(
        begin: const Offset(0, 0.02), // ~16px on a typical phone height
        end: Offset.zero,
      ).animate(curved),
      child: fade,
    );
  }

  /// go_router page with the shared fade-through transition.
  static CustomTransitionPage<T> page<T>({
    required Widget child,
    LocalKey? key,
  }) {
    return CustomTransitionPage<T>(
      key: key,
      child: child,
      transitionDuration: duration,
      reverseTransitionDuration: duration,
      transitionsBuilder: buildTransition,
    );
  }
}

/// Fade-through route for imperative detail pushes (replaces
/// MaterialPageRoute across the app).
class CmpysPageRoute<T> extends PageRouteBuilder<T> {
  CmpysPageRoute({required WidgetBuilder builder})
      : super(
          transitionDuration: CmpysPageTransition.duration,
          reverseTransitionDuration: CmpysPageTransition.duration,
          pageBuilder: (context, animation, secondaryAnimation) =>
              builder(context),
          transitionsBuilder: CmpysPageTransition.buildTransition,
        );
}

/// Bottom-sheet-style slide-up route for modal entry screens (Record).
class CmpysSheetRoute<T> extends PageRouteBuilder<T> {
  CmpysSheetRoute({required WidgetBuilder builder})
      : super(
          transitionDuration: CmpysPageTransition.duration,
          reverseTransitionDuration: CmpysPageTransition.duration,
          pageBuilder: (context, animation, secondaryAnimation) =>
              builder(context),
          transitionsBuilder: (context, animation, secondaryAnimation, child) {
            final curved =
                CurvedAnimation(parent: animation, curve: AppCurves.easeOut);
            if (!MotionConfig.enabled(context)) {
              return FadeTransition(opacity: curved, child: child);
            }
            return SlideTransition(
              position: Tween<Offset>(
                begin: const Offset(0, 1),
                end: Offset.zero,
              ).animate(curved),
              child: child,
            );
          },
        );
}
