import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/design_tokens.dart';
import '../../features/cmpys/state/cmpys_backend_sync.dart';
import 'cmpys/cmpys_nav_icons.dart';
import 'motion/motion_config.dart';

/// CMPYS floating tab bar.
///
/// Pill-shaped, opaque-white, with a single green pill for the active tab
/// (icon + label) and circular icon-only chips for the inactive ones — the
/// Deepstash/Wiser 2026 look from the design. Icons are exact traces of the
/// design's SVG glyphs (see [CmpysNavIcon]).
///
/// **Layout note**: the nav is rendered via a `Stack` + bottom-pinned
/// `Positioned`, not `Scaffold.bottomNavigationBar`, which can collide with
/// nested `Scaffold`s in tab screens.
@visibleForTesting
class AppShellDestination {
  const AppShellDestination({required this.glyph, required this.label});

  final CmpysNavGlyph glyph;
  final String label;
}

// Router branch order is: home / plan / chat / vault / profile.
// CMPYS design tabs (verbatim): Today · Plan · Chat · Compare · You.
@visibleForTesting
const appShellDestinations = [
  AppShellDestination(glyph: CmpysNavGlyph.today, label: 'Today'),
  AppShellDestination(glyph: CmpysNavGlyph.plan, label: 'Plan'),
  AppShellDestination(glyph: CmpysNavGlyph.chat, label: 'Chat'),
  AppShellDestination(glyph: CmpysNavGlyph.compare, label: 'Compare'),
  AppShellDestination(glyph: CmpysNavGlyph.you, label: 'You'),
];

class AppShell extends ConsumerWidget {
  const AppShell({super.key, required this.navigationShell});
  final StatefulNavigationShell navigationShell;

  /// Height of the pill itself (48 chip + 6 padding top & bottom).
  static const double _pillHeight = 60.0;

  /// Gap between the floating nav and the bottom safe-area edge.
  ///
  /// Shared by [_FloatingPillNav] (its outer margin) and
  /// [bottomNavClearance] so the two never drift apart.
  static double _bottomMargin(BuildContext context) {
    final bottomSafe = MediaQuery.of(context).padding.bottom;
    return bottomSafe > 0 ? bottomSafe + 6.0 : 18.0;
  }

  /// Vertical space the floating pill nav occupies at the bottom of the screen.
  ///
  /// The nav is a `Stack` overlay (see class docs), so it sits *on top* of the
  /// branch content rather than reserving layout space. Any scroll view or
  /// bottom-pinned control inside a shell screen must add this as bottom
  /// padding so its last item / button clears the nav instead of hiding
  /// underneath it. Pass [extra] for additional breathing room.
  static double bottomNavClearance(BuildContext context, {double extra = 0}) {
    // The floating nav is hidden while the keyboard is open. Keeping its full
    // clearance would leave a large dead zone above text fields/composers.
    if (MediaQuery.viewInsetsOf(context).bottom > 0) return 12.0 + extra;
    return _pillHeight + _bottomMargin(context) + 22.0 + extra;
  }

  @visibleForTesting
  static bool useIconOnlyNavigation(double width, double scaledLabelSize) =>
      width < 380 || scaledLabelSize > 16;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Hydrate mentor + AI results from the backend on app entry, regardless
    // of which tab the user lands on first.
    ref.watch(cmpysBackendSyncProvider);

