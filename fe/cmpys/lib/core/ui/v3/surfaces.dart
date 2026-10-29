import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' show ImageFilter, PointMode;

import 'package:flutter/gestures.dart' show DragStartBehavior;
import 'package:flutter/material.dart';

import '../../../app/design_tokens.dart';
import '../motion/motion_config.dart';
import 'buttons.dart';
import 'chips.dart';
import 'icons.dart';
import 'motion.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Sheet
// ─────────────────────────────────────────────────────────────────────────────

/// The `Sheet` panel from `v3/core.jsx`: a 34-radius card (night2 when
/// [dark]) with a grab handle, an optional [title] row with a 34 pt close
/// button, and scrolling content padded 10 / 22 / 26 (none with [noPad]).
///
/// Dragging the handle or title row moves the panel with the finger; letting
/// go past [dismissDistance] calls [onClose] (default: pop the route, and
/// spring back if the pop is vetoed, e.g. by a `PopScope`), otherwise it
/// springs back. [showV3Sheet] adds the scrim and slide-up.
///
/// The body scrolls inside the sheet by default. Pass [scrollable] false to
/// host your own scrollable (a `ListView`, say): the body is then bounded to
/// the height left under the header, still padded unless [noPad].
class V3Sheet extends StatefulWidget {
  const V3Sheet({
    super.key,
    this.title,
    required this.child,
    this.dark = false,
    this.noPad = false,
    this.maxHeightFraction = 0.86,
    this.onClose,
    this.scrollable = true,
  });

  /// Key on the grab-handle strip (tests and drag probes).
  static const handleKey = ValueKey<String>('v3-sheet-handle');

  /// Key on the panel itself.
  static const panelKey = ValueKey<String>('v3-sheet-panel');

  /// Drag distance past which releasing dismisses (the design's 90 px).
  static const double dismissDistance = 90;

  final String? title;
  final Widget child;
  final bool dark;
  final bool noPad;

  /// Maximum height as a fraction of the screen (the design's `max`, 86%).
  final double maxHeightFraction;

  /// Replaces the default close (pop the enclosing route). A custom handler
  /// owns the outcome: the sheet does not spring back after calling it.
  final VoidCallback? onClose;

  /// Wrap the body in a scroll view (default) or bound it for the caller's
  /// own scrollable.
  final bool scrollable;

  @override
  State<V3Sheet> createState() => _V3SheetState();
}

class _V3SheetState extends State<V3Sheet> with SingleTickerProviderStateMixin {
  late final AnimationController _snap;
  double _drag = 0;
  double _snapFrom = 0;
  double? _startY;

