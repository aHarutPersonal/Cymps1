// CMPYS Ideas Reels — full-screen vertical snap feed (TikTok/Reels style).
//
// Ported from reels.jsx: per-idea gradient cards, floating watermark quote,
// entrance text animation, action rail with fill-on-active + count pop,
// double-tap heart burst, story-style progress segments, swipe hint, overlay
// header with refresh (first-refresh-fails demo), and a comments sheet.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/design_tokens.dart';
import '../../../core/network/dio_client.dart';
import '../../../core/ui/cmpys/cmpys_primitives.dart';
import '../data/cmpys_ideas_provider.dart';
import '../data/cmpys_seed.dart';
import '../state/cmpys_store.dart';

class CmpysReelsScreen extends ConsumerStatefulWidget {
  const CmpysReelsScreen({super.key});

  @override
  ConsumerState<CmpysReelsScreen> createState() => _CmpysReelsScreenState();
}

class _CmpysReelsScreenState extends ConsumerState<CmpysReelsScreen> {
  final PageController _page = PageController();
  int _active = 0;
  String _refresh = 'idle'; // idle | loading | error
  List<CmpysIdea>? _ideas; // set by the explicit refresh; overrides the cache

  @override
  void dispose() {
    _page.dispose();
    super.dispose();
  }

  Future<void> _doRefresh() async {
    if (_refresh == 'loading') return;
    setState(() => _refresh = 'loading');
    try {
      final dio = ref.read(dioClientProvider);
      final ideas = await fetchCmpysIdeasFromDio(dio, refresh: true);
      if (!mounted) return;
      setState(() {
        _ideas = ideas;
        _refresh = 'idle';
        _active = 0;
      });
      _page.jumpToPage(0);
      showCmpysToast(context, 'Fresh ideas loaded',
          icon: Icons.auto_awesome_rounded, tone: AppColors.green);
    } catch (e) {
      if (!mounted) return;
      setState(() => _refresh = 'error');
    }
  }

  @override
  Widget build(BuildContext context) {
    // Initial data comes from the shared, cached ideas provider (same /feed
    // payload the Today surface uses) — a network fetch only happens on the
    // true first load. The explicit refresh button still fetches fresh ideas.
    final ideasAsync = ref.watch(cmpysIdeasProvider);
    final ideas = _ideas ?? ideasAsync.valueOrNull;
    if (ideas == null) {
      // First load: spinner, or full-screen error + retry. Never canned
      // quotes. While a retry is reloading, show the spinner again.
      if (_refresh == 'error' ||
          (ideasAsync.hasError && !ideasAsync.isLoading)) {
        return Scaffold(
          backgroundColor: const Color(0xFF0E0E12),
          body: SafeArea(
            child: Stack(
              children: [
                Positioned(
                  top: 8,
                  left: 14,
                  child: _circleBtn(PhosphorIconsRegular.caretLeft,
                      () => Navigator.of(context).maybePop()),
                ),
                Center(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 32),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.wifi_off_rounded,
                            size: 36, color: Colors.white),
                        const SizedBox(height: 16),
                        Text(
                          'Couldn’t load your ideas. Check your connection and try again.',
                          textAlign: TextAlign.center,
                          style: AppTypography.bodyLarge.copyWith(
                              color: Colors.white, fontSize: 16, height: 1.5),
                        ),
                        const SizedBox(height: 22),
                        CmpysButton(
                          variant: CmpysBtnVariant.primary,
                          size: CmpysBtnSize.lg,
                          leadingIcon: Icons.refresh_rounded,
                          onTap: () {
                            setState(() => _refresh = 'idle');
                            ref.invalidate(cmpysIdeasProvider);
                          },
                          child: const Text('Try again'),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      }
      return const Scaffold(
        backgroundColor: Color(0xFF0E0E12),
        body: Center(
          child: CircularProgressIndicator(
            strokeWidth: 2.4,
            valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
          ),
        ),
      );
    }
    return Scaffold(
      backgroundColor: const Color(0xFF0E0E12),
      body: Stack(
        children: [
          PageView.builder(
            controller: _page,
            scrollDirection: Axis.vertical,
            itemCount: ideas.length,
            onPageChanged: (i) => setState(() => _active = i),
            itemBuilder: (_, i) => _Reel(
              idea: ideas[i],
              active: i == _active,
              first: i == 0,
              onComments: () => _openComments(ideas[i]),
            ),
          ),

          // Top gradient + progress segments + header
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: Container(
              padding: EdgeInsets.only(
                  top: MediaQuery.of(context).padding.top + 8,
                  left: 14,
                  right: 14,
                  bottom: 14),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.black.withValues(alpha: 0.35),
                    Colors.transparent,
                  ],
                ),
              ),
              child: Column(
                children: [
                  // progress segments
                  Row(
                    children: List.generate(ideas.length, (i) {
                      return Expanded(
                        child: Container(
                          height: 3,
                          margin: EdgeInsets.only(
                              right: i == ideas.length - 1 ? 0 : 4),
                          decoration: BoxDecoration(
                            color: i <= _active
                                ? Colors.white
                                : Colors.white.withValues(alpha: 0.28),
                            borderRadius: BorderRadius.circular(999),
                          ),
                        ),
                      );
                    }),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      _circleBtn(PhosphorIconsRegular.caretLeft,
                          () => Navigator.of(context).maybePop()),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text('Ideas',
                                style: TextStyle(
                                    color: Colors.white,
                                    fontFamily: 'Plus Jakarta Sans',
                                    fontWeight: FontWeight.w800,
                                    fontSize: 16)),
                            Text('For you · ${_active + 1} of ${ideas.length}',
                                style: TextStyle(
                                    color: Colors.white.withValues(alpha: 0.75),
                                    fontSize: 11.5)),
                          ],
                        ),
                      ),
                      _refresh == 'loading'
                          ? Container(
                              width: 44,
                              height: 44,
                              padding: const EdgeInsets.all(9),
                              child: const CircularProgressIndicator(
                                strokeWidth: 2,
                                valueColor:
                                    AlwaysStoppedAnimation<Color>(Colors.white),
                              ),
                            )
                          : _circleBtn(
                              PhosphorIconsRegular.arrowClockwise, _doRefresh),
                    ],
                  ),
                ],
              ),
            ),
          ),

