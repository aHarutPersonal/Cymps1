import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/design_tokens.dart';
import '../../features/cmpys/data/cmpys_seed.dart';
import '../../features/cmpys/data/record_restore.dart';
import '../../features/cmpys/state/cmpys_backend_sync.dart';
import '../../features/cmpys/state/cmpys_store.dart';
import '../../features/plan/presentation/book_narration_dock.dart';
import '../../features/plan/state/book_narration_remote_controller.dart';
import '../../features/plan/state/current_plan_provider.dart';
import 'cmpys/cmpys_nav_icons.dart';
import 'haptics.dart';
import 'motion/motion_config.dart';
import 'narration_dock_page.dart';
import 'v3/icons.dart';
import 'v3/motion.dart';
import 'v3/surfaces.dart';
import 'v3/tab_bar.dart';

/// One bottom surface: the floating v3 tab bar, or controls for active
/// listening. Both float over the branches; [AppShell.bottomNavClearance]
/// tells a branch how much room to leave under its content.
@visibleForTesting
class AppShellDestination {
  const AppShellDestination({required this.glyph, required this.label});

  final CmpysNavGlyph glyph;
  final String label;
}

// Router branch order is: home / plan / chat / vault / profile.
// CMPYS v3 tabs (verbatim from `v3/app.jsx`): Today · Plan · Mentor · Compare ·
// You. The centre tab keeps its `chat` glyph; the bar itself shows the
// mentor's portrait there.
@visibleForTesting
const appShellDestinations = [
  AppShellDestination(glyph: CmpysNavGlyph.today, label: 'Today'),
  AppShellDestination(glyph: CmpysNavGlyph.plan, label: 'Plan'),
  AppShellDestination(glyph: CmpysNavGlyph.chat, label: 'Mentor'),
  AppShellDestination(glyph: CmpysNavGlyph.compare, label: 'Compare'),
  AppShellDestination(glyph: CmpysNavGlyph.you, label: 'You'),
];

/// Index of the Mentor (chat) branch: no paper fades, centre of the bar.
const int _kMentorBranch = 2;

final List<V3TabItem> _tabItems = [
  for (final destination in appShellDestinations)
    V3TabItem(
      label: destination.label,
      icon: destination.glyph == CmpysNavGlyph.chat
          ? null
          : destination.glyph.icon,
      // The design fills the active glyph on every tab but Plan and Compare.
      fillWhenActive:
          destination.glyph != CmpysNavGlyph.plan &&
          destination.glyph != CmpysNavGlyph.compare,
    ),
];

/// Tells the shell whether a full-screen page sits on top of a branch's root
/// page, so the tab bar can slide away and the paper fades step aside.
///
/// Attach one to each `StatefulShellBranch` (`observers: [ShellPushObserver()]`).
/// Only page routes count: a dialog, menu or sheet is not a detail screen.
/// Routes pushed on the root navigator are not seen here; they cover the whole
/// shell and need no help.
class ShellPushObserver extends NavigatorObserver {
  final ValueNotifier<bool> _pushed = ValueNotifier<bool>(false);
  final ValueNotifier<Route<dynamic>?> _top = ValueNotifier<Route<dynamic>?>(
    null,
  );

  /// Pushed pages, bottom to top.
  final List<Route<dynamic>> _pages = <Route<dynamic>>[];

  /// True while at least one page route is above the branch's root page.
  ValueListenable<bool> get pushed => _pushed;

