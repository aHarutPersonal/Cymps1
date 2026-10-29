import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../../../app/design_tokens.dart';
import '../motion/motion_config.dart';
import 'icons.dart';
import 'motion.dart';
import 'surfaces.dart';

// `TabBar` from `v3/app.jsx`: the floating dark-glass pill with a notch cut
// out of its top edge for the mentor's portrait, a sliding indicator with an
// ember tick, a tap ripple and a count badge on the Today tab.
//
// This file is presentational. The shell (`app_shell.dart`) decides which tab
// is current, when the bar is compact or hidden, and feeds in the mentor and
// the count.
//
// Not carried over from the CSS:
//  * `backdrop-filter: saturate(1.5)`. The glass is .94-.96 opaque, so a
//    saturation boost behind it is not visible.

/// The design's `#121018`: the dark ring around the portrait and the badge,
/// matching the bottom of the glass.
const Color _night = Color(0xFF121018);
const Color _white = Color(0xFFFFFFFF);

/// `rgba(255,255,255,.5)`: an inactive label.
const Color _dim = Color(0x80FFFFFF);

/// One tab of [V3TabBar]. A null [icon] marks the centre tab, which shows the
/// mentor's portrait instead of a glyph.
class V3TabItem {
  const V3TabItem({required this.label, this.icon, this.fillWhenActive = true});

  final String label;
  final V3Icons? icon;

  /// The design tints the active glyph (`fill: rgba(255,255,255,.12)`) on
  /// every tab except Plan and Compare.
  final bool fillWhenActive;
}

/// The portrait in the centre tab: [image] when there is one, else [initials].
class V3TabBarMentor {
  const V3TabBarMentor({this.image, this.initials = '', this.tint});

  final ImageProvider? image;
  final String initials;
  final Color? tint;
}

/// The floating five-slot tab bar of v3.
///
/// All of the geometry follows `TabBar` in `v3/app.jsx`: 20 pt from the sides,
/// 58 pt tall (50 pt and a 20 pt radius when [compact]), each tab one fifth of
/// the pill, the indicator 16.8% wide.
class V3TabBar extends StatefulWidget {
  const V3TabBar({
    super.key,
    required this.items,
    required this.index,
    required this.onTap,
    required this.mentor,
    this.todayLeft = 0,
    this.badgeIndex = 0,
    this.compact = false,
    this.hidden = false,
    this.bottomOffset = 20,
  });

  /// Pill height, and its compact height.
  static const double height = 58;
  static const double compactHeight = 50;

  /// Gap to each side of the screen.
  static const double sideInset = 20;

  /// Room kept above the pill for the portrait that rises into the notch.
  static const double headroom = 20;

  /// Gap between the pill and the bottom of the screen: the design's 20 pt,
  /// lifted on devices whose home-indicator inset is taller than the design's
  /// phone frame has.
  static double bottomOffsetFor(double safeBottom) =>
      math.max(20, safeBottom - 14);

  /// Vertical room the bar takes, from the screen's bottom edge to the pill's
  /// top, plus the 42 pt of breathing room the design's `Scroll` pads below
  /// the last row (120 pt in all on a phone).
  static double clearanceFor(double safeBottom) =>
      bottomOffsetFor(safeBottom) + height + 42;

  final List<V3TabItem> items;
  final int index;
  final ValueChanged<int> onTap;
  final V3TabBarMentor mentor;

  /// Habits not done today; the badge is hidden at 0.
  final int todayLeft;

  /// Which tab carries the [todayLeft] badge.
  final int badgeIndex;

  /// Compact pill: shorter, labels hidden.
  final bool compact;

  /// Slides the whole bar below the screen and takes it out of touch and
  /// semantics.
  final bool hidden;

  /// Distance from the bottom of the available space to the pill.
  final double bottomOffset;

  @override
  State<V3TabBar> createState() => _V3TabBarState();
}

