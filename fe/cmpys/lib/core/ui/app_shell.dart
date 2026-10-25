import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/design_tokens.dart';
import '../../features/cmpys/state/cmpys_backend_sync.dart';
import '../../features/plan/presentation/book_narration_dock.dart';
import '../../features/plan/state/book_narration_remote_controller.dart';
import 'cmpys/cmpys_nav_icons.dart';
import 'motion/motion_config.dart';

/// One bottom surface: labelled navigation, or controls for active listening.
/// The floating dock is an overlay; branches reserve its measured height via
/// [AppShell.bottomNavClearance], including enlarged accessibility text.
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

class AppShell extends ConsumerStatefulWidget {
  const AppShell({super.key, required this.navigationShell});
  final StatefulNavigationShell navigationShell;

  static const _labelStyle = TextStyle(
    fontFamily: 'Plus Jakarta Sans',
    inherit: false,
    fontSize: 11,
    fontWeight: FontWeight.w600,
    letterSpacing: 0,
    height: 1.2,
  );

  static bool _largeLabels(BuildContext context) =>
      MediaQuery.textScalerOf(context).scale(11) > 16;
  static double _sideMargin(BuildContext context) =>
      _largeLabels(context) ? 4 : 12;
  static double _dockPadding(BuildContext context) =>
      _largeLabels(context) ? 2 : 6;

  static double _dockWidth(BuildContext context) =>
      (MediaQuery.sizeOf(context).width -
              MediaQuery.paddingOf(context).horizontal -
              _sideMargin(context) * 2)
          .clamp(0.0, 560.0);

  static ({double height, List<double> widths}) _layout(BuildContext context) {
    final available = _dockWidth(context) - _dockPadding(context) * 2 - 2;
    final painters = [
      for (final destination in appShellDestinations)
        TextPainter(
          text: TextSpan(text: destination.label, style: _labelStyle),
          textDirection: Directionality.of(context),
          textScaler: MediaQuery.textScalerOf(context),
        )..layout(),
    ];
    final desired = [
      for (final painter in painters)
        (painter.width + 5).clamp(48.0, double.infinity),
    ];
    final total = desired.fold<double>(0, (sum, width) => sum + width);
    final extra = (available - 240).clamp(0.0, double.infinity);
    final widths = [
      for (final width in desired)
        total <= available
            ? width + (available - total) / 5
            : 48 + extra * (width - 48) / (total - 240),
    ];
    var labelHeight = 0.0;
    for (var i = 0; i < painters.length; i++) {
      painters[i].layout(maxWidth: (widths[i] - 4).clamp(1.0, double.infinity));
      if (painters[i].height > labelHeight) labelHeight = painters[i].height;
      painters[i].dispose();
    }
    return (
      height: 40 + _dockPadding(context) * 2 + labelHeight,
      widths: widths,
    );
  }

  static double _pillHeight(BuildContext context) => _layout(context).height;

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
    final scope = context.dependOnInheritedWidgetOfExactType<_AppShellScope>();
    if (scope == null) return MediaQuery.paddingOf(context).bottom + 24 + extra;
    return scope.bottomClearance + extra;
  }

  /// Whether [context] belongs to one of the state-preserving shell branches.
  ///
  /// Full-screen readers use this to leave room for the floating tab bar while
  /// remaining mounted when another tab is selected.
  static bool isWithinShell(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<_AppShellScope>() != null;

  @override
  ConsumerState<AppShell> createState() => _AppShellState();
}

class _AppShellState extends ConsumerState<AppShell> {
  bool _hidden = false;
  double _scrollDistance = 0;
  int? _lastBranch;
  bool? _lastListening;

  StatefulNavigationShell get navigationShell => widget.navigationShell;

  void _showDock() {
    _scrollDistance = 0;
    if (_hidden) setState(() => _hidden = false);
  }

  bool _onScroll(ScrollNotification notification) {
    if (MediaQuery.accessibleNavigationOf(context) ||
        notification.metrics.axis != Axis.vertical) {
      return false;
    }
    // Only deliberate finger scrolling changes the dock. Narration autoscroll,
    // page transitions, and layout changes must not hide playback controls.
    if (notification is ScrollUpdateNotification &&
        notification.dragDetails != null) {
      final delta = notification.scrollDelta ?? 0;
      if (delta == 0) return false;
      if (_scrollDistance.sign != delta.sign) _scrollDistance = 0;
      _scrollDistance += delta;
      if (notification.metrics.pixels <= notification.metrics.minScrollExtent ||
          _scrollDistance <= -24) {
        _showDock();
      } else if (_scrollDistance >= 32 && !_hidden) {
        setState(() => _hidden = true);
      }
    }
    if (notification is ScrollEndNotification) _scrollDistance = 0;
    return false;
  }