          // Error banner
          if (_refresh == 'error')
            Positioned(
              top: MediaQuery.of(context).padding.top + 110,
              left: 16,
              right: 16,
              child: Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(18),
                  boxShadow: const [
                    BoxShadow(
                        color: Color(0x4D000000),
                        blurRadius: 30,
                        offset: Offset(0, 12)),
                  ],
                ),
                child: Row(
                  children: [
                    const Icon(Icons.warning_amber_rounded,
                        size: 20, color: AppColors.danger),
                    const SizedBox(width: 11),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Couldn’t refresh your feed',
                              style: AppTypography.bodyMedium.copyWith(
                                  fontSize: 13.5, fontWeight: FontWeight.w700)),
                          Text('Check your connection and try again.',
                              style: AppTypography.caption.copyWith(
                                  color: AppColors.ink2, fontSize: 12)),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    CmpysButton(
                      variant: CmpysBtnVariant.primary,
                      size: CmpysBtnSize.sm,
                      onTap: _doRefresh,
                      child: const Text('Retry'),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _circleBtn(IconData icon, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 44,
        height: 44,
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.16),
          shape: BoxShape.circle,
        ),
        child: Icon(icon, color: Colors.white, size: 20),
      ),
    );
  }

  void _openComments(CmpysIdea idea) {
    final store = ref.read(cmpysStoreProvider.notifier);
    final controller = TextEditingController();
    showCmpysSheet(
      context,
      child: StatefulBuilder(
        builder: (ctx, setSheet) {
          final st = ref.read(cmpysStoreProvider).ideaState[idea.id];
          final merged = [
            ...idea.comments,
            ...(st?.comments ?? const []),
          ];
          return Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                merged.isEmpty
                    ? 'Comments'
                    : '${merged.length} comment${merged.length == 1 ? "" : "s"}',
                style: AppTypography.h3,
              ),
              const SizedBox(height: 10),
              Container(
                padding: const EdgeInsets.only(bottom: 12),
                decoration: const BoxDecoration(
                  border: Border(bottom: BorderSide(color: AppColors.hair)),
                ),
                child: Text(
                  '"${idea.text.length > 90 ? '${idea.text.substring(0, 90)}…' : idea.text}"',
                  style: AppTypography.caption
                      .copyWith(color: AppColors.ink2, fontSize: 13.5),
                ),
              ),
              const SizedBox(height: 12),
              if (merged.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 20),
                  child: Center(
                    child: Text('No comments yet. Start the conversation.',
                        style: AppTypography.caption
                            .copyWith(color: AppColors.ink3)),
                  ),
                )
              else
                ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: 280),
                  child: ListView.separated(
                    shrinkWrap: true,
                    itemCount: merged.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 12),
                    itemBuilder: (_, i) {
                      final c = merged[i];
                      return Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          CmpysMonogram(
                            initials: c.who.isNotEmpty
                                ? c.who[0].toUpperCase()
                                : '?',
                            size: 30,
                            color: AppColors.ink2,
                            tint: AppColors.paper2,
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(c.who,
                                    style: AppTypography.captionMedium.copyWith(
                                        fontWeight: FontWeight.w700,
                                        fontSize: 13)),
                                Text(c.text,
                                    style: AppTypography.body.copyWith(
                                        color: AppColors.ink2, fontSize: 14)),
                              ],
                            ),
                          ),
                        ],
                      );
                    },
                  ),
                ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: Container(
                      height: 44,
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      decoration: BoxDecoration(
                        color: AppColors.card,
                        borderRadius: BorderRadius.circular(999),
                        border: Border.all(color: AppColors.hair2, width: 1.5),
                      ),
                      child: Center(
                        child: TextField(
                          controller: controller,
                          style: AppTypography.body.copyWith(fontSize: 14),
                          cursorColor: AppColors.green,
                          decoration: const InputDecoration(
                            hintText: 'Add a comment…',
                            border: InputBorder.none,
                            isDense: true,
                            filled: false,
                            contentPadding: EdgeInsets.zero,
                          ),
                          onSubmitted: (_) => _submitComment(
                              store, idea.id, controller, setSheet),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  // Only the send button tracks the text per keystroke — the
                  // rest of the sheet doesn't need to rebuild while typing.
                  ValueListenableBuilder<TextEditingValue>(
                    valueListenable: controller,
                    builder: (_, value, _) => GestureDetector(
                      onTap: () =>
                          _submitComment(store, idea.id, controller, setSheet),
                      child: Container(
                        width: 44,
                        height: 44,
                        decoration: BoxDecoration(
                          color: value.text.trim().isEmpty
                              ? AppColors.hair2
                              : AppColors.green,
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(Icons.arrow_forward_rounded,
                            color: Colors.white, size: 18),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          );
        },
      ),
    );
  }

  void _submitComment(CmpysStore store, String id,
      TextEditingController controller, void Function(void Function()) setSheet) {
    final text = controller.text.trim();
    if (text.isEmpty) return;
    final who = ref.read(cmpysStoreProvider).user.name;
    store.commentIdea(id, (who: who.isEmpty ? 'You' : who, text: text));
    controller.clear();
    setSheet(() {});
  }
}

class _Reel extends ConsumerStatefulWidget {
  const _Reel({
    required this.idea,
    required this.active,
    required this.first,
    required this.onComments,
  });
  final CmpysIdea idea;
  final bool active;
  final bool first;
  final VoidCallback onComments;

  @override
  ConsumerState<_Reel> createState() => _ReelState();
}

class _ReelState extends ConsumerState<_Reel>
    with SingleTickerProviderStateMixin {
  late final AnimationController _burst;
  DateTime? _lastTap;

  @override
  void initState() {
    super.initState();
    _burst = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 850),
    );
  }

  @override
  void dispose() {
    _burst.dispose();
    super.dispose();
  }

  void _onTap() {
    final now = DateTime.now();
    if (_lastTap != null &&
        now.difference(_lastTap!) < const Duration(milliseconds: 320)) {
      final liked = ref.read(cmpysStoreProvider).ideaState[widget.idea.id]?.liked ?? false;
      if (!liked) {
        ref.read(cmpysStoreProvider.notifier).likeIdea(widget.idea.id);
        HapticFeedback.lightImpact();
      }
      _burst.forward(from: 0);
    }
    _lastTap = now;
  }

  @override
  Widget build(BuildContext context) {
    final idea = widget.idea;
    final st = ref.watch(cmpysStoreProvider.select((s) => s.ideaState[idea.id]));
    final liked = st?.liked ?? false;
    final saved = st?.saved ?? false;
    final commentCount = idea.comments.length + (st?.comments.length ?? 0);
    final likeN = idea.likes + (liked ? 1 : 0);
    final dark = Color.lerp(idea.tone, Colors.black, 0.45)!;
    final media = MediaQuery.of(context);
    final compact = media.size.height < 700 || media.textScaler.scale(14) > 16;

    return GestureDetector(
      onTap: _onTap,
      behavior: HitTestBehavior.opaque,
      child: Stack(
        fit: StackFit.expand,
        children: [
          // Background gradient
          DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: const Alignment(-0.4, -1),
                end: const Alignment(0.4, 1),
                colors: [idea.tone, dark],
              ),
            ),
          ),
          // radial highlight top-right
          const DecoratedBox(
            decoration: BoxDecoration(
              gradient: RadialGradient(
                center: Alignment(0.7, -1.05),
                radius: 1.0,
                colors: [Color(0x33FFFFFF), Color(0x00FFFFFF)],
                stops: [0.0, 0.55],
              ),
            ),
          ),

          // Watermark quote
          Positioned(
            top: compact ? 94 : 116,
            left: compact ? 16 : 20,
            child: Opacity(
              opacity: 0.55,
              child: Icon(PhosphorIconsFill.quotes,
                  size: compact ? 90 : 120,
                  color: Colors.white.withValues(alpha: 0.16)),
            ),
          ),

          // Main text block
          Positioned(
            left: compact ? 18 : 24,
            right: compact ? 76 : 90,
            bottom: compact ? 92 : 130,
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 450),
              transitionBuilder: (child, anim) => FadeTransition(
                opacity: anim,
                child: SlideTransition(
                  position: Tween(begin: const Offset(0, 0.12), end: Offset.zero)
                      .animate(CurvedAnimation(
                          parent: anim, curve: Curves.easeOutCubic)),
                  child: child,
                ),
              ),
              child: widget.active
                  ? Column(
                      key: ValueKey('on-${idea.id}'),
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: _textColumn(idea, compact: compact),
                    )
                  : Column(
                      key: ValueKey('off-${idea.id}'),
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: _textColumn(idea, compact: compact),
                    ),
            ),
          ),

          // Action rail
          Positioned(
            right: 12,
            bottom: compact ? 82 : 118,
            child: GestureDetector(
              onTap: () {}, // absorb taps so card double-tap doesn't fire
              child: Column(
                children: [
                  _RailBtn(
                    icon: PhosphorIconsFill.heart,
                    outlineIcon: PhosphorIconsRegular.heart,
                    count: likeN,
                    active: liked,
                    activeColor: const Color(0xFFFF5DA2),
                    onTap: () =>
                        ref.read(cmpysStoreProvider.notifier).likeIdea(idea.id),
                  ),
                  SizedBox(height: compact ? 10 : 16),
                  _RailBtn(
                    icon: PhosphorIconsFill.chatCircle,
                    outlineIcon: PhosphorIconsRegular.chatCircle,
                    count: commentCount,
                    active: false,
                    activeColor: Colors.white,
                    onTap: widget.onComments,
                  ),
                  SizedBox(height: compact ? 10 : 16),
                  _RailBtn(
                    icon: PhosphorIconsFill.bookmarkSimple,
                    outlineIcon: PhosphorIconsRegular.bookmarkSimple,
                    count: null,
                    active: saved,
                    activeColor: const Color(0xFFFFD166),
                    onTap: () {
                      final now = ref.read(cmpysStoreProvider.notifier).toggleIdeaSave(
                          id: idea.id, title: idea.text, author: idea.author);
                      showCmpysToast(context, now ? 'Idea saved' : 'Removed from saved',
                          icon: now
                              ? Icons.bookmark_added_outlined
                              : Icons.bookmark_remove_outlined,
                          tone: now ? AppColors.green : AppColors.ink3);
                    },
                  ),
                  SizedBox(height: compact ? 10 : 16),
                  _RailBtn(
                    icon: PhosphorIconsFill.shareNetwork,
                    outlineIcon: PhosphorIconsRegular.shareNetwork,
                    count: null,
                    active: false,
                    activeColor: Colors.white,
                    onTap: () => showCmpysToast(context, 'Link copied',
                        icon: Icons.ios_share_rounded, tone: AppColors.ink3),
                  ),
                ],
              ),
            ),
          ),

          // Swipe hint (first reel only)
          if (widget.first && widget.active)
            Positioned(
              left: 0,
              right: 0,
              bottom: compact ? 22 : 44,
              child: _SwipeHint(),
            ),

          // Heart burst
          AnimatedBuilder(
            animation: _burst,
            builder: (_, _) {
              if (_burst.value == 0) return const SizedBox.shrink();
              final t = _burst.value;
              final scale = t < 0.25
                  ? 0.3 + (t / 0.25) * 0.95
                  : t < 0.55
                      ? 1.25 - ((t - 0.25) / 0.3) * 0.25
                      : 1.0 + ((t - 0.55) / 0.45) * 0.1;
              final opacity = t < 0.55 ? (t / 0.25).clamp(0.0, 1.0) : 1 - (t - 0.55) / 0.45;
              final dy = t < 0.55 ? 0.0 : -30 * ((t - 0.55) / 0.45);
              return IgnorePointer(
                child: Center(
                  child: Transform.translate(
                    offset: Offset(0, dy),
                    child: Transform.scale(
                      scale: scale,
                      child: Opacity(
                        opacity: opacity.clamp(0.0, 1.0),
                        child: const Icon(PhosphorIconsFill.heart,
                            size: 110, color: Colors.white),
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  List<Widget> _textColumn(CmpysIdea idea, {required bool compact}) {
    return [
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.18),
          borderRadius: BorderRadius.circular(999),
        ),
        child: Text(
          idea.tag.toUpperCase(),
          style: AppTypography.kicker
              .copyWith(color: Colors.white, fontSize: 11, letterSpacing: 1.4),
        ),
      ),
      const SizedBox(height: 16),
      Text(
        idea.text,
        maxLines: compact ? 7 : null,
        overflow: compact ? TextOverflow.ellipsis : null,
        // Design uses the reading serif (`className="serif"`) for idea body text.
        style: AppTypography.readingBold.copyWith(
          color: Colors.white,
          fontSize: compact
              ? (idea.text.length > 90 ? 20 : 23)
              : (idea.text.length > 90 ? 25 : 29),
          height: 1.16,
          letterSpacing: -0.4,
        ),
      ),
      const SizedBox(height: 18),
      Row(
        children: [
          Container(
            width: 30,
            height: 30,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.92),
              shape: BoxShape.circle,
            ),
            alignment: Alignment.center,
            child: Text(
              _reelInitials(idea.author),
              style: TextStyle(
                  color: idea.tone,
                  fontWeight: FontWeight.w800,
                  fontSize: 11.5),
            ),
          ),
          const SizedBox(width: 9),
          Flexible(
            child: Text(idea.author,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                    fontSize: 14.5)),
          ),
          if (idea.isSourced) ...[
            const SizedBox(width: 6),
            Tooltip(
              message: idea.isVerified
                  ? 'Independently cross-checked'
                  : 'Source-backed quote',
              child: Icon(
                idea.isVerified ? Icons.verified : Icons.verified_outlined,
                size: 17,
                color: Colors.white.withValues(alpha: 0.88),
              ),
            ),
          ],
        ],
      ),
    ];
  }

  String _reelInitials(String name) {
    final parts = name.trim().split(RegExp(r'\s+'));
    return parts.take(2).map((p) => p.isNotEmpty ? p[0] : '').join().toUpperCase();
  }
}