  @override
  void initState() {
    super.initState();
    _snap = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
    )..addListener(_onSnap);
  }

  void _onSnap() {
    setState(() {
      _drag = _snapFrom * (1 - AppMotion.spring.transform(_snap.value));
    });
  }

  Future<void> _close() async {
    final onClose = widget.onClose;
    if (onClose != null) {
      onClose();
      return;
    }
    final route = ModalRoute.of(context);
    await Navigator.of(context).maybePop();
    if (!mounted) return;
    // `maybePop` also resolves true when a PopScope vetoes the pop, so ask
    // the route itself: still current means it did not go anywhere.
    if (route == null || route.isCurrent) _springBack();
  }

  void _springBack() {
    if (_drag == 0) return;
    if (!MotionConfig.enabled(context)) {
      setState(() => _drag = 0);
      return;
    }
    _snapFrom = _drag;
    _snap.forward(from: 0);
  }

  void _dragStart(DragStartDetails details) {
    _snap.stop();
    _startY = details.globalPosition.dy - _drag;
  }

  void _dragUpdate(DragUpdateDetails details) {
    final start = _startY;
    if (start == null) return;
    setState(() => _drag = math.max(0, details.globalPosition.dy - start));
  }

  void _dragEnd([DragEndDetails? _]) {
    if (_startY == null) return;
    _startY = null;
    if (_drag > V3Sheet.dismissDistance) {
      unawaited(_close());
      return;
    }
    _springBack();
  }

  @override
  void dispose() {
    _snap.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final dark = widget.dark;
    final foreground = dark ? Colors.white : AppColors.ink;
    final media = MediaQuery.of(context);
    final maxHeight = math.max(
      0.0,
      math.min(
        media.size.height * widget.maxHeightFraction,
        media.size.height - media.viewInsets.bottom - media.padding.top - 16,
      ),
    );
    const radius = BorderRadius.all(Radius.circular(34));
    final bodyPadding = widget.noPad
        ? EdgeInsets.zero
        : const EdgeInsets.fromLTRB(22, 10, 22, 26);

    final header = GestureDetector(
      behavior: HitTestBehavior.opaque,
      // Screen readers close via the close button or the scrim's "Dismiss".
      excludeFromSemantics: true,
      dragStartBehavior: DragStartBehavior.down,
      onVerticalDragStart: _dragStart,
      onVerticalDragUpdate: _dragUpdate,
      onVerticalDragEnd: _dragEnd,
      onVerticalDragCancel: _dragEnd,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ColoredBox(
            key: V3Sheet.handleKey,
            color: const Color(0x00000000), // hit-testable strip
            child: Padding(
              padding: const EdgeInsets.only(top: 10, bottom: 4),
              child: Center(
                child: Container(
                  width: 38,
                  height: 5,
                  decoration: BoxDecoration(
                    color: dark ? const Color(0x33FFFFFF) : AppColors.hair2,
                    borderRadius: BorderRadius.circular(9),
                  ),
                ),
              ),
            ),
          ),
          if (widget.title != null)
            // Design: padding 6 22 4, gap 10, 34 pt close. The close button's
            // 44 pt hit box takes 5 pt of that padding on each side.
            Padding(
              padding: const EdgeInsets.only(left: 22, right: 17, top: 1),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      widget.title!,
                      style: AppTypography.sans(
                        19,
                        FontWeight.w600,
                      ).copyWith(color: foreground, letterSpacing: -0.01 * 19),
                    ),
                  ),
                  const SizedBox(width: 5),
                  V3IconButton(
                    icon: V3Icons.x,
                    size: 34,
                    dark: dark,
                    label: 'Close',
                    onPressed: _close,
                  ),
                ],
              ),
            ),
        ],
      ),
    );

    return Transform.translate(
      offset: Offset(0, _drag),
      child: Container(
        key: V3Sheet.panelKey,
        constraints: BoxConstraints(maxHeight: maxHeight),
        decoration: BoxDecoration(
          color: dark ? AppColors.night2 : AppColors.card,
          borderRadius: radius,
          boxShadow: const [
            BoxShadow(
              color: Color(0x2E000000),
              offset: Offset(0, -10),
              blurRadius: 40,
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: radius,
          child: Material(
            type: MaterialType.transparency,
            child: DefaultTextStyle(
              style: AppTypography.sans(16).copyWith(color: foreground),
              child: IconTheme(
                data: IconThemeData(color: foreground),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    header,
                    Flexible(
                      child: widget.scrollable
                          ? SingleChildScrollView(
                              padding: bodyPadding,
                              child: widget.child,
                            )
                          // Loose fit: at most the height left under the
                          // header, so a ListView body has a bounded viewport.
                          : Padding(padding: bodyPadding, child: widget.child),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Pushes a [V3Sheet] as a modal route: a 42% night scrim with a 3 px blur
/// fading in over .35 s, and the panel springing up from below over .5 s
/// (`--spring`), inset 8 pt from the screen edges and lifted above the
/// keyboard. Tapping the scrim, the close button or dragging past 90 pt pops
/// it. Reduced motion shows and hides it at once. Pass [scrollable] false
/// when the builder returns its own scrollable (see [V3Sheet.scrollable]).
Future<T?> showV3Sheet<T>(
  BuildContext context, {
  required WidgetBuilder builder,
  String? title,
  bool dark = false,
  double max = 0.86,
  bool noPad = false,
  bool scrollable = true,
  bool dismissible = true,
  bool useRootNavigator = true,
}) {
  final localizations = Localizations.of<MaterialLocalizations>(
    context,
    MaterialLocalizations,
  );
  return Navigator.of(context, rootNavigator: useRootNavigator).push(
    V3SheetRoute<T>(
      builder: builder,
      title: title,
      dark: dark,
      max: max,
      noPad: noPad,
      scrollable: scrollable,
      dismissible: dismissible,
      reducedMotion: !MotionConfig.enabled(context),
      barrierLabel: localizations?.modalBarrierDismissLabel ?? 'Dismiss',
    ),
  );
}

/// The route behind [showV3Sheet]; usable directly with [Navigator.push].
class V3SheetRoute<T> extends PopupRoute<T> {
  V3SheetRoute({
    required this.builder,
    this.title,
    this.dark = false,
    this.max = 0.86,
    this.noPad = false,
    this.scrollable = true,
    this.dismissible = true,
    this.reducedMotion = false,
    String? barrierLabel,
    super.settings,
  }) : _barrierLabel = barrierLabel;

  final WidgetBuilder builder;
  final String? title;
  final bool dark;
  final double max;
  final bool noPad;

  /// See [V3Sheet.scrollable].
  final bool scrollable;
  final bool dismissible;
  final bool reducedMotion;
  final String? _barrierLabel;

  @override
  Color? get barrierColor => null; // the page paints its own blurred scrim

  @override
  bool get barrierDismissible => dismissible;

  @override
  String? get barrierLabel => _barrierLabel;

  @override
  Duration get transitionDuration =>
      reducedMotion ? Duration.zero : const Duration(milliseconds: 500);

  // The design unmounts 380 ms after closing.
  @override
  Duration get reverseTransitionDuration =>
      reducedMotion ? Duration.zero : const Duration(milliseconds: 380);

  @override
  Widget buildPage(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
  ) {
    return _V3SheetPage(route: this, animation: animation);
  }
}

/// Plays a curve on a compressed clock: `curve(t * factor)`.
class _TimeScaledCurve extends Curve {
  const _TimeScaledCurve(this.curve, this.factor);

  final Curve curve;
  final double factor;

  @override
  double transformInternal(double t) => curve.transform(t * factor);
}

class _V3SheetPage<T> extends StatefulWidget {
  const _V3SheetPage({required this.route, required this.animation});

  final V3SheetRoute<T> route;
  final Animation<double> animation;

  @override
  State<_V3SheetPage<T>> createState() => _V3SheetPageState<T>();
}

class _V3SheetPageState<T> extends State<_V3SheetPage<T>> {
  // Opening: translateY 110% → 0 on --spring over .5 s. Closing runs the same
  // .5 s spring but is cut at 380 ms (76%), when the design unmounts.
  late final CurvedAnimation _slide = CurvedAnimation(
    parent: widget.animation,
    curve: AppMotion.spring,
    reverseCurve: const FlippedCurve(_TimeScaledCurve(AppMotion.spring, 0.76)),
  );
  // Scrim: opacity .35 s `ease` both ways (380 ms reverse → done at 7.9%).
  late final CurvedAnimation _scrim = CurvedAnimation(
    parent: widget.animation,
    curve: const Interval(0, 0.7, curve: Curves.ease),
    reverseCurve: const Interval(0.0789, 1, curve: FlippedCurve(Curves.ease)),
  );

  @override
  void dispose() {
    _slide.dispose();
    _scrim.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final route = widget.route;
    final keyboard = MediaQuery.viewInsetsOf(context).bottom;
    return Stack(
      children: [
        Positioned.fill(
          child: IgnorePointer(
            child: AnimatedBuilder(
              animation: _scrim,
              builder: (context, _) {
                final v = _scrim.value.clamp(0.0, 1.0);
                final tint = ColoredBox(
                  color: AppColors.night.withValues(alpha: 0.42 * v),
                );
                if (v == 0) return tint;
                return BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 3 * v, sigmaY: 3 * v),
                  child: tint,
                );
              },
            ),
          ),
        ),
        Positioned(
          left: 8,
          right: 8,
          bottom: 8 + keyboard,
          child: AnimatedBuilder(
            animation: _slide,
            builder: (context, child) => FractionalTranslation(
              translation: Offset(0, 1.1 * (1 - _slide.value)),
              child: child,
            ),
            child: Semantics(
              scopesRoute: true,
              namesRoute: route.title != null,
              explicitChildNodes: true,
              label: route.title,
              child: V3Sheet(
                title: route.title,
                dark: route.dark,
                noPad: route.noPad,
                maxHeightFraction: route.max,
                scrollable: route.scrollable,
                // Default close: pops this route, springs back if vetoed.
                child: Builder(builder: route.builder),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Section, card, top bar
// ─────────────────────────────────────────────────────────────────────────────

/// `Section` from `v3/core.jsx`: a titled block (18 pt w600) with an
/// optional `action ›` link, 30 pt above and 20 pt side padding.
class V3Section extends StatelessWidget {
  const V3Section({
    super.key,
    required this.title,
    this.action,
    this.onAction,
    required this.child,
    this.dark = false,
    this.padding = const EdgeInsets.symmetric(horizontal: 20),
    this.top = 30,
  });

  final String title;

  /// Link label, e.g. "See all".
  final String? action;
  final VoidCallback? onAction;
  final Widget child;
  final bool dark;
  final EdgeInsets padding;

  /// Space above the section (the design's `marginTop: 30`).
  final double top;

  /// Space borrowed from [top] for the link's hit box.
  static const double _linkLift = 11;

  @override
  Widget build(BuildContext context) {
    final linkColor = dark ? AppColors.nink2 : AppColors.ink2;
    // With a link, [_linkLift] pt of the space above the section moves into
    // the header row (on the title and the link alike, so the baselines stay
    // aligned). Nothing renders anywhere new, but the link's hit box spans
    // that space above it and the header's 12 pt bottom margin below it,
    // reaching the 44 pt minimum.
    final outerTop = padding.top + top;
    final lift = action == null ? 0.0 : math.min(_linkLift, outerTop);
    return Padding(
      padding: padding.copyWith(top: outerTop - lift),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Expanded(
                child: Padding(
                  padding: EdgeInsets.only(top: lift),
                  child: Text(
                    title,
                    style: AppTypography.sans(18, FontWeight.w600).copyWith(
                      color: dark ? Colors.white : AppColors.ink,
                      letterSpacing: -0.015 * 18,
                    ),
                  ),
                ),
              ),
              if (action != null)
                V3Pressable(
                  onTap: onAction,
                  minTapTarget: 0,
                  pressedScale: 1,
                  focusRadius: BorderRadius.circular(8),
                  // Guarantees 44 pt even with a short lift; any extra
                  // height falls below the baseline.
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(minHeight: kV3TapTarget),
                    child: Padding(
                      padding: EdgeInsets.only(
                        left: 12,
                        top: 4 + lift,
                        bottom: 12,
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.baseline,
                        textBaseline: TextBaseline.alphabetic,
                        children: [
                          Text(
                            action!,
                            style: AppTypography.sans(
                              13.5,
                              FontWeight.w600,
                            ).copyWith(color: linkColor),
                          ),
                          const SizedBox(width: 2),
                          V3Icon(V3Icons.right, size: 15, color: linkColor),
                        ],
                      ),
                    ),
                  ),
                ),
            ],
          ),
          if (action == null) const SizedBox(height: 12),
          child,
        ],
      ),
    );
  }
}

/// `card()` from `v3/core.jsx`: card fill, radius `--r` (22) and a 1 pt hair
/// border. Pass overrides as the design's spread does.
BoxDecoration v3Card({
  Color color = AppColors.card,
  double radius = AppRadii.r,
  Color borderColor = AppColors.hair,
  List<BoxShadow>? boxShadow,
  Gradient? gradient,
}) {
  return BoxDecoration(
    color: gradient == null ? color : null,
    gradient: gradient,
    borderRadius: BorderRadius.circular(radius),
    border: Border.all(color: borderColor),
    boxShadow: boxShadow,
  );
}

/// Frosted glass over whatever is behind it (a video, say): the backdrop is
/// blurred by [blur] (and saturated by [saturation], CSS `saturate()`), then
/// tinted with [tint], inside a [radius] rounded box with a 1 pt
/// [borderColor] hairline. [child] is padded by [padding].
///
/// The mentor lab's two looks are [V3Frosted.stage] (`rgba(20,18,28,.55)`,
/// `blur(18px) saturate(1.3)`, white border at .1) and [V3Frosted.secondary]
/// (`rgba(25,22,34,.72)`, `blur(18px)`, white border at .08).
class V3Frosted extends StatelessWidget {
  const V3Frosted({
    super.key,
    required this.child,
    required this.tint,
    this.blur = 18,
    this.saturation = 1,
    this.radius = 24,
    this.borderColor = const Color(0x1AFFFFFF),
    this.padding = EdgeInsets.zero,
  });

  /// The lab's stage list card.
  const V3Frosted.stage({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
  }) : tint = const Color(0x8C14121C),
       blur = 18,
       saturation = 1.3,
       radius = 24,
       borderColor = const Color(0x1AFFFFFF);

  /// The lab's secondary cards ("From your comparison", "Blueprint
  /// direction", "12-week roadmap").
  const V3Frosted.secondary({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(18),
  }) : tint = const Color(0xB8191622),
       blur = 18,
       saturation = 1,
       radius = 24,
       borderColor = const Color(0x14FFFFFF);

  final Widget child;
  final Color tint;

  /// Backdrop blur in logical pixels (CSS `blur()`).
  final double blur;

  /// Backdrop saturation (CSS `saturate()`); 1 is unchanged.
  final double saturation;
  final double radius;
  final Color borderColor;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    final shape = BorderRadius.circular(radius);
    final ImageFilter blurFilter = ImageFilter.blur(sigmaX: blur, sigmaY: blur);
    final s = saturation;
    final filter = (s - 1).abs() < 0.001
        ? blurFilter
        : ImageFilter.compose(
            outer: ColorFilter.matrix([
              0.213 + 0.787 * s, 0.715 - 0.715 * s, 0.072 - 0.072 * s, 0, 0, //
              0.213 - 0.213 * s, 0.715 + 0.285 * s, 0.072 - 0.072 * s, 0, 0,
              0.213 - 0.213 * s, 0.715 - 0.715 * s, 0.072 + 0.928 * s, 0, 0,
              0, 0, 0, 1, 0,
            ]),
            inner: blurFilter,
          );
    return ClipRRect(
      borderRadius: shape,
      child: BackdropFilter(
        filter: filter,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: tint,
            borderRadius: shape,
            border: Border.all(color: borderColor),
          ),
          child: Padding(padding: padding, child: child),
        ),
      ),
    );
  }
}

/// `TopBar` from `v3/core.jsx`: a 52 pt bar below the status bar with an
/// optional 40 pt back button, a 15.5 pt title and 12 pt subtitle, and a
/// [right] slot. [solid] paints paper (night when [dark]) behind it.
class V3TopBar extends StatelessWidget {
  const V3TopBar({
    super.key,
    this.onBack,
    this.title,
    this.sub,
    this.right,
    this.dark = false,
    this.solid = false,
    this.backIcon = V3Icons.left,
    this.topInset,
  });

  final VoidCallback? onBack;
  final String? title;
  final String? sub;
  final Widget? right;
  final bool dark;
  final bool solid;
  final V3Icons backIcon;

  /// Space above the bar; defaults to the status-bar inset (the design's 54).
  final double? topInset;

  @override
  Widget build(BuildContext context) {
    final top = topInset ?? MediaQuery.paddingOf(context).top;
    final back = onBack;
    // The bar is a fixed 52 pt: like the tab bar, its text scales at most
    // 1.2×, and each line stays on one line, so it never overflows.
    return MediaQuery.withClampedTextScaling(
      maxScaleFactor: 1.2,
      child: ColoredBox(
        color: solid
            ? (dark ? AppColors.night : AppColors.paper)
            : const Color(0x00000000),
        child: Padding(
          padding: EdgeInsets.only(top: top),
          child: SizedBox(
            height: 52,
            child: Padding(
              // A 40 pt back disc sits in a 44 pt hit box: trim 2 pt each side.
              padding: EdgeInsets.only(left: back != null ? 14 : 16, right: 16),
              child: Row(
                children: [
                  if (back != null) ...[
                    V3IconButton(
                      icon: backIcon,
                      dark: dark,
                      label: 'Back',
                      onPressed: back,
                    ),
                    const SizedBox(width: 8),
                  ],
                  Expanded(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (title != null)
                          Text(
                            title!,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: AppTypography.sans(15.5, FontWeight.w600)
                                .copyWith(
                                  color: dark ? Colors.white : AppColors.ink,
                                ),
                          ),
                        if (sub != null)
                          Padding(
                            padding: const EdgeInsets.only(top: 1),
                            child: Text(
                              sub!,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: AppTypography.sans(12).copyWith(
                                color: dark ? AppColors.nink3 : AppColors.ink3,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                  // The design's `gap: 10` between title and the right slot.
                  if (right != null) ...[const SizedBox(width: 10), right!],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Avatar, portrait, cover
// ─────────────────────────────────────────────────────────────────────────────

// CSS `grayscale(1)`.
const List<double> _grayscale = [
  0.2126, 0.7152, 0.0722, 0, 0, //
  0.2126, 0.7152, 0.0722, 0, 0,
  0.2126, 0.7152, 0.0722, 0, 0,
  0, 0, 0, 1, 0,
];

// CSS `grayscale(1) contrast(1.15) brightness(.8)` at `opacity: .9`:
// rgb' = .8 · (1.15 · Y + .5 · (1 − 1.15)) = .92 · Y − .06 (× 255).
const List<double> _portraitMatrix = [
  0.92 * 0.2126, 0.92 * 0.7152, 0.92 * 0.0722, 0, -15.3, //
  0.92 * 0.2126, 0.92 * 0.7152, 0.92 * 0.0722, 0, -15.3,
  0.92 * 0.2126, 0.92 * 0.7152, 0.92 * 0.0722, 0, -15.3,
  0, 0, 0, 0.9, 0,
];

/// `Avatar` from `v3/core.jsx`: a round photo (grayscale when [gray]) or
/// [initials] on [tint], with an optional 2 pt [ring] colour around a 2 pt
/// card gap. [name] is the spoken label.
class V3Avatar extends StatelessWidget {
  const V3Avatar({
    super.key,
    this.image,
    this.initials = '',
    this.name,
    this.tint,
    this.size = 40,
    this.ring,
    this.gray = false,
  });

  final ImageProvider? image;
  final String initials;
  final String? name;

  /// Fill behind the photo / initials (the design's `m.tint`, default #ddd).
  final Color? tint;
  final double size;
  final Color? ring;
  final bool gray;

  @override
  Widget build(BuildContext context) {
    final fallback = Center(
      child: Text(
        initials,
        style: AppTypography.sans(
          size * 0.38,
          FontWeight.w600,
        ).copyWith(color: AppColors.ink),
      ),
    );
    Widget face = image == null
        ? fallback
        : Image(
            image: image!,
            fit: BoxFit.cover,
            width: double.infinity,
            height: double.infinity,
            errorBuilder: (context, error, stack) => fallback,
          );
    if (gray && image != null) {
      face = ColorFiltered(
        colorFilter: const ColorFilter.matrix(_grayscale),
        child: face,
      );
    }
    final inner = Container(
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: tint ?? const Color(0xFFDDDDDD),
        border: ring == null
            ? null
            : Border.all(color: AppColors.card, width: 2),
      ),
      child: ClipOval(child: face),
    );
    return Semantics(
      image: name != null,
      label: name,
      excludeSemantics: name != null,
      child: Container(
        width: size,
        height: size,
        padding: ring == null ? null : const EdgeInsets.all(2),
        decoration: ring == null
            ? null
            : BoxDecoration(shape: BoxShape.circle, color: ring),
        child: inner,
      ),
    );
  }
}

/// `Portrait` from `v3/core.jsx`: the night duotone hero for low-res mentor
/// photos. The [image] is enlarged 12%, made grayscale (contrast 1.15,
/// brightness .8, a .4 px blur, 90% opacity), tinted with [tone] in `color`
/// blend at 55%, shaded by a night gradient (10% → 20% at 45% → 96%) and a
/// film grain. [child] is laid over it (use [Positioned] / [Align]).
class V3Portrait extends StatelessWidget {
  const V3Portrait({
    super.key,
    this.image,
    this.height = 320,
    this.radius = 0,
    this.tone = AppColors.iris,
    this.child,
  });

  final ImageProvider? image;
  final double height;
  final double radius;
  final Color tone;
  final Widget? child;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: SizedBox(
        height: height,
        width: double.infinity,
        child: ColoredBox(
          color: AppColors.night,
          child: Stack(
            fit: StackFit.expand,
            children: [
              if (image != null)
                FractionallySizedBox(
                  widthFactor: 1.12,
                  heightFactor: 1.12,
                  child: ImageFiltered(
                    imageFilter: ImageFilter.blur(sigmaX: 0.4, sigmaY: 0.4),
                    child: ColorFiltered(
                      colorFilter: const ColorFilter.matrix(_portraitMatrix),
                      child: Image(
                        image: image!,
                        fit: BoxFit.cover,
                        excludeFromSemantics: true,
                        errorBuilder: (context, error, stack) =>
                            const SizedBox.shrink(),
                      ),
                    ),
                  ),
                ),
              DecoratedBox(
                decoration: BoxDecoration(
                  color: tone.withValues(alpha: tone.a * 0.55),
                  backgroundBlendMode: BlendMode.color,
                ),
              ),
              const DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Color(0x1A0E0C14),
                      Color(0x330E0C14),
                      Color(0xF50E0C14),
                    ],
                    stops: [0, 0.45, 1],
                  ),
                ),
              ),
              const V3Grain(),
              ?child,
            ],
          ),
        ),
      ),
    );
  }
}

/// Book-cover grounds from the design's `BookShelf` (oklch → sRGB). The
/// backend has no cover colour, so a screen picks one with [v3CoverGround].
const List<Color> kV3CoverGrounds = <Color>[
  Color(0xFF2B294B), // oklch(0.3 0.06 285)
  Color(0xFF225A39), // oklch(0.42 0.08 155)
  Color(0xFFB8492E), // oklch(0.55 0.15 35)
  Color(0xFF46372B), // oklch(0.35 0.03 60)
];

/// The type colour on every [kV3CoverGrounds] cover.
const Color kV3CoverInk = Color(0xFFF6F1EA);

/// The cover ground for the book with [id]: stable, so one book shows one
/// cover on every screen.
Color v3CoverGround(String id) =>
    kV3CoverGrounds[id.codeUnits.fold<int>(0, (a, b) => a + b) %
        kV3CoverGrounds.length];

/// The title a cover prints: the main title without its subtitle. It cuts
/// only at a subtitle separator, a colon followed by a space or a spaced em
/// dash, so "Thinking, Fast and Slow" and "Moby Dick; Or, The Whale" stay
/// whole while "The Art of War: A Guide" becomes "The Art of War". The result
/// is trimmed; a title that would be left empty is returned whole.
String v3CoverTitle(String title) {
  final whole = title.trim();
  var cut = whole.length;
  for (final separator in const [': ', ' — ']) {
    final at = whole.indexOf(separator);
    if (at >= 0 && at < cut) cut = at;
  }
  final short = whole.substring(0, cut).trim();
  return short.isEmpty ? whole : short;
}

/// `Cover` from `v3/core.jsx`: a typographic book cover. The author's last
/// name runs uppercase at the top (8.5% of [width], .14em tracking, 75%),
/// the [title] in Instrument Serif (19% of [width]) sits at the bottom, with
/// a faint ring top-right, a spine shade and grain.
class V3Cover extends StatelessWidget {
  const V3Cover({
    super.key,
    required this.title,
    required this.author,
    required this.background,
    required this.foreground,
    this.width = 92,
    this.height = 132,
    this.radius = 10,
  });

  final String title;
  final String author;

  /// Cover colour (the design's `b.bg`).
  final Color background;

  /// Type colour (the design's `b.fg`).
  final Color foreground;
  final double width;
  final double height;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final w = width;
    final words = author.trim().split(RegExp(r'\s+'));
    final lastName = words.isEmpty ? '' : words.last;
    final authorSize = w * 0.085;
    final borderRadius = BorderRadius.circular(radius);
    return Semantics(
      image: true,
      label: '$title, $author',
      excludeSemantics: true,
      child: Container(
        width: w,
        height: height,
        decoration: BoxDecoration(
          color: background,
          borderRadius: borderRadius,
          boxShadow: const [
            BoxShadow(
              color: Color(0x73000000),
              offset: Offset(0, 10),
              blurRadius: 24,
              spreadRadius: -12,
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: borderRadius,
          child: Stack(
            fit: StackFit.expand,
            children: [
              // inset 3px 0 0 rgba(0,0,0,.12): the spine.
              const Positioned(
                left: 0,
                top: 0,
                bottom: 0,
                width: 3,
                child: ColoredBox(color: Color(0x1F000000)),
              ),
              Padding(
                padding: EdgeInsets.all(w * 0.1),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      lastName.toUpperCase(),
                      maxLines: 1,
                      softWrap: false,
                      overflow: TextOverflow.clip,
                      style: AppTypography.sans(authorSize, FontWeight.w600)
                          .copyWith(
                            color: foreground.withValues(
                              alpha: foreground.a * 0.75,
                            ),
                            letterSpacing: 0.14 * authorSize,
                          ),
                    ),
                    // `marginTop: auto`: the title sits at the bottom and,
                    // like `overflow: hidden`, clips if it runs too tall.
                    Expanded(
                      child: Align(
                        alignment: Alignment.bottomLeft,
                        child: Text(
                          title,
                          style: AppTypography.display(
                            w * 0.19,
                          ).copyWith(color: foreground, height: 0.98),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              Positioned(
                right: -w * 0.25,
                top: -w * 0.25,
                width: w * 0.8,
                height: w * 0.8,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: foreground.withValues(alpha: foreground.a * 0.25),
                    ),
                  ),
                ),
              ),
              const V3Grain(),
            ],
          ),
        ),
      ),
    );
  }
}

/// `.grain`: fine noise at 7% in `overlay` blend. Drawn once per size from
/// a fixed seed (no image asset or per-frame cost). Fills its parent; lay it
/// over a surface with `Positioned.fill` (it ignores pointers).
class V3Grain extends StatelessWidget {
  const V3Grain({super.key});

  @override
  Widget build(BuildContext context) {
    return const IgnorePointer(
      child: RepaintBoundary(child: CustomPaint(painter: _GrainPainter())),
    );
  }
}

class _GrainPainter extends CustomPainter {
  const _GrainPainter();

  static const double _step = 2.5;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    final random = math.Random(1729);
    final light = <double>[];
    final dark = <double>[];
    for (var y = 0.0; y < size.height; y += _step) {
      for (var x = 0.0; x < size.width; x += _step) {
        final roll = random.nextDouble();
        if (roll > 0.66) continue;
        final px = x + random.nextDouble() * _step;
        final py = y + random.nextDouble() * _step;
        (roll < 0.33 ? light : dark)
          ..add(px)
          ..add(py);
      }
    }
    final paint = Paint()
      ..strokeWidth = 1.2
      ..strokeCap = StrokeCap.square
      ..blendMode = BlendMode.overlay;
    canvas.drawRawPoints(
      PointMode.points,
      Float32List.fromList(light),
      paint..color = const Color(0x12FFFFFF),
    );
    canvas.drawRawPoints(
      PointMode.points,
      Float32List.fromList(dark),
      paint..color = const Color(0x12000000),
    );
  }

  @override
  bool shouldRepaint(_GrainPainter oldDelegate) => false;
}

// ─────────────────────────────────────────────────────────────────────────────
// Access badge (`ACCESS` / `AccessBadge`, BN-11 reading-access honesty)
// ─────────────────────────────────────────────────────────────────────────────

/// What CMPYS can actually show for a reading item.
enum AccessType { guide, original, excerpt, web, video, none }

/// One `ACCESS` entry: badge label, icon and colours, plus the [cta] and
/// [note] that reading screens show. Copy is verbatim from the design.
@immutable
class V3AccessCopy {
  const V3AccessCopy({
    required this.label,
    required this.icon,
    required this.color,
    required this.background,
    required this.cta,
    required this.note,
  });

  final String label;
  final V3Icons icon;
  final Color color;
  final Color background;

  /// Primary action label; null when there is nothing to open ([AccessType.none]).
  final String? cta;
  final String note;
}

const Map<AccessType, V3AccessCopy> _access = {
  AccessType.guide: V3AccessCopy(
    label: 'Study guide',
    icon: V3Icons.book,
    color: AppColors.iris2,
    background: AppColors.irisSoft,
    cta: 'Open guide',
    note: 'A CMPYS-written guide to the book, not the author’s full text.',
  ),
  AccessType.original: V3AccessCopy(
    label: 'Original · public domain',
    icon: V3Icons.book,
    color: AppColors.sage2,
    background: AppColors.sageSoft,
    cta: 'Read original',
    note: 'Full original text, verified source.',
  ),
  AccessType.excerpt: V3AccessCopy(
    label: 'Excerpt only',
    icon: V3Icons.file,
    color: AppColors.gold2,
    background: AppColors.goldSoft,
    cta: 'Read excerpt',
    note: 'A verified excerpt. The full book is not included.',
  ),
  AccessType.web: V3AccessCopy(
    label: 'Web source',
    icon: V3Icons.external,
    color: AppColors.ink2,
    background: AppColors.paper2,
    cta: 'Open source',
    note: 'Opens the verified page in the in-app viewer.',
  ),
  AccessType.video: V3AccessCopy(
    label: 'Video',
    icon: V3Icons.video,
    color: AppColors.ember2,
    background: AppColors.emberSoft,
    cta: 'Watch',
    note: 'Plays in the in-app video viewer.',
  ),
  AccessType.none: V3AccessCopy(
    label: 'No readable edition',
    icon: V3Icons.lock,
    color: AppColors.ink3,
    background: AppColors.paper2,
    cta: null,
    note: 'Recommended reading. CMPYS has no readable edition of this title.',
  ),
};

/// The design's `ACCESS[type]`.
V3AccessCopy accessCopy(AccessType type) => _access[type]!;

/// `AccessBadge` from `v3/core.jsx`: a [V3Tag] naming what CMPYS can show.
class V3AccessBadge extends StatelessWidget {
  const V3AccessBadge({super.key, required this.type});

  final AccessType type;

  @override
  Widget build(BuildContext context) {
    final copy = accessCopy(type);
    return V3Tag(
      color: copy.color,
      background: copy.background,
      icon: copy.icon,
      child: Text(copy.label),
    );
  }
}