  /// The page route on top of the branch's root page; null on the root.
  ValueListenable<Route<dynamic>?> get top => _top;

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    // The first route is the branch's own page.
    if (previousRoute != null && route is PageRoute) _pages.add(route);
    _publish();
  }

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    _pages.remove(route);
    _publish();
  }

  @override
  void didRemove(Route<dynamic> route, Route<dynamic>? previousRoute) {
    _pages.remove(route);
    _publish();
  }

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) {
    // A pushed page stays a pushed page; a replaced root page stays the root.
    final index = oldRoute == null ? -1 : _pages.indexOf(oldRoute);
    if (index >= 0) {
      if (newRoute is PageRoute) {
        _pages[index] = newRoute;
      } else {
        _pages.removeAt(index);
      }
    }
    _publish();
  }

  /// Navigators report changes while they build (declarative pages) as well as
  /// from event handlers. Listeners rebuild widgets, so outside an idle frame
  /// the notification waits for the end of the frame.
  void _publish() {
    final binding = SchedulerBinding.instance;
    void publish() {
      _pushed.value = _pages.isNotEmpty;
      _top.value = _pages.isEmpty ? null : _pages.last;
    }

    if (binding.schedulerPhase == SchedulerPhase.idle) {
      publish();
      return;
    }
    binding
      ..addPostFrameCallback((_) => publish())
      ..ensureVisualUpdate();
  }
}

/// The five-tab shell: the router's branches with the floating [V3TabBar] over
/// them and, while a book is narrated, the narration dock above the bar.
///
/// The bar goes compact while a tab scrolls down and slides away while a page
/// is pushed on the branch (see [ShellPushObserver]); the dock then drops to
/// the bar's place (design: dock bottom 90 over the bar, 30 without it). The
/// dock stays off the Mentor tab. Tab screens also get top and bottom paper
/// fades, except the Mentor (chat) tab.
class AppShell extends ConsumerStatefulWidget {
  const AppShell({super.key, required this.navigationShell});
  final StatefulNavigationShell navigationShell;

  /// Distance from the bottom of the screen to the narration dock: 70 pt
  /// above the tab bar's baseline while the bar shows (design 90 over its
  /// 20), 10 pt above it when the bar is hidden (design 30).
  static double _dockBottom(double safeBottom, {required bool lifted}) =>
      V3TabBar.bottomOffsetFor(safeBottom) + (lifted ? 70 : 10);

  /// Vertical space the floating bar occupies at the bottom of the screen.
  ///
  /// The bar is a `Stack` overlay (see class docs), so it sits *on top* of the
  /// branch content rather than reserving layout space. Any scroll view or
  /// bottom-pinned control inside a shell screen must add this as bottom
  /// padding so its last item / button clears the bar instead of hiding
  /// underneath it. Pass [extra] for additional breathing room.
  ///
  /// The value does not change when the bar goes compact or slides away, so
  /// content never jumps while scrolling.
  static double bottomNavClearance(BuildContext context, {double extra = 0}) {
    // The floating nav is hidden while the keyboard is open. Keeping its full
    // clearance would leave a large dead zone above text fields/composers.
    if (MediaQuery.viewInsetsOf(context).bottom > 0) return 12.0 + extra;
    final scope = context.dependOnInheritedWidgetOfExactType<_AppShellScope>();
    if (scope == null) return MediaQuery.paddingOf(context).bottom + 24 + extra;
    return scope.bottomClearance + extra;
  }

  /// The shell's App menu, which switches tabs while a pushed reader stays
  /// mounted and keeps narrating; null outside the shell.
  static Future<void> Function()? appMenuOf(BuildContext context) =>
      context.getInheritedWidgetOfExactType<_AppShellScope>()?.openAppMenu;

  /// Whether [context] belongs to one of the state-preserving shell branches.
  ///
  /// Full-screen readers use this to leave room for the floating tab bar while
  /// remaining mounted when another tab is selected.
  static bool isWithinShell(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<_AppShellScope>() != null;

  /// Key on the transform that moves the incoming tab in, for tests.
  @visibleForTesting
  static const tabTransitionKey = Key('app-shell-tab-transition');

  @override
  ConsumerState<AppShell> createState() => _AppShellState();
}

class _AppShellState extends ConsumerState<AppShell> {
  /// Tab bar compact: scrolling down more than 8 px past 60 px.
  bool _compact = false;
  double _compactRun = 0;