class _RailBtn extends StatelessWidget {
  const _RailBtn({
    required this.icon,
    required this.outlineIcon,
    required this.count,
    required this.active,
    required this.activeColor,
    required this.onTap,
  });
  final IconData icon;
  final IconData outlineIcon;
  final int? count;
  final bool active;
  final Color activeColor;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        children: [
          AnimatedScale(
            duration: const Duration(milliseconds: 220),
            scale: active ? 1.12 : 1.0,
            child: Container(
              width: 50,
              height: 50,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.16),
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white.withValues(alpha: 0.18)),
              ),
              child: Icon(active ? icon : outlineIcon,
                  size: 24, color: active ? activeColor : Colors.white),
            ),
          ),
          if (count != null) ...[
            const SizedBox(height: 5),
            Text('$count',
                style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                    fontSize: 12,
                    shadows: [
                      Shadow(color: Color(0x4D000000), blurRadius: 4, offset: Offset(0, 1))
                    ])),
          ],
        ],
      ),
    );
  }
}

class _SwipeHint extends StatefulWidget {
  @override
  State<_SwipeHint> createState() => _SwipeHintState();
}

class _SwipeHintState extends State<_SwipeHint>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c;

  @override
  void initState() {
    super.initState();
    _c = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 1700))
      ..repeat(reverse: true);
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: AnimatedBuilder(
        animation: _c,
        builder: (_, child) {
          final t = Curves.easeInOut.transform(_c.value);
          return Opacity(
            opacity: 0.75 + 0.25 * t,
            child: Transform.translate(offset: Offset(0, -7 * t), child: child),
          );
        },
        child: Column(
          children: [
            const Icon(Icons.keyboard_arrow_up_rounded,
                color: Colors.white, size: 22),
            Text('Swipe up for the next idea',
                style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.85),
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600)),
          ],
        ),
      ),
    );
  }
}
