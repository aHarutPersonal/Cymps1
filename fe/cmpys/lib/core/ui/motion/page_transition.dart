import 'package:flutter/material.dart';

import '../../../app/design_tokens.dart';
import 'motion_config.dart';

/// Shared navigation for declarative pages and imperative detail pushes.
/// Mobile routes preserve platform gestures; desktop uses a subtle fade-through.
/// Modal entry screens use the bottom-sheet-style [CmpysSheetRoute].
abstract final class CmpysPageTransition {
  static const Duration duration = AppDurations.normal;

  static Widget buildTransition(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    final curved = CurveTween(curve: AppCurves.easeOut).animate(animation);
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

  /// Declarative routes use the same native back gestures as detail pushes.
  static Page<T> page<T>({required Widget child, LocalKey? key}) =>
      _CmpysPage<T>(key: key, child: child);
}

class _CmpysPage<T> extends Page<T> {
  const _CmpysPage({super.key, required this.child});
  final Widget child;

  @override
  Route<T> createRoute(BuildContext context) => CmpysPageRoute<T>(
    settings: this,
    // Read the current Page after a declarative route update.
    builder: (context) =>
        (ModalRoute.of(context)!.settings as _CmpysPage<T>).child,
  );
}

/// Native mobile transitions keep edge-swipe cancellation, RTL, PopScope and
/// Android predictive back under the framework's control. Desktop retains the
/// shared fade-through. Never replace this with a full-screen swipe detector:
/// readers, sliders and carousels own their horizontal gestures.
class CmpysPageRoute<T> extends MaterialPageRoute<T> {
  CmpysPageRoute({required super.builder, super.settings});

  @override
  Widget buildTransitions(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    final platform = Theme.of(context).platform;
    if (platform == TargetPlatform.iOS ||
        platform == TargetPlatform.macOS ||
        platform == TargetPlatform.android) {
      final motion = MotionConfig.enabled(context);
      // Keep native gesture recognizers mounted even when spatial transitions
      // are disabled. The real route controller still owns completion/cancel.
      return super.buildTransitions(
        context,
        motion ? animation : const AlwaysStoppedAnimation<double>(1),
        motion ? secondaryAnimation : const AlwaysStoppedAnimation<double>(0),
        motion ? child : FadeTransition(opacity: animation, child: child),
      );
    }
    return CmpysPageTransition.buildTransition(
      context,
      animation,
      secondaryAnimation,
      child,
    );
  }
}

/// Record entry uses native mobile back gestures and a desktop slide-up.
class CmpysSheetRoute<T> extends CmpysPageRoute<T> {
  CmpysSheetRoute({required super.builder});

  @override
  Widget buildTransitions(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    final platform = Theme.of(context).platform;
    if (platform == TargetPlatform.iOS ||
        platform == TargetPlatform.macOS ||
        platform == TargetPlatform.android) {
      return super.buildTransitions(
        context,
        animation,
        secondaryAnimation,
        child,
      );
    }
    final curved = CurveTween(curve: AppCurves.easeOut).animate(animation);
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
  }
}