  int? _lastBranch;
  bool? _lastPushed;

  /// Per-branch [ShellPushObserver], null where the router has none.
  List<ShellPushObserver?> _observers = const [];

  /// The dock's measured height: 66 pt, taller with large text.
  double _dockHeight = BookNarrationDock.preferredHeight;

  StatefulNavigationShell get navigationShell => widget.navigationShell;

  @override
  void initState() {
    super.initState();
    _attachObservers();
    NarrationDockPage.changes.addListener(_onPushedChanged);
  }

  @override
  void didUpdateWidget(AppShell oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.navigationShell.route != navigationShell.route) {
      _attachObservers();
    }
  }

  @override
  void dispose() {
    _detachObservers();
    NarrationDockPage.changes.removeListener(_onPushedChanged);
    super.dispose();
  }

  void _attachObservers() {
    _detachObservers();
    _observers = [
      for (final branch in navigationShell.route.branches)
        branch.observers?.whereType<ShellPushObserver>().firstOrNull,
    ];
    for (final observer in _observers) {
      observer?.top.addListener(_onPushedChanged);
    }
  }

  void _detachObservers() {
    for (final observer in _observers) {
      observer?.top.removeListener(_onPushedChanged);
    }
  }

  void _onPushedChanged() {
    if (mounted) setState(() {});
  }

  /// A page sits above the current branch's root page.
  bool get _pushed => _topPage != null;

  /// The page on top of the current branch's root page.
  Route<dynamic>? get _topPage {
    final index = navigationShell.currentIndex;
    return index < _observers.length ? _observers[index]?.top.value : null;
  }

  void _setCompact(bool value) {
    _compactRun = 0;
    if (_compact != value) setState(() => _compact = value);
  }

  /// `Compact tab bar when scrolling down >8px past 60px in a tab's scroll
  /// view, restored on scroll up or near the bottom` (v3/app.jsx).
  void _trackCompact(ScrollUpdateNotification notification) {
    final delta = notification.scrollDelta ?? 0;
    if (delta == 0 || _pushed) return;
    if (_compactRun.sign != delta.sign) _compactRun = 0;
    _compactRun += delta;
    final metrics = notification.metrics;
    final bool? wanted;
    if (metrics.extentAfter < 20 || _compactRun <= -8) {
      wanted = false;
    } else if (_compactRun >= 8 && metrics.pixels > 60) {
      wanted = true;
    } else {
      wanted = null;
    }
    if (wanted == null || wanted == _compact) return;
    // Sheets, dialogs and menus can sit in the branch navigator too; only the
    // branch's own pages drive the bar.
    final scrollContext = notification.context;
    if (scrollContext != null && ModalRoute.of(scrollContext) is! PageRoute) {
      return;
    }
    _setCompact(wanted);
  }

  bool _onScroll(ScrollNotification notification) {
    if (MediaQuery.accessibleNavigationOf(context) ||
        notification.metrics.axis != Axis.vertical) {
      return false;
    }
    if (notification is ScrollUpdateNotification) _trackCompact(notification);
    return false;
  }

  /// The centre tab's portrait: a network photo when the idol has one, else
  /// the bundled portrait, else null (the bar then shows initials). Mirrors
  /// `CmpysMentorAvatar` so both places resolve a mentor the same way.
  ImageProvider? _mentorImage(CmpysIdol idol) {
    final explicit = idol.imageUrl?.trim();
    final remote = explicit != null && explicit.isNotEmpty
        ? explicit
        : (idol.slug.startsWith('https://') ? idol.slug : null);
    if (remote != null && remote.isNotEmpty) return NetworkImage(remote);
    final slug = idol.slug.trim();
    if (slug.isEmpty || slug == '__llm__') return null;
    return AssetImage('assets/images/mentors/$slug.png');
  }