    final keyboardOpen = MediaQuery.viewInsetsOf(context).bottom > 0;

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarBrightness: Brightness.light,
        statusBarIconBrightness: Brightness.dark,
        systemNavigationBarColor: AppColors.paper,
        systemNavigationBarIconBrightness: Brightness.dark,
        systemNavigationBarDividerColor: AppColors.paper,
      ),
      child: Scaffold(
        // Each branch owns its keyboard inset. Resizing this outer scaffold as
        // well would apply the same inset twice to nested branch Scaffolds and
        // create a large blank band above the keyboard.
        resizeToAvoidBottomInset: false,
        backgroundColor: AppColors.paper,
        body: Stack(
          children: [
            Positioned.fill(
              child: _TabFade(
                index: navigationShell.currentIndex,
                child: navigationShell,
              ),
            ),
            if (!keyboardOpen)
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                child: _FloatingPillNav(
                  currentIndex: navigationShell.currentIndex,
                  onTap: (index) {
                    HapticFeedback.selectionClick();
                    navigationShell.goBranch(
                      index,
                      initialLocation: index == navigationShell.currentIndex,
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

class _FloatingPillNav extends StatefulWidget {
  const _FloatingPillNav({required this.currentIndex, required this.onTap});
  final int currentIndex;
  final ValueChanged<int> onTap;

  @override
  State<_FloatingPillNav> createState() => _FloatingPillNavState();
}

class _FloatingPillNavState extends State<_FloatingPillNav>
    with SingleTickerProviderStateMixin {
  static const _itemGap = 3.0;
  static const _labelStyle = TextStyle(
    fontFamily: 'Plus Jakarta Sans',
    fontSize: 14,
    fontWeight: FontWeight.w600,
    letterSpacing: -0.1,
  );

  late final AnimationController _selectorController = AnimationController(
    vsync: this,
    duration: AppDurations.normal,
    value: 1,
  );
  late double _selectorFrom;
  late double _selectorTo;
  bool _motionEnabled = true;

  @override
  void initState() {
    super.initState();
    _selectorFrom = widget.currentIndex.toDouble();
    _selectorTo = _selectorFrom;
  }

  double get _selectorPosition {
    final eased = AppCurves.easeOut.transform(_selectorController.value);
    return _selectorFrom + (_selectorTo - _selectorFrom) * eased;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final enabled = MotionConfig.enabled(context);
    if (_motionEnabled && !enabled) {
      final target = widget.currentIndex.toDouble();
      _selectorController.stop();
      _selectorFrom = target;
      _selectorTo = target;
      _selectorController.value = 1;
    }
    _motionEnabled = enabled;
  }

  @override
  void didUpdateWidget(_FloatingPillNav oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.currentIndex == widget.currentIndex) return;

    final target = widget.currentIndex.toDouble();
    if (!_motionEnabled) {
      _selectorController.stop();
      _selectorFrom = target;
      _selectorTo = target;
      _selectorController.value = 1;
      return;
    }

    final current = _selectorPosition;
    final distance = (target - current).abs();
    final extraDistance = (distance - 1).clamp(0, 3);
    _selectorFrom = current;
    _selectorTo = target;
    _selectorController.duration = Duration(
      milliseconds:
          AppDurations.normal.inMilliseconds + (extraDistance * 45).round(),
    );
    _selectorController.forward(from: 0);
  }

  @override
  void dispose() {
    _selectorController.dispose();
    super.dispose();
  }

  double _activeItemWidth(BuildContext context, String label) {
    final painter = TextPainter(
      text: TextSpan(text: label, style: _labelStyle),
      maxLines: 1,
      textDirection: Directionality.of(context),
      textScaler: MediaQuery.textScalerOf(context),
    )..layout();
    // 15 left + 22 icon + 8 gap + label + 18 right.
    return 63 + painter.width;
  }

  @override
  Widget build(BuildContext context) {
    final bottomMargin = AppShell._bottomMargin(context);
    final width = MediaQuery.sizeOf(context).width;
    final scaledLabelSize = MediaQuery.textScalerOf(context).scale(14);
    final iconOnly = AppShell.useIconOnlyNavigation(width, scaledLabelSize);
    final activeWidths = [
      for (final destination in appShellDestinations)
        iconOnly ? 44.0 : _activeItemWidth(context, destination.label),
    ];

    return Padding(
      padding: EdgeInsets.only(
        bottom: bottomMargin,
        left: iconOnly ? 10 : 16,
        right: iconOnly ? 10 : 16,
      ),
      child: Center(
        child: AnimatedBuilder(
          animation: _selectorController,
          builder: (context, _) {
            final geometry = _FloatingNavGeometry.calculate(
              position: _selectorPosition,
              activeWidths: activeWidths,
              iconOnly: iconOnly,
              itemGap: _itemGap,
            );

            return Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: const Color(0xFAFFFFFF),
                borderRadius: BorderRadius.circular(999),
                border: Border.all(color: AppColors.hair),
                boxShadow: AppShadows.tabPill,
              ),
              child: SizedBox(
                width: geometry.totalWidth,
                height: 48,
                child: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    Positioned(
                      left: geometry.selectorLeft,
                      top: 0,
                      width: geometry.selectorWidth,
                      height: 48,
                      child: DecoratedBox(
                        key: const ValueKey('floating-nav-selector'),
                        decoration: BoxDecoration(
                          color: AppColors.green,
                          borderRadius: BorderRadius.circular(999),
                          boxShadow: [
                            BoxShadow(
                              color: AppColors.green2.withValues(alpha: 0.34),
                              blurRadius: 12,
                              offset: const Offset(0, 4),
                            ),
                          ],
                        ),
                      ),
                    ),
                    Row(
                      children: [
                        for (
                          var i = 0;
                          i < appShellDestinations.length;
                          i++
                        ) ...[
                          if (i > 0) const SizedBox(width: _itemGap),
                          SizedBox(
                            key: ValueKey('floating-nav-item-$i'),
                            width: geometry.itemWidths[i],
                            height: 48,
                            child: _NavChip(
                              glyph: appShellDestinations[i].glyph,
                              label: appShellDestinations[i].label,
                              selected: widget.currentIndex == i,
                              selectionProgress: geometry.selectionProgress[i],
                              iconOnly: iconOnly,
                              onTap: () => widget.onTap(i),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

class _FloatingNavGeometry {
  const _FloatingNavGeometry({
    required this.itemWidths,
    required this.selectionProgress,
    required this.selectorLeft,
    required this.selectorWidth,
    required this.totalWidth,
  });

  final List<double> itemWidths;
  final List<double> selectionProgress;
  final double selectorLeft;
  final double selectorWidth;
  final double totalWidth;

  static _FloatingNavGeometry calculate({
    required double position,
    required List<double> activeWidths,
    required bool iconOnly,
    required double itemGap,
  }) {
    final lastIndex = activeWidths.length - 1;
    final clampedPosition = position.clamp(0, lastIndex.toDouble()).toDouble();
    final baseWidth = iconOnly ? 44.0 : 48.0;
    final selectionProgress = [
      for (var i = 0; i < activeWidths.length; i++)
        (1 - (clampedPosition - i).abs()).clamp(0, 1).toDouble(),
    ];
    final itemWidths = [
      for (var i = 0; i < activeWidths.length; i++)
        _lerp(baseWidth, activeWidths[i], selectionProgress[i]),
    ];
    final lower = clampedPosition.floor().clamp(0, lastIndex).toInt();
    final upper = clampedPosition.ceil().clamp(0, lastIndex).toInt();
    final fraction = clampedPosition - lower;
    final totalWidth =
        itemWidths.fold<double>(0, (sum, value) => sum + value) +
        itemGap * lastIndex;
    // Interpolate the selector in the dock's *global* coordinate space, then
    // translate it back into the currently morphing dock. Deriving its left
    // edge from the temporary item widths can introduce a tiny end-of-travel
    // overshoot as the centered dock changes width.
    double endpointLeftFromCenter(int index) {
      final endpointTotalWidth =
          baseWidth * activeWidths.length +
          (activeWidths[index] - baseWidth) +
          itemGap * lastIndex;
      final endpointLocalLeft = index * (baseWidth + itemGap);
      return endpointLocalLeft - endpointTotalWidth / 2;
    }

    final selectorLeftFromCenter = _lerp(
      endpointLeftFromCenter(lower),
      endpointLeftFromCenter(upper),
      fraction,
    );
    final selectorLeft = selectorLeftFromCenter + totalWidth / 2;
    final selectorWidth = _lerp(
      activeWidths[lower],
      activeWidths[upper],
      fraction,
    );

    return _FloatingNavGeometry(
      itemWidths: itemWidths,
      selectionProgress: selectionProgress,
      selectorLeft: selectorLeft,
      selectorWidth: selectorWidth,
      totalWidth: totalWidth,
    );
  }

  static double _lerp(double begin, double end, double t) =>
      begin + (end - begin) * t;
}

class _NavChip extends StatelessWidget {
  const _NavChip({
    required this.glyph,
    required this.label,
    required this.selected,
    required this.selectionProgress,
    required this.iconOnly,
    required this.onTap,
  });

  final CmpysNavGlyph glyph;
  final String label;
  final bool selected;
  final double selectionProgress;
  final bool iconOnly;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final progress = selectionProgress.clamp(0.0, 1.0).toDouble();
    final foreground = Color.lerp(AppColors.ink3, Colors.white, progress)!;
    final labelProgress = iconOnly ? 0.0 : progress;

    return Semantics(
      label: label,
      button: true,
      selected: selected,
      child: Tooltip(
        message: iconOnly ? label : '',
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(999),
            child: ExcludeSemantics(
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                mainAxisSize: MainAxisSize.min,
                children: [
                  CmpysNavIcon(
                    glyph,
                    size: 23 - progress,
                    color: foreground,
                    strokeWidth: 1.7 + 0.3 * progress,
                  ),
                  if (!iconOnly)
                    ClipRect(
                      child: Align(
                        widthFactor: labelProgress,
                        child: Opacity(
                          opacity: labelProgress,
                          child: Padding(
                            padding: const EdgeInsets.only(left: 8),
                            child: Text(
                              label,
                              maxLines: 1,
                              style: _FloatingPillNavState._labelStyle.copyWith(
                                color: foreground,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Fades the incoming branch in on tab switch (the IndexedStack swap is
/// otherwise a hard cut). The outgoing branch disappears instantly —
/// duplicating the shell tree for a cross-fade would break its GlobalKeys.
class _TabFade extends StatefulWidget {
  const _TabFade({required this.index, required this.child});

  final int index;
  final Widget child;

  @override
  State<_TabFade> createState() => _TabFadeState();
}

class _TabFadeState extends State<_TabFade>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: AppDurations.fast,
    value: 1,
  );

  @override
  void didUpdateWidget(_TabFade oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.index != widget.index && MotionConfig.enabled(context)) {
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
    return FadeTransition(
      opacity: CurvedAnimation(parent: _controller, curve: AppCurves.easeOut),
      child: widget.child,
    );
  }
}