  Widget _dockVisibility(Widget child) => IgnorePointer(
    ignoring: _hidden,
    child: ExcludeSemantics(
      excluding: _hidden,
      child: AnimatedSlide(
        offset: _hidden ? const Offset(0, 1.7) : Offset.zero,
        duration: MotionConfig.enabled(context)
            ? const Duration(milliseconds: 180)
            : Duration.zero,
        curve: Curves.easeOutCubic,
        child: AnimatedOpacity(
          opacity: _hidden ? 0 : 1,
          duration: MotionConfig.enabled(context)
              ? const Duration(milliseconds: 140)
              : Duration.zero,
          child: child,
        ),
      ),
    ),
  );

  @override
  Widget build(BuildContext context) {
    // Hydrate mentor + AI results from the backend on app entry, regardless
    // of which tab the user lands on first.
    ref.watch(cmpysBackendSyncProvider);
    final narrationRemote = ref.watch(bookNarrationRemoteControllerProvider);

    final keyboardOpen = MediaQuery.viewInsetsOf(context).bottom > 0;
    final listeningDockVisible = narrationRemote.active && !keyboardOpen;

    if (_lastBranch != navigationShell.currentIndex ||
        _lastListening != narrationRemote.active ||
        MediaQuery.accessibleNavigationOf(context)) {
      _hidden = false;
      _scrollDistance = 0;
    }
    _lastBranch = navigationShell.currentIndex;
    _lastListening = narrationRemote.active;

    return _AppShellScope(
      bottomClearance:
          (listeningDockVisible
              ? BookNarrationDock.preferredHeight
              : AppShell._pillHeight(context)) +
          AppShell._bottomMargin(context) +
          22,
      child: AnnotatedRegion<SystemUiOverlayStyle>(
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
                child: NotificationListener<ScrollNotification>(
                  onNotification: _onScroll,
                  child: _TabFade(
                    index: navigationShell.currentIndex,
                    child: navigationShell,
                  ),
                ),
              ),
              if (!keyboardOpen && !listeningDockVisible)
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 0,
                  child: _dockVisibility(
                    _FloatingPillNav(
                      currentIndex: navigationShell.currentIndex,
                      onTap: (index) {
                        HapticFeedback.selectionClick();
                        navigationShell.goBranch(
                          index,
                          initialLocation:
                              index == navigationShell.currentIndex,
                        );
                      },
                    ),
                  ),
                ),
              if (listeningDockVisible)
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: AppShell._bottomMargin(context),
                  child: _dockVisibility(
                    SafeArea(
                      top: false,
                      bottom: false,
                      child: BookNarrationDock(
                        controller: narrationRemote,
                        maxWidth: 560,
                        margin: const EdgeInsets.symmetric(horizontal: 12),
                        onOpenNavigation: () => _openNavigation(context),
                      ),
                    ),
                  ),
                ),
              if (_hidden && !keyboardOpen)
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: MediaQuery.paddingOf(context).bottom,
                  child: Center(
                    child: GestureDetector(
                      onVerticalDragUpdate: (details) {
                        if (details.delta.dy < -2) _showDock();
                      },
                      child: IconButton(
                        key: const Key('reveal-bottom-menu'),
                        tooltip: 'Show bottom controls',
                        onPressed: _showDock,
                        style: IconButton.styleFrom(
                          backgroundColor: AppColors.card,
                          minimumSize: const Size(64, 44),
                          side: const BorderSide(color: AppColors.hair),
                        ),
                        icon: const Icon(Icons.keyboard_arrow_up_rounded),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _openNavigation(BuildContext context) async {
    final destination = await showModalBottomSheet<int>(
      context: context,
      useRootNavigator: true,
      useSafeArea: true,
      isScrollControlled: true,
      backgroundColor: AppColors.card,
      constraints: const BoxConstraints(maxWidth: 560),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (sheetContext) => SafeArea(
        top: false,
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.sizeOf(sheetContext).height * .8,
          ),
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text('App menu', style: AppTypography.bodyMedium),
                    ),
                    IconButton(
                      tooltip: 'Close app menu',
                      onPressed: () => Navigator.pop(sheetContext),
                      icon: const Icon(Icons.close_rounded),
                    ),
                  ],
                ),
                for (var i = 0; i < appShellDestinations.length; i++)
                  ListTile(
                    key: ValueKey('listening-nav-item-$i'),
                    selected: navigationShell.currentIndex == i,
                    selectedColor: AppColors.green2,
                    selectedTileColor: AppColors.greenSoft,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                    leading: CmpysNavIcon(
                      appShellDestinations[i].glyph,
                      color: navigationShell.currentIndex == i
                          ? AppColors.green2
                          : AppColors.ink2,
                    ),
                    title: Text(appShellDestinations[i].label),
                    trailing: navigationShell.currentIndex == i
                        ? const Icon(Icons.check_rounded, size: 20)
                        : null,
                    onTap: () => Navigator.pop(sheetContext, i),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
    if (!context.mounted || destination == null) return;
    HapticFeedback.selectionClick();
    // Preserve the reader route, even when its currently selected tab is tapped.
    // Resetting that branch would dispose the owner and interrupt narration.
    navigationShell.goBranch(destination);
  }
}

class _AppShellScope extends InheritedWidget {
  const _AppShellScope({required this.bottomClearance, required super.child});

  final double bottomClearance;

  @override
  bool updateShouldNotify(_AppShellScope oldWidget) =>
      bottomClearance != oldWidget.bottomClearance;
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

  @override
  Widget build(BuildContext context) {
    final layout = AppShell._layout(context);
    return SafeArea(
      top: false,
      bottom: false,
      child: Padding(
        padding: EdgeInsets.only(
          bottom: AppShell._bottomMargin(context),
          left: AppShell._sideMargin(context),
          right: AppShell._sideMargin(context),
        ),
        child: Center(
          child: Container(
            width: AppShell._dockWidth(context),
            height: layout.height,
            padding: EdgeInsets.all(AppShell._dockPadding(context)),
            decoration: BoxDecoration(
              color: AppColors.card,
              borderRadius: BorderRadius.circular(28),
              border: Border.all(color: AppColors.hair),
              boxShadow: AppShadows.tabPill,
            ),
            child: AnimatedBuilder(
              animation: _selectorController,
              builder: (context, _) {
                final lower = _selectorPosition.floor().clamp(0, 4);
                final upper = _selectorPosition.ceil().clamp(0, 4);
                final fraction = _selectorPosition - lower;
                final start = layout.widths
                    .take(lower)
                    .fold<double>(0, (sum, w) => sum + w);
                return Stack(
                  children: [
                    PositionedDirectional(
                      start:
                          start +
                          (upper == lower
                              ? 0
                              : layout.widths[lower] * fraction),
                      top: 0,
                      width:
                          layout.widths[lower] +
                          (layout.widths[upper] - layout.widths[lower]) *
                              fraction,
                      bottom: 0,
                      child: DecoratedBox(
                        key: const ValueKey('floating-nav-selector'),
                        decoration: BoxDecoration(
                          color: AppColors.greenSoft,
                          borderRadius: BorderRadius.circular(21),
                        ),
                      ),
                    ),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        for (var i = 0; i < appShellDestinations.length; i++)
                          SizedBox(
                            key: ValueKey('floating-nav-item-$i'),
                            width: layout.widths[i],
                            child: _NavChip(
                              glyph: appShellDestinations[i].glyph,
                              label: appShellDestinations[i].label,
                              selected: widget.currentIndex == i,
                              onTap: () => widget.onTap(i),
                            ),
                          ),
                      ],
                    ),
                  ],
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}

class _NavChip extends StatelessWidget {
  const _NavChip({
    required this.glyph,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final CmpysNavGlyph glyph;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final foreground = selected ? AppColors.green2 : AppColors.ink2;
    return Semantics(
      label: label,
      button: true,
      selected: selected,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(21),
          child: ExcludeSemantics(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 6),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  CmpysNavIcon(
                    glyph,
                    size: 22,
                    color: foreground,
                    strokeWidth: selected ? 2 : 1.7,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    label,
                    textAlign: TextAlign.center,
                    style: AppShell._labelStyle.copyWith(color: foreground),
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