  @override
  Widget build(BuildContext context) {
    // Hydrate mentor + AI results from the backend on app entry, regardless
    // of which tab the user lands on first.
    ref.watch(cmpysBackendSyncProvider);
    // Restore the account's synced wins into the Record (once per sign-in
    // and per cold start).
    ref.watch(cmpysRecordRestoreProvider);
    // Only the session's start and end matter here; the dock listens to the
    // remote itself, so word events do not rebuild the shell.
    final narrationActive = ref.watch(
      bookNarrationRemoteControllerProvider.select((remote) => remote.active),
    );
    final narrationRemote = ref.read(bookNarrationRemoteControllerProvider);
    final mentor = ref.watch(cmpysStoreProvider.select((s) => s.idol));
    // The Today badge: habits not done today. Hidden until the plan and
    // today's view have loaded; previous data stays while it refreshes.
    final habitsLeft = ref.watch(
      todayViewProvider.select(
        (today) =>
            today.valueOrNull?.items.where((i) => !i.completedToday).length ??
            0,
      ),
    );

    final keyboardOpen = MediaQuery.viewInsetsOf(context).bottom > 0;
    final branch = navigationShell.currentIndex;
    final pushed = _pushed;
    final safe = MediaQuery.paddingOf(context);
    // `Narration dock shows on tabs (except chat)` and on pushed pages; it is
    // lifted above the tab bar while the bar shows (v3/app.jsx).
    // …and only over the book, library, mission and record pages.
    final topPage = _topPage;
    final listeningDockVisible =
        narrationActive &&
        !keyboardOpen &&
        (topPage == null
            ? branch != _kMentorBranch
            : NarrationDockPage.allows(topPage));
    final dockBottom = AppShell._dockBottom(safe.bottom, lifted: !pushed);
    final motion = MotionConfig.enabled(context);

    // The bar always restores on a tab change, when a page is pushed or
    // popped, and for screen readers.
    if (_lastBranch != branch ||
        _lastPushed != pushed ||
        MediaQuery.accessibleNavigationOf(context)) {
      _compact = false;
      _compactRun = 0;
    }
    _lastBranch = branch;
    _lastPushed = pushed;

    // Paper fades belong to the tab screens: not the Mentor tab, which has its
    // own composer, and not a page pushed over a tab.
    final fades = branch != _kMentorBranch && !pushed;

    return _AppShellScope(
      openAppMenu: _openAppMenu,
      bottomClearance: listeningDockVisible
          ? dockBottom + _dockHeight + 22
          : V3TabBar.clearanceFor(safe.bottom),
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
                  child: _TabFade(index: branch, child: navigationShell),
                ),
              ),
              Positioned(
                top: 0,
                left: 0,
                right: 0,
                // An opaque paper ground under the status bar, so scrolled
                // content never collides with the clock, then an 11 pt fade
                // just under it (which never veils a screen's top bar).
                // Without a status bar, the design's 58 pt fade.
                height: safe.top > 0 ? safe.top + 11 : 58,
                child: _PaperFade(
                  fadeKey: const Key('tab-fade-top'),
                  top: true,
                  visible: fades,
                  ground: safe.top,
                ),
              ),
              Positioned(
                bottom: 0,
                left: 0,
                right: 0,
                height: 104,
                child: _PaperFade(
                  fadeKey: const Key('tab-fade-bottom'),
                  top: false,
                  visible: fades,
                ),
              ),
              if (!keyboardOpen)
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 0,
                  child: V3TabBar(
                    items: _tabItems,
                    index: branch,
                    mentor: V3TabBarMentor(
                      image: _mentorImage(mentor),
                      initials: mentor.initials,
                      tint: mentor.tint,
                    ),
                    todayLeft: habitsLeft,
                    compact: _compact,
                    hidden: pushed,
                    bottomOffset: V3TabBar.bottomOffsetFor(safe.bottom),
                    onTap: (index) {
                      playHaptic(context, AppHaptic.selection);
                      navigationShell.goBranch(
                        index,
                        initialLocation: index == navigationShell.currentIndex,
                      );
                    },
                  ),
                ),
              if (listeningDockVisible)
                AnimatedPositioned(
                  left: 12,
                  right: 12,
                  bottom: dockBottom,
                  // `transition: bottom .4s var(--out)`.
                  duration: motion
                      ? const Duration(milliseconds: 400)
                      : Duration.zero,
                  curve: AppMotion.out,
                  child: Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 560),
                      // `animation: rise .5s var(--spring)`.
                      child: V3Rise(
                        duration: const Duration(milliseconds: 500),
                        child: _ReportHeight(
                          onHeight: (height) {
                            if (mounted && height != _dockHeight) {
                              setState(() => _dockHeight = height);
                            }
                          },
                          child: BookNarrationDock(
                            controller: narrationRemote,
                            onOpenAppMenu: _openAppMenu,
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
    );
  }

  /// The App menu (restored from v2, in the v3 sheet): pick a tab while a
  /// pushed reader stays mounted in its branch and keeps narrating.
  Future<void> _openAppMenu() async {
    final current = navigationShell.currentIndex;
    final destination = await showV3Sheet<int>(
      context,
      title: 'App menu',
      builder: (sheetContext) => Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var i = 0; i < appShellDestinations.length; i++)
            V3Pressable(
              key: ValueKey('listening-nav-item-$i'),
              selected: current == i,
              focusRadius: AppRadii.br12,
              onTap: () => Navigator.of(sheetContext).pop(i),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Row(
                  children: [
                    CmpysNavIcon(
                      appShellDestinations[i].glyph,
                      color: current == i ? AppColors.ember : AppColors.ink2,
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Text(
                        appShellDestinations[i].label,
                        style: AppTypography.sans(
                          15.5,
                          FontWeight.w500,
                        ).copyWith(color: AppColors.ink),
                      ),
                    ),
                    if (current == i)
                      const V3Icon(
                        V3Icons.check,
                        size: 18,
                        color: AppColors.ember,
                      ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
    if (!mounted || destination == null) return;
    playHaptic(context, AppHaptic.selection);
    // Keep the reader route, even when its own tab is picked: resetting that
    // branch would dispose the reader and interrupt narration.
    navigationShell.goBranch(destination);
  }
}

/// Reports its child's laid-out height after the frame (the dock grows with
/// large text, and the content clearance under it must follow).
class _ReportHeight extends SingleChildRenderObjectWidget {
  const _ReportHeight({required this.onHeight, required super.child});

  final ValueChanged<double> onHeight;

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderReportHeight(onHeight);

  @override
  void updateRenderObject(
    BuildContext context,
    _RenderReportHeight renderObject,
  ) => renderObject.onHeight = onHeight;
}

class _RenderReportHeight extends RenderProxyBox {
  _RenderReportHeight(this.onHeight);

  ValueChanged<double> onHeight;
  double? _reported;

  @override
  void performLayout() {
    super.performLayout();
    final height = size.height;
    if (height == _reported) return;
    _reported = height;
    SchedulerBinding.instance.addPostFrameCallback((_) => onHeight(height));
  }
}

class _AppShellScope extends InheritedWidget {
  const _AppShellScope({
    required this.bottomClearance,
    required this.openAppMenu,
    required super.child,
  });

  final double bottomClearance;
  final Future<void> Function() openAppMenu;

  @override
  bool updateShouldNotify(_AppShellScope oldWidget) =>
      bottomClearance != oldWidget.bottomClearance;
}

/// A paper-coloured fade over the top or bottom of a tab screen: content
/// scrolls under the status bar and under the tab bar without a hard edge.
/// Never takes touches.
class _PaperFade extends StatelessWidget {
  const _PaperFade({
    required this.fadeKey,
    required this.top,
    required this.visible,
    this.ground = 0,
  });

  /// Goes on the [IgnorePointer] that wraps the fade, so a test can read both
  /// its size and that it ignores touches.
  final Key fadeKey;
  final bool top;
  final bool visible;

  /// Height of an opaque paper ground at the top (the status bar's inset):
  /// the fade runs below it. 0 for none.
  final double ground;

  static const _stops = [0.0, 0.3, 0.65, 1.0];
  static const _alphas = [1.0, 0.82, 0.38, 0.0];

  @override
  Widget build(BuildContext context) {
    final colors = [
      for (final alpha in top ? _alphas : _alphas.reversed)
        AppColors.paper.withValues(alpha: alpha),
    ];
    final fade = DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: colors,
          stops: top ? _stops : _stops.reversed.map((s) => 1 - s).toList(),
        ),
      ),
    );
    return IgnorePointer(
      key: fadeKey,
      child: AnimatedOpacity(
        opacity: visible ? 1 : 0,
        duration: MotionConfig.enabled(context)
            ? const Duration(milliseconds: 300)
            : Duration.zero,
        child: top && ground > 0
            ? Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  SizedBox(
                    height: ground,
                    child: const ColoredBox(
                      key: Key('tab-ground-top'),
                      color: AppColors.paper,
                    ),
                  ),
                  Expanded(child: fade),
                ],
              )
            : fade,
      ),
    );
  }
}