class _V3TabBarState extends State<V3TabBar>
    with SingleTickerProviderStateMixin {
  // The indicator's two edges are animated together by one controller. Each
  // edge runs .55 s on `--spring`; the trailing one starts .07 s later.
  static const double _edgeMs = 550;
  static const double _lagMs = 70;
  static const double _totalMs = _edgeMs + _lagMs;

  late final AnimationController _slide = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 620),
    value: 1,
  );

  late double _fromLeft;
  late double _fromRight;
  late double _toLeft;
  late double _toRight;
  bool _forward = true;

  int _bump = 0;
  ({int id, int k, Offset at})? _ripple;

  // Fractions of the pill width: `L = idx * W + pad`, `R = 100 - (idx + 1) * W
  // + pad` with W = 20% and pad = 1.6%.
  static double _leftFor(int i) => i * .2 + .016;
  static double _rightFor(int i) => (4 - i) * .2 + .016;

  double _edge({required double from, required double to, required bool lag}) {
    final delay = lag ? _lagMs : 0.0;
    final t = Interval(
      delay / _totalMs,
      (delay + _edgeMs) / _totalMs,
      curve: AppMotion.spring,
    ).transform(_slide.value);
    return from + (to - from) * t;
  }

  double get _left => _edge(from: _fromLeft, to: _toLeft, lag: _forward);
  double get _right => _edge(from: _fromRight, to: _toRight, lag: !_forward);

  @override
  void initState() {
    super.initState();
    _fromLeft = _toLeft = _leftFor(widget.index);
    _fromRight = _toRight = _rightFor(widget.index);
  }

  @override
  void didUpdateWidget(V3TabBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.index == widget.index) return;
    final motion = MotionConfig.enabled(context);
    // Moving right, the right edge leads; moving left, the left edge does.
    _forward = widget.index >= oldWidget.index;
    _fromLeft = motion ? _left : _leftFor(widget.index);
    _fromRight = motion ? _right : _rightFor(widget.index);
    _toLeft = _leftFor(widget.index);
    _toRight = _rightFor(widget.index);
    if (motion) {
      _slide.forward(from: 0);
    } else {
      _slide.stop();
      _slide.value = 1;
    }
  }

  @override
  void dispose() {
    _slide.dispose();
    super.dispose();
  }

  void _tap(int i, Offset? at) {
    final motion = MotionConfig.enabled(context);
    setState(() {
      _bump++;
      if (motion && at != null) _ripple = (id: i, k: _bump, at: at);
    });
    widget.onTap(i);
  }

  @override
  Widget build(BuildContext context) {
    final motion = MotionConfig.enabled(context);
    final padding = MediaQuery.paddingOf(context);
    return MediaQuery.withClampedTextScaling(
      // The bar's geometry is fixed; labels grow with the user's text size up
      // to the point where five of them still fit a 56 pt slot.
      maxScaleFactor: 1.3,
      child: IgnorePointer(
        ignoring: widget.hidden,
        child: ExcludeSemantics(
          excluding: widget.hidden,
          child: TweenAnimationBuilder<double>(
            tween: Tween<double>(end: widget.hidden ? 1 : 0),
            duration: motion
                ? const Duration(milliseconds: 550)
                : Duration.zero,
            curve: AppMotion.out,
            builder: (context, hide, child) => FractionalTranslation(
              key: const Key('tab-bar-slide'),
              translation: Offset(0, hide),
              child: child,
            ),
            child: Padding(
              padding: EdgeInsets.fromLTRB(
                V3TabBar.sideInset + padding.left,
                0,
                V3TabBar.sideInset + padding.right,
                widget.bottomOffset,
              ),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 560),
                  child: _body(motion),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _body(bool motion) {
    return TweenAnimationBuilder<double>(
      // 0 = full size, 1 = compact; `height .45s var(--spring)`.
      tween: Tween<double>(end: widget.compact ? 1 : 0),
      duration: motion ? const Duration(milliseconds: 450) : Duration.zero,
      curve: AppMotion.spring,
      builder: (context, t, _) {
        final pill = ui.lerpDouble(V3TabBar.height, V3TabBar.compactHeight, t)!;
        final radius = ui.lerpDouble(23, 20, t)!;
        return SizedBox(
          height: V3TabBar.headroom + pill,
          child: LayoutBuilder(
            builder: (context, box) =>
                _stack(context, box.maxWidth, pill, radius, t, motion),
          ),
        );
      },
    );
  }

  Widget _stack(
    BuildContext context,
    double width,
    double pill,
    double radius,
    double t,
    bool motion,
  ) {
    final items = widget.items;
    final centre = items.indexWhere((item) => item.icon == null);
    final cell = width / items.length;
    // `radial-gradient(circle 29px at 50% -10px, ...)`, -9 when compact.
    final notchY = -10 + t;
    final onCentre = widget.index == centre;

    return Stack(
      clipBehavior: Clip.none,
      children: [
        Positioned(
          left: 0,
          right: 0,
          bottom: 0,
          height: pill,
          child: Semantics(
            container: true,
            explicitChildNodes: true,
            label: 'Main',
            child: Stack(
              key: const Key('v3-tab-bar'),
              clipBehavior: Clip.none,
              children: [
                // The shadow's blur is the costly part of the bar to paint;
                // keep it on its own layer so the indicator and the pop never
                // repaint it.
                Positioned.fill(
                  child: RepaintBoundary(
                    child: Stack(
                      clipBehavior: Clip.none,
                      children: [
                        Positioned.fill(
                          child: CustomPaint(
                            painter: _PillShadowPainter(
                              radius: radius,
                              notchCenterY: notchY,
                            ),
                          ),
                        ),
                        Positioned.fill(
                          child: ClipPath(
                            key: const Key('tab-bar-glass-clip'),
                            clipper: _NotchClipper(
                              radius: radius,
                              notchCenterY: notchY,
                            ),
                            clipBehavior: Clip.antiAlias,
                            child: BackdropFilter(
                              filter: ui.ImageFilter.blur(
                                sigmaX: 22,
                                sigmaY: 22,
                              ),
                              child: CustomPaint(
                                painter: _GlassPainter(radius: radius),
                                child: const SizedBox.expand(),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                Positioned.fill(
                  child: AnimatedBuilder(
                    animation: _slide,
                    builder: (context, _) => Stack(
                      clipBehavior: Clip.none,
                      children: [
                        Positioned(
                          left: width * _left,
                          right: width * _right,
                          top: 6 - t,
                          bottom: 6 - t,
                          child: _Indicator(hollow: onCentre, motion: motion),
                        ),
                      ],
                    ),
                  ),
                ),
                Positioned.fill(
                  child: Row(
                    children: [
                      for (var i = 0; i < items.length; i++)
                        Expanded(
                          child: i == centre
                              ? const SizedBox.shrink()
                              : _TabCell(
                                  key: ValueKey('floating-nav-item-$i'),
                                  item: items[i],
                                  index: i,
                                  on: widget.index == i,
                                  compact: widget.compact,
                                  bump: _bump,
                                  badge: i == widget.badgeIndex
                                      ? widget.todayLeft
                                      : 0,
                                  ripple: _ripple != null && _ripple!.id == i
                                      ? _ripple
                                      : null,
                                  onTap: (at) => _tap(i, at),
                                ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        if (centre >= 0)
          Positioned(
            left: cell * centre,
            width: cell,
            top: 0,
            bottom: 0,
            child: ClipPath(
              key: ValueKey('floating-nav-item-$centre'),
              clipper: _CentreHitClipper(
                pillHeight: pill,
                avatarTop: V3TabBar.headroom - 14 - t,
                scale: 1.04 * (1 - .1 * t),
              ),
              // The clipper only trims where touches land; it never paints.
              clipBehavior: Clip.none,
              child: _CentreTab(
                index: centre,
                item: items[centre],
                mentor: widget.mentor,
                on: onCentre,
                compact: widget.compact,
                compactT: t,
                bump: _bump,
                onTap: () => _tap(centre, null),
              ),
            ),
          ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Glass: path, clip, shadow, fill
// ─────────────────────────────────────────────────────────────────────────────

/// The notch's radius: the mask is `transparent 28px, #000 29px`, so the
/// anti-aliased edge sits half way.
const double _notchRadius = 28.5;

/// The pill's outline with the circular notch cut out of its top centre.
Path _pillPath(Size size, double radius, double notchCenterY) {
  final pill = Path()
    ..addRRect(
      RRect.fromRectAndRadius(Offset.zero & size, Radius.circular(radius)),
    );
  final notch = Path()
    ..addOval(
      Rect.fromCircle(
        center: Offset(size.width / 2, notchCenterY),
        radius: _notchRadius,
      ),
    );
  return Path.combine(PathOperation.difference, pill, notch);
}

/// Clips the glass to the pill minus the notch (the CSS `mask-image`).
class _NotchClipper extends CustomClipper<Path> {
  const _NotchClipper({required this.radius, required this.notchCenterY});

  final double radius;

  /// Notch centre, measured down from the pill's top edge (negative: above).
  final double notchCenterY;

  @override
  Path getClip(Size size) => _pillPath(size, radius, notchCenterY);

  @override
  bool shouldReclip(_NotchClipper oldClipper) =>
      oldClipper.radius != radius || oldClipper.notchCenterY != notchCenterY;
}

/// `filter: drop-shadow(0 18px 26px rgba(14,12,20,.45))`. The CSS filter works
/// on the masked element, so the notch casts no shadow of its own.
class _PillShadowPainter extends CustomPainter {
  const _PillShadowPainter({required this.radius, required this.notchCenterY});

  final double radius;
  final double notchCenterY;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawPath(
      _pillPath(size, radius, notchCenterY).shift(const Offset(0, 18)),
      Paint()
        ..color = const Color.fromRGBO(14, 12, 20, .45)
        // A CSS blur radius is twice the Gaussian's sigma.
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 13),
    );
  }

  @override
  bool shouldRepaint(_PillShadowPainter old) =>
      old.radius != radius || old.notchCenterY != notchCenterY;
}

/// The glass fill: `linear-gradient(180deg, rgba(34,30,44,.94),
/// rgba(16,14,22,.96))` plus the two inset highlights
/// (`inset 0 1px 0 rgba(255,255,255,.09), inset 0 0 0 1px rgba(255,255,255,.05)`).
class _GlassPainter extends CustomPainter {
  const _GlassPainter({required this.radius});

  final double radius;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final rrect = RRect.fromRectAndRadius(rect, Radius.circular(radius));
    canvas.drawRRect(
      rrect,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Color.fromRGBO(34, 30, 44, .94),
            Color.fromRGBO(16, 14, 22, .96),
          ],
        ).createShader(rect),
    );
    final outline = Path()..addRRect(rrect);
    canvas.drawPath(
      Path.combine(
        PathOperation.difference,
        outline,
        Path()..addRRect(rrect.shift(const Offset(0, 1))),
      ),
      Paint()..color = const Color.fromRGBO(255, 255, 255, .09),
    );
    canvas.drawPath(
      Path.combine(
        PathOperation.difference,
        outline,
        Path()..addRRect(rrect.deflate(1)),
      ),
      Paint()..color = const Color.fromRGBO(255, 255, 255, .05),
    );
  }

  @override
  bool shouldRepaint(_GlassPainter old) => old.radius != radius;
}

// ─────────────────────────────────────────────────────────────────────────────
// Indicator
// ─────────────────────────────────────────────────────────────────────────────

/// The sliding highlight behind the current tab, with the ember tick that
/// hangs from the pill's top edge. Hollow (no fill, no tick) behind the centre
/// tab, whose portrait carries its own ring.
class _Indicator extends StatelessWidget {
  const _Indicator({required this.hollow, required this.motion});

  final bool hollow;
  final bool motion;

  @override
  Widget build(BuildContext context) {
    final fade = motion ? const Duration(milliseconds: 300) : Duration.zero;
    return Stack(
      clipBehavior: Clip.none,
      children: [
        Positioned.fill(
          child: AnimatedContainer(
            key: const ValueKey('floating-nav-selector'),
            duration: fade,
            decoration: BoxDecoration(
              color: hollow
                  ? const Color(0x00FFFFFF)
                  : const Color.fromRGBO(255, 255, 255, .09),
              borderRadius: BorderRadius.circular(17),
            ),
            child: AnimatedOpacity(
              opacity: hollow ? 0 : 1,
              duration: fade,
              child: CustomPaint(
                painter: _TopEdgePainter(
                  radius: 17,
                  color: const Color.fromRGBO(255, 255, 255, .08),
                ),
              ),
            ),
          ),
        ),
        Positioned(
          top: -7,
          left: 0,
          right: 0,
          child: Center(
            child: AnimatedContainer(
              key: const Key('tab-bar-tick'),
              duration: fade,
              curve: Curves.ease,
              width: hollow ? 0 : 18,
              height: 3,
              decoration: const BoxDecoration(
                color: AppColors.ember,
                borderRadius: BorderRadius.only(
                  bottomLeft: Radius.circular(4),
                  bottomRight: Radius.circular(4),
                ),
                // `0 2px 10px var(--ember)`
                boxShadow: [
                  BoxShadow(
                    color: AppColors.ember,
                    offset: Offset(0, 2),
                    blurRadius: _blur10,
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// `inset 0 1px 0 <color>`: a one pixel highlight along the top edge.
class _TopEdgePainter extends CustomPainter {
  const _TopEdgePainter({required this.radius, required this.color});

  final double radius;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final rrect = RRect.fromRectAndRadius(
      Offset.zero & size,
      Radius.circular(radius),
    );
    canvas.drawPath(
      Path.combine(
        PathOperation.difference,
        Path()..addRRect(rrect),
        Path()..addRRect(rrect.shift(const Offset(0, 1))),
      ),
      Paint()..color = color,
    );
  }

  @override
  bool shouldRepaint(_TopEdgePainter old) =>
      old.radius != radius || old.color != color;
}

/// Flutter's [BoxShadow.blurRadius] for a CSS blur of [px]: CSS blurs with a
/// Gaussian of sigma `px / 2`, Flutter with `radius * .57735 + .5`.
double _cssBlur(double px) => (px / 2 - .5) / .57735;
const double _blur10 = (10 / 2 - .5) / .57735;

// ─────────────────────────────────────────────────────────────────────────────
// Tabs
// ─────────────────────────────────────────────────────────────────────────────

/// A regular tab: glyph (popping on selection), optional badge, label that
/// collapses when the bar is compact, and the tap ripple.
class _TabCell extends StatefulWidget {
  const _TabCell({
    super.key,
    required this.item,
    required this.index,
    required this.on,
    required this.compact,
    required this.bump,
    required this.badge,
    required this.ripple,
    required this.onTap,
  });

  final V3TabItem item;
  final int index;
  final bool on;
  final bool compact;
  final int bump;
  final int badge;
  final ({int id, int k, Offset at})? ripple;
  final ValueChanged<Offset?> onTap;

  @override
  State<_TabCell> createState() => _TabCellState();
}

class _TabCellState extends State<_TabCell> {
  Offset? _down;

  @override
  Widget build(BuildContext context) {
    final motion = MotionConfig.enabled(context);
    final item = widget.item;
    final on = widget.on;
    final ripple = widget.ripple;

    Widget content = TweenAnimationBuilder<double>(
      // `gap .4s`, `max-height .4s` (default `ease`).
      tween: Tween<double>(end: widget.compact ? 1 : 0),
      duration: motion ? const Duration(milliseconds: 400) : Duration.zero,
      curve: Curves.ease,
      builder: (context, c, _) {
        final open = 1 - c.clamp(0.0, 1.0);
        return Padding(
          padding: EdgeInsets.only(bottom: 2 * open),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _TbPop(
                trigger: on ? widget.bump : -1,
                playOnMount: on,
                child: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    AnimatedOpacity(
                      opacity: on ? 1 : .5,
                      duration: motion
                          ? const Duration(milliseconds: 300)
                          : Duration.zero,
                      child: V3Icon(
                        item.icon!,
                        size: 19,
                        color: _white,
                        strokeWidth: on ? 2.2 : 1.8,
                        fill: on && item.fillWhenActive
                            ? const Color.fromRGBO(255, 255, 255, .12)
                            : null,
                      ),
                    ),
                    if (widget.badge > 0)
                      Positioned(
                        top: -5,
                        right: -9,
                        child: _Badge(count: widget.badge),
                      ),
                  ],
                ),
              ),
              SizedBox(height: 3 * open),
              ClipRect(
                child: Align(
                  alignment: Alignment.topCenter,
                  heightFactor: open,
                  child: _TabLabel(
                    index: widget.index,
                    text: item.label,
                    on: on,
                    compact: widget.compact,
                    motion: motion,
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );

    Widget button = V3Pressable(
      onTap: () => widget.onTap(_down),
      semanticLabel: item.label,
      selected: on,
      focusRadius: BorderRadius.circular(17),
      child: content,
    );
    if (widget.badge > 0) {
      // Say the count too, without changing the tab's name.
      button = MergeSemantics(
        child: Semantics(value: '${widget.badge} left', child: button),
      );
    }

    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: (event) => _down = event.localPosition,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(17),
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (ripple != null)
              Positioned(
                left: ripple.at.dx - 60,
                top: ripple.at.dy - 60,
                width: 120,
                height: 120,
                child: IgnorePointer(child: _TbRipple(key: ValueKey(ripple.k))),
              ),
            button,
          ],
        ),
      ),
    );
  }
}

/// The 9.5 pt tab label. Fades out (`opacity .3s`) when [compact]; its box
/// collapses separately in the caller.
class _TabLabel extends StatelessWidget {
  const _TabLabel({
    required this.index,
    required this.text,
    required this.on,
    required this.compact,
    required this.motion,
  });

  final int index;
  final String text;
  final bool on;
  final bool compact;
  final bool motion;

  @override
  Widget build(BuildContext context) {
    final fade = motion ? const Duration(milliseconds: 300) : Duration.zero;
    return AnimatedOpacity(
      key: ValueKey('tab-bar-label-$index'),
      opacity: compact ? 0 : 1,
      duration: fade,
      child: AnimatedDefaultTextStyle(
        duration: fade,
        style: AppTypography.sans(9.5, FontWeight.w600).copyWith(
          letterSpacing: 9.5 * .01,
          height: 1.2,
          color: on ? _white : _dim,
        ),
        child: Text(
          text,
          maxLines: 1,
          softWrap: false,
          overflow: TextOverflow.clip,
        ),
      ),
    );
  }
}

/// The Today count: an ember pill with a dark ring.
class _Badge extends StatelessWidget {
  const _Badge({required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    return Container(
      key: const Key('tab-bar-badge'),
      height: 16,
      constraints: const BoxConstraints(minWidth: 16),
      padding: const EdgeInsets.symmetric(horizontal: 4),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: AppColors.ember,
        borderRadius: BorderRadius.circular(99),
        border: Border.all(color: _night, width: 2),
      ),
      child: Text(
        '$count',
        maxLines: 1,
        style: AppTypography.sans(
          9.5,
          FontWeight.w700,
        ).merge(AppTypography.tnum).copyWith(color: _white, height: 1),
      ),
    );
  }
}

/// The centre tab: the mentor's portrait rising into the notch, its online
/// dot, the conic ember ring when current, and the "Mentor" label.
class _CentreTab extends StatelessWidget {
  const _CentreTab({
    required this.index,
    required this.item,
    required this.mentor,
    required this.on,
    required this.compact,
    required this.compactT,
    required this.bump,
    required this.onTap,
  });

  final int index;
  final V3TabItem item;
  final V3TabBarMentor mentor;
  final bool on;
  final bool compact;
  final double compactT;
  final int bump;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final motion = MotionConfig.enabled(context);
    return V3Pressable(
      onTap: onTap,
      semanticLabel: item.label,
      selected: on,
      // The portrait is not a `.press` element in the design.
      pressedScale: 1,
      minTapTarget: 0,
      focusRadius: BorderRadius.circular(23),
      child: SizedBox.expand(
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Positioned(
              top: V3TabBar.headroom - 14 - compactT,
              left: 0,
              right: 0,
              child: Center(
                child: _Orb(
                  mentor: mentor,
                  on: on,
                  bump: bump,
                  shrink: compactT,
                  motion: motion,
                ),
              ),
            ),
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: TweenAnimationBuilder<double>(
                tween: Tween<double>(end: compact ? 1 : 0),
                duration: motion
                    ? const Duration(milliseconds: 400)
                    : Duration.zero,
                curve: Curves.ease,
                builder: (context, c, _) {
                  final open = 1 - c.clamp(0.0, 1.0);
                  return Padding(
                    padding: EdgeInsets.only(bottom: 5 + 2 * open),
                    child: ClipRect(
                      child: Align(
                        alignment: Alignment.topCenter,
                        heightFactor: open,
                        child: _TabLabel(
                          index: index,
                          text: item.label,
                          on: on,
                          compact: compact,
                          motion: motion,
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The 46 pt portrait: padded ring (conic gradient when [on], else a 14%
/// white), the 40 pt portrait with its dark 2.5 pt border, the sage online dot,
/// and the ring pulse that plays when it is tapped.
class _Orb extends StatelessWidget {
  const _Orb({
    required this.mentor,
    required this.on,
    required this.bump,
    required this.shrink,
    required this.motion,
  });

  final V3TabBarMentor mentor;
  final bool on;
  final int bump;

  /// 0..1 spring-driven compaction; the portrait scales by up to 10% less.
  final double shrink;
  final bool motion;

  static const _conic = SweepGradient(
    // `conic-gradient(from 200deg, ...)` starts at 200deg clockwise from the
    // top; Flutter's sweep starts at 3 o'clock.
    transform: GradientRotation(110 * math.pi / 180),
    colors: [AppColors.ember, AppColors.gold, AppColors.iris, AppColors.ember],
  );

  static List<double> _grayContrast() {
    // `grayscale(1) contrast(1.1)`: luminance, then 1.1 * y + 255 * .5 * (1 - 1.1).
    const c = 1.1;
    const r = 0.2126 * c;
    const g = 0.7152 * c;
    const b = 0.0722 * c;
    const o = 255 * .5 * (1 - c);
    return const [
      r, g, b, 0, o, //
      r, g, b, 0, o,
      r, g, b, 0, o,
      0, 0, 0, 1, 0,
    ];
  }

  @override
  Widget build(BuildContext context) {
    final springy = motion ? const Duration(milliseconds: 450) : Duration.zero;
    final glow = motion ? const Duration(milliseconds: 400) : Duration.zero;
    final portrait = _TbPop(
      trigger: on ? bump : -1,
      playOnMount: on,
      child: Container(
        key: const Key('tab-bar-mentor-avatar'),
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(color: _night, width: 2.5),
        ),
        child: ClipOval(
          child: ColorFiltered(
            colorFilter: ColorFilter.matrix(_grayContrast()),
            child: V3Avatar(
              image: mentor.image,
              initials: mentor.initials,
              tint: mentor.tint,
              size: 35,
            ),
          ),
        ),
      ),
    );

    return TweenAnimationBuilder<double>(
      // `translateY(-2px) scale(1.04)` when current, `transform .45s spring`.
      tween: Tween<double>(end: on ? 1 : 0),
      duration: springy,
      curve: AppMotion.spring,
      builder: (context, lift, child) => Transform.translate(
        offset: Offset(0, -2 * lift),
        child: Transform.scale(
          scale: (1 + .04 * lift) * (1 - .1 * shrink),
          child: child,
        ),
      ),
      child: SizedBox(
        width: 46,
        height: 46,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Positioned.fill(
              child: ClipPath(
                clipper: const _OutsideCircleClipper(),
                child: AnimatedContainer(
                  duration: glow,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    // `0 10px 26px -6px oklch(.6 .17 42 / .75)` when current,
                    // `0 8px 20px -8px rgba(0,0,0,.6)` otherwise.
                    boxShadow: [
                      BoxShadow(
                        color: on
                            ? const Color.fromRGBO(208, 84, 24, .75)
                            : const Color.fromRGBO(0, 0, 0, .6),
                        offset: Offset(0, on ? 10 : 8),
                        blurRadius: _cssBlur(on ? 26 : 20),
                        spreadRadius: on ? -6 : -8,
                      ),
                    ],
                  ),
                ),
              ),
            ),
            Positioned.fill(
              child: DecoratedBox(
                key: const Key('tab-bar-mentor-ring'),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: on ? null : const Color.fromRGBO(255, 255, 255, .14),
                  gradient: on ? _conic : null,
                ),
                child: Padding(
                  padding: const EdgeInsets.all(3),
                  child: portrait,
                ),
              ),
            ),
            if (on && motion)
              Positioned.fill(
                child: IgnorePointer(child: _TbRing(key: ValueKey(bump))),
              ),
            Positioned(
              right: 0,
              bottom: 2,
              child: SizedBox(
                width: 11,
                height: 11,
                child: DecoratedBox(
                  key: const Key('tab-bar-online-dot'),
                  decoration: BoxDecoration(
                    color: AppColors.sage,
                    shape: BoxShape.circle,
                    border: Border.all(color: _night, width: 2),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// CSS box shadows are not painted under their own box; this clips a shadow
/// layer to everything outside the 46 pt circle so a translucent ring does
/// not darken.
class _OutsideCircleClipper extends CustomClipper<Path> {
  const _OutsideCircleClipper();

  @override
  Path getClip(Size size) => Path()
    ..fillType = PathFillType.evenOdd
    ..addRect(Rect.fromLTWH(-80, -80, size.width + 160, size.height + 160))
    ..addOval(Offset.zero & size);

  @override
  bool shouldReclip(_OutsideCircleClipper oldClipper) => false;
}

/// Limits touches on the centre tab to the pill and to the portrait that
/// rises above it, so the empty corners of the headroom still reach the page.
class _CentreHitClipper extends CustomClipper<Path> {
  const _CentreHitClipper({
    required this.pillHeight,
    required this.avatarTop,
    required this.scale,
  });

  final double pillHeight;
  final double avatarTop;
  final double scale;

  @override
  Path getClip(Size size) {
    final radius = 23 * scale;
    return Path()
      ..addRect(
        Rect.fromLTWH(0, size.height - pillHeight, size.width, pillHeight),
      )
      ..addOval(
        Rect.fromCircle(
          center: Offset(size.width / 2, avatarTop + 23),
          radius: radius,
        ),
      );
  }

  @override
  bool shouldReclip(_CentreHitClipper old) =>
      old.pillHeight != pillHeight ||
      old.avatarTop != avatarTop ||
      old.scale != scale;
}

// ─────────────────────────────────────────────────────────────────────────────
// Keyframes: tbPop, tbRing, tbRip
// ─────────────────────────────────────────────────────────────────────────────

/// `tbPop`: the glyph (or portrait) hops 5 pt, swells to 1.18, dips below 1
/// and settles, in .55 s with each leg on `--spring`. Plays once when it
/// becomes current and again on every tap of the current tab. Skipped under
/// reduced motion.
class _TbPop extends StatefulWidget {
  const _TbPop({
    required this.trigger,
    required this.playOnMount,
    required this.child,
  });

  /// A negative value is idle; any other value that changes replays the pop
  /// (CSS: `key={on ? 'on' + bump : 'off'}`).
  final int trigger;

  /// Whether to play when first built while already current.
  final bool playOnMount;
  final Widget child;

  @override
  State<_TbPop> createState() => _TbPopState();
}

class _TbPopState extends State<_TbPop> with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 550),
    value: 1,
  );
  bool _mounted = false;

  static final Animatable<double> _lift = TweenSequence<double>([
    for (final leg in const [
      (0.0, -5.0, 35.0),
      (-5.0, 1.0, 35.0),
      (1.0, 0.0, 30.0),
    ])
      TweenSequenceItem(
        tween: Tween<double>(
          begin: leg.$1,
          end: leg.$2,
        ).chain(CurveTween(curve: AppMotion.spring)),
        weight: leg.$3,
      ),
  ]);

  static final Animatable<double> _swell = TweenSequence<double>([
    for (final leg in const [
      (1.0, 1.18, 35.0),
      (1.18, 0.96, 35.0),
      (0.96, 1.0, 30.0),
    ])
      TweenSequenceItem(
        tween: Tween<double>(
          begin: leg.$1,
          end: leg.$2,
        ).chain(CurveTween(curve: AppMotion.spring)),
        weight: leg.$3,
      ),
  ]);

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_mounted) return;
    _mounted = true;
    if (widget.playOnMount &&
        widget.trigger >= 0 &&
        MotionConfig.enabled(context)) {
      _controller.forward(from: 0);
    }
  }

  @override
  void didUpdateWidget(_TbPop oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.trigger != oldWidget.trigger &&
        widget.trigger >= 0 &&
        MotionConfig.enabled(context)) {
      _controller.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      child: widget.child,
      // Always the same wrappers, so the child keeps its state at rest.
      builder: (context, child) => Transform.translate(
        offset: Offset(0, _lift.evaluate(_controller)),
        child: Transform.scale(
          scale: _swell.evaluate(_controller),
          child: child,
        ),
      ),
    );
  }
}

/// `tbRing`: the ember ring around the current portrait grows from .8 to 1.6
/// while fading from .7, over .8 s on `--out`. Mounted fresh on every tap.
class _TbRing extends StatefulWidget {
  const _TbRing({super.key});

  @override
  State<_TbRing> createState() => _TbRingState();
}

class _TbRingState extends State<_TbRing> with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 800),
  )..forward();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        final p = AppMotion.out.transform(_controller.value);
        return Opacity(
          opacity: .7 * (1 - p),
          child: Transform.scale(
            scale: .8 + .8 * p,
            child: DecoratedBox(
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(color: AppColors.ember, width: 2),
              ),
            ),
          ),
        );
      },
    );
  }
}

/// `tbRip`: a 120 pt white disc grows from the touch point while fading from
/// 35% to nothing, .6 s on `--out`. The cell clips it.
class _TbRipple extends StatefulWidget {
  const _TbRipple({super.key});

  @override
  State<_TbRipple> createState() => _TbRippleState();
}

class _TbRippleState extends State<_TbRipple>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 600),
  )..forward();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        final p = AppMotion.out.transform(_controller.value);
        return Opacity(
          opacity: .35 * (1 - p),
          child: Transform.scale(
            scale: p,
            child: const DecoratedBox(
              decoration: BoxDecoration(shape: BoxShape.circle, color: _white),
            ),
          ),
        );
      },
    );
  }
}
