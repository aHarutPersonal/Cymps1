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

    return Scaffold(
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
    );
  }
}

class _FloatingPillNav extends StatelessWidget {
  const _FloatingPillNav({required this.currentIndex, required this.onTap});
  final int currentIndex;
  final ValueChanged<int> onTap;

  @override
  Widget build(BuildContext context) {
    final bottomMargin = AppShell._bottomMargin(context);
    final width = MediaQuery.sizeOf(context).width;
    final scaledLabelSize = MediaQuery.textScalerOf(context).scale(14);
    final iconOnly = AppShell.useIconOnlyNavigation(width, scaledLabelSize);

    return Padding(
      padding: EdgeInsets.only(
        bottom: bottomMargin,
        left: iconOnly ? 10 : 16,
        right: iconOnly ? 10 : 16,
      ),
      child: Center(
        child: Container(
          padding: const EdgeInsets.all(6),
          decoration: BoxDecoration(
            color: const Color(0xFAFFFFFF),
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: AppColors.hair),
            boxShadow: AppShadows.tabPill,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: List.generate(appShellDestinations.length, (i) {
              final dest = appShellDestinations[i];
              final active = currentIndex == i;
              return Padding(
                padding: EdgeInsets.only(
                  right: i == appShellDestinations.length - 1 ? 0 : 3,
                ),
                child: _NavChip(
                  glyph: dest.glyph,
                  label: dest.label,
                  active: active,
                  iconOnly: iconOnly,
                  onTap: () => onTap(i),
                ),
              );
            }),
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
    required this.active,
    required this.iconOnly,
    required this.onTap,
  });

  final CmpysNavGlyph glyph;
  final String label;
  final bool active;
  final bool iconOnly;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final iconOnlyChip = AnimatedContainer(
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOutCubic,
      width: 44,
      height: 48,
      decoration: BoxDecoration(
        color: active ? AppColors.green : Colors.transparent,
        borderRadius: BorderRadius.circular(999),
        boxShadow: active
            ? [
                BoxShadow(
                  color: AppColors.green2.withValues(alpha: 0.28),
                  blurRadius: 10,
                  offset: const Offset(0, 3),
                ),
              ]
            : null,
      ),
      alignment: Alignment.center,
      child: CmpysNavIcon(
        glyph,
        size: 22,
        color: active ? Colors.white : AppColors.ink3,
        strokeWidth: active ? 2.0 : 1.7,
      ),
    );

    final activeChip = AnimatedContainer(
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOutCubic,
      height: 48,
      padding: const EdgeInsets.fromLTRB(15, 0, 18, 0),
      decoration: BoxDecoration(
        color: AppColors.green,
        borderRadius: BorderRadius.circular(999),
        boxShadow: [
          BoxShadow(
            color: AppColors.green2.withValues(alpha: 0.36),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          CmpysNavIcon(glyph, size: 22, color: Colors.white, strokeWidth: 2.0),
          const SizedBox(width: 8),
          Text(
            label,
            style: const TextStyle(
              fontFamily: 'Plus Jakarta Sans',
              fontSize: 14,
              fontWeight: FontWeight.w600,
              letterSpacing: -0.1,
              color: Colors.white,
            ),
          ),
        ],
      ),
    );

    final inactiveChip = SizedBox(
      width: 48,
      height: 48,
      child: Center(
        child: CmpysNavIcon(glyph,
            size: 23, color: AppColors.ink3, strokeWidth: 1.7),
      ),
    );

    return Semantics(
      label: label,
      button: true,
      selected: active,
      child: Tooltip(
        message: iconOnly ? label : '',
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(999),
            child: iconOnly
                ? iconOnlyChip
                : active
                    ? activeChip
                    : inactiveChip,
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