/// The incoming tab's entrance (`v3/app.jsx`): the IndexedStack swap is
/// otherwise a hard cut. Only the incoming branch animates; the outgoing one
/// disappears at once (duplicating the shell tree for a cross-fade would
/// break its GlobalKeys).
///
/// - To a tab further right in the bar (`TAB_ORDER` today, plan, mentor,
///   compare, you): `tabR`, from 46 px right and transparent; further left:
///   `tabL`, from 46 px left. Both `.5s var(--out)`.
/// - The first show: `tabIn`, from 10 px down at 99% and transparent, also
///   `.5s var(--out)`.
/// - Reduced motion: a short fade (200 ms), no movement.
class _TabFade extends StatefulWidget {
  const _TabFade({required this.index, required this.child});

  final int index;
  final Widget child;

  @override
  State<_TabFade> createState() => _TabFadeState();
}

class _TabFadeState extends State<_TabFade>
    with SingleTickerProviderStateMixin {
  static const _duration = Duration(milliseconds: 500);
  static const _reducedDuration = Duration(milliseconds: 200);

  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: _duration,
  );

  /// +1 entering from the right, −1 from the left, 0 the first show.
  int _direction = 0;
  bool _motion = true;
  bool _shown = false;

  void _enter(int direction) {
    _direction = direction;
    _motion = MotionConfig.enabled(context);
    _controller
      ..duration = _motion ? _duration : _reducedDuration
      ..forward(from: 0);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_shown) return;
    _shown = true;
    _enter(0);
  }

  @override
  void didUpdateWidget(_TabFade oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.index != widget.index) {
      _enter(widget.index > oldWidget.index ? 1 : -1);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // One fixed structure, so the branches below never remount.
    return AnimatedBuilder(
      animation: _controller,
      child: widget.child,
      builder: (context, child) {
        final value = _controller.value;
        final double opacity;
        var transform = Matrix4.identity();
        if (!_motion) {
          opacity = AppCurves.easeOut.transform(value);
        } else {
          final t = AppMotion.out.transform(value);
          final rest = 1 - t;
          opacity = t;
          if (_direction == 0) {
            final scale = .99 + .01 * t;
            transform = Matrix4.translationValues(0, 10 * rest, 0)
              ..scaleByDouble(scale, scale, 1, 1);
          } else {
            transform = Matrix4.translationValues(_direction * 46 * rest, 0, 0);
          }
        }
        return Opacity(
          opacity: opacity.clamp(0.0, 1.0),
          child: Transform(
            key: AppShell.tabTransitionKey,
            alignment: Alignment.center,
            transform: transform,
            child: child,
          ),
        );
      },
    );
  }
}
