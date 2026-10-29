// CMPYS v3 idea reels (design `ReelsScreen` in v3/you.jsx).
//
// Full-screen vertical snap pages on night: a provenance tag, the big quote
// mark, the quote and its attribution. Double-tap likes (never unlikes) and
// plays the heart burst; the side rail likes, opens the on-device comments,
// saves to Saved and shares (copies the quote, as the app has no share
// sheet). The top bar carries the progress segments, close, "Ideas for week
// w" and up/down. The last idea offers "Load new ideas" (`/feed?refresh`).

import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/design_tokens.dart';
import '../../../core/network/dio_client.dart';
import '../../../core/ui/haptics.dart';
import '../../../core/ui/motion/motion_config.dart';
import '../../../core/ui/v3/v3.dart';
import '../../plan/state/current_plan_provider.dart';
import '../data/cmpys_ideas_provider.dart';
import '../data/cmpys_seed.dart';
import '../state/cmpys_store.dart';

/// The design's `PROV` labels and icons.
enum IdeaProvenance {
  verified('Verified quotation', V3Icons.check),
  exact('Exact quotation', V3Icons.quote),
  sourced('Sourced attribution', V3Icons.link),
  generated('Generated insight', V3Icons.sparkle);

  const IdeaProvenance(this.label, this.icon);
  final String label;
  final V3Icons icon;
}

/// Maps the `/feed` provenance of [idea] to a design label.
///
/// - Not linked to a catalog quote, or the quote's verification was
///   `rejected`: Generated insight.
/// - `is_verified` (verification `verified`): Verified quotation.
/// - `quote_type` `sourced` (exact words with a source reference) with
///   verification `source_backed`: Exact quotation.
/// - `quote_type` `sourced` with verification `inconclusive`, or
///   `quote_type` `attributed` / `paraphrase` (`source_backed` or
///   `inconclusive`): Sourced attribution.
/// - Anything else (a missing or unknown type or verification): Generated
///   insight, the claim that promises least.
IdeaProvenance ideaProvenanceOf(CmpysIdea idea) {
  String norm(String? v) => (v ?? '').trim().toLowerCase();
  final level = norm(idea.verificationLevel);
  if (!idea.isSourced || level == 'rejected') return IdeaProvenance.generated;
  if (idea.isVerified || level == 'verified') return IdeaProvenance.verified;
  if (level != 'source_backed' && level != 'inconclusive') {
    return IdeaProvenance.generated;
  }
  switch (norm(idea.quoteType)) {
    case 'sourced':
      return level == 'source_backed'
          ? IdeaProvenance.exact
          : IdeaProvenance.sourced;
    case 'attributed':
    case 'paraphrase':
      return IdeaProvenance.sourced;
    default:
      return IdeaProvenance.generated;
  }
}

String? _sourceOf(CmpysIdea idea) {
  for (final s in [idea.sourceReference, idea.sourceTitle]) {
    if (s != null && s.trim().isNotEmpty) return s.trim();
  }
  return null;
}

/// What Share copies. Only verified and exact quotations are put in
/// quotation marks; anything else is plain text that names its provenance,
/// so a pasted idea never passes for a quotation it isn't.
String ideaShareText(CmpysIdea idea) {
  final prov = ideaProvenanceOf(idea);
  final src = _sourceOf(idea);
  final by = src == null ? idea.author : '${idea.author}, $src';
  final quoted =
      prov == IdeaProvenance.verified || prov == IdeaProvenance.exact;
  final text = StringBuffer(
    quoted ? '“${idea.text}” — $by' : '${idea.text} — $by (${prov.label})',
  );
  final url = idea.sourceUrl?.trim() ?? '';
  if (url.isNotEmpty) text.write('\n$url');
  return text.toString();
}

const _glass = Color(0x1FFFFFFF); // rgba(255,255,255,.12)
const _segOff = Color(0x40FFFFFF); // rgba(255,255,255,.25)
const _quoteMark = Color(0x12FFFFFF); // rgba(255,255,255,.07)
const _hint = 'Double-tap to like · swipe for the next idea';

TextStyle get _titleStyle => AppTypography.sans(
  15,
  FontWeight.w600,
).copyWith(color: Colors.white, height: 1.25);

TextStyle get _hintStyle =>
    AppTypography.sans(11.5).copyWith(color: AppColors.nink3, height: 1.3);

/// Short screens and very large text read the quote in a scroll viewport
/// with the rail laid out as a row along the bottom.
bool _readingLayout(MediaQueryData media) =>
    media.size.height < 500 || media.textScaler.scale(14) >= 24;

double _textHeight(
  BuildContext context,
  String text,
  TextStyle style,
  double maxWidth,
) {
  final media = MediaQuery.of(context);
  final painter = TextPainter(
    text: TextSpan(
      text: text,
      style: DefaultTextStyle.of(context).style.merge(style),
    ),
    textDirection: Directionality.of(context),
    textScaler: media.textScaler,
  )..layout(maxWidth: math.max(1.0, maxWidth));
  final height = painter.height;
  painter.dispose();
  return height;
}

double _headerHeight(BuildContext context, String title) {
  final media = MediaQuery.of(context);
  // Row: close 44 · 10 · title · 10 · up 44 · 10 · down 44, inside 16 + 16.
  final width = media.size.width - 32 - 44 * 3 - 30;
  final textHeight = _textHeight(context, title, _titleStyle, width);
  return media.padding.top + 8 + 3 + 12 + math.max(44.0, textHeight);
}

class CmpysReelsScreen extends ConsumerStatefulWidget {
  const CmpysReelsScreen({super.key});

  @override
  ConsumerState<CmpysReelsScreen> createState() => _CmpysReelsScreenState();
}

class _CmpysReelsScreenState extends ConsumerState<CmpysReelsScreen> {
  PageController _page = PageController();
  int _pageGen = 0;
  int _active = 0;
  DateTime? _lastTap;
  ({int key, Offset at})? _heart;
  int _heartSeq = 0;

  /// Ideas from "Load new ideas"; they replace the cached feed until the
  /// feed itself reloads (a new day).
  List<CmpysIdea>? _fresh;
  bool _loadingNew = false;

  /// The next `/feed` page to read (the provider holds page 1), and whether
  /// the last page read said the feed has no more.
  int _nextPage = 2;
  bool _feedDone = false;

  @override
  void dispose() {
    _page.dispose();
    super.dispose();
  }

  /// A new list starts at its first idea with a fresh controller.
  void _resetPaging() {
    final old = _page;
    _page = PageController();
    _pageGen++;
    _active = 0;
    WidgetsBinding.instance.addPostFrameCallback((_) => old.dispose());
  }

  void _go(int delta, int count) {
    final target = _active + delta;
    if (!_page.hasClients || target < 0 || target >= count) return;
    if (MotionConfig.enabled(context)) {
      _page.animateToPage(
        target,
        duration: const Duration(milliseconds: 450),
        curve: AppMotion.io,
      );
    } else {
      _page.jumpToPage(target);
    }
  }

  /// The design's `tap`: two taps within 300 ms like the idea (never unlike
  /// it) and drop the heart burst where the second tap landed.
  void _onPageTap(CmpysIdea idea, Offset global) {
    final now = ref.read(cmpysIdeasClockProvider)();
    final last = _lastTap;
    _lastTap = now;
    if (last == null ||
        now.difference(last) >= const Duration(milliseconds: 300)) {
      return;
    }
    // A third quick tap starts a new pair rather than chaining.
    _lastTap = null;
    final store = ref.read(cmpysStoreProvider.notifier);
    if (!store.ideaOf(idea.id).liked) {
      store.likeIdea(idea.id);
      playHaptic(context, AppHaptic.light);
    }
    if (!MotionConfig.enabled(context)) return;
    final box = context.findRenderObject() as RenderBox?;
    if (box == null) return;
    setState(() => _heart = (key: _heartSeq++, at: box.globalToLocal(global)));
  }

  void _toggleSave(CmpysIdea idea) {
    final on = ref
        .read(cmpysStoreProvider.notifier)
        .toggleIdeaSave(id: idea.id, title: idea.text, author: idea.author);
    showV3Toast(
      context,
      on ? 'Idea saved' : 'Removed from saved',
      icon: V3Icons.bookmark,
    );
  }

  /// No share plugin ships with the app, so share copies [ideaShareText].
  Future<void> _share(CmpysIdea idea) async {
    await Clipboard.setData(ClipboardData(text: ideaShareText(idea)));
    if (!mounted) return;
    showV3Toast(context, 'Copied quote', icon: V3Icons.link);
  }

  /// "Load new ideas", showing the skeleton meanwhile. It reads the next
  /// page of the existing feed first; only once the feed reports no more
  /// pages does it ask the backend to generate (`refresh=true`, paid). The
  /// new page replaces the list and paging restarts at idea 1. A failure
  /// keeps the current ideas and position.
  Future<void> _loadNew() async {
    // Single flight: a second tap in the same frame sees the flag.
    if (_loadingNew) return;
    setState(() => _loadingNew = true);
    final dio = ref.read(dioClientProvider);
    try {
      var ideas = const <CmpysIdea>[];
      while (ideas.isEmpty && !_feedDone) {
        final page = await fetchCmpysIdeasPage(dio, page: _nextPage);
        _nextPage++;
        _feedDone = !page.hasMore;
        ideas = page.ideas;
      }
      if (ideas.isEmpty) {
        final page = await fetchCmpysIdeasPage(dio, refresh: true);
        _nextPage = 2;
        _feedDone = !page.hasMore;
        ideas = page.ideas;
      }
      if (ideas.isEmpty) throw StateError('feed returned no quote items');
      if (!mounted) return;
      setState(() {
        _loadingNew = false;
        _fresh = ideas;
        _resetPaging();
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loadingNew = false);
      showV3Toast(
        context,
        'Couldn’t refresh your feed',
        icon: V3Icons.alert,
        tone: V3ToastTone.warn,
      );
    }
  }

  void _openComments(CmpysIdea idea) {
    // The sheet rides the root navigator; carry this screen's container so
    // it reads the same store wherever the ProviderScope sits.
    final container = ProviderScope.containerOf(context, listen: false);
    showV3Sheet<void>(
      context,
      title: 'Comments',
      builder: (_) => UncontrolledProviderScope(
        container: container,
        child: _CommentsSheet(idea: idea),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // The feed reloaded (a new day on resume): show it from the top.
    ref.listen<AsyncValue<List<CmpysIdea>>>(cmpysIdeasProvider, (prev, next) {
      final before = prev?.valueOrNull;
      final after = next.valueOrNull;
      if (before != null && after != null && !identical(before, after)) {
        setState(() {
          _fresh = null;
          _nextPage = 2;
          _feedDone = false;
          _resetPaging();
        });
      }
    });
    final media = MediaQuery.of(context);
    final ideasAsync = ref.watch(cmpysIdeasProvider);
    final ideas = _fresh ?? ideasAsync.valueOrNull;
    final plan = ref.watch(
      currentPlanProvider.select(
        (s) => (
          resolving: s.plan == null && s.status == CurrentPlanStatus.loading,
          week: s.plan?.focusWeek,
        ),
      ),
    );
    final title = plan.week == null ? 'Ideas' : 'Ideas for week ${plan.week}';
    // Measured at the longest form, so the bar never jumps as the plan
    // resolves.
    final headerHeight = _headerHeight(
      context,
      'Ideas for week ${plan.week ?? 12}',
    );
    final reading = _readingLayout(media);
    final failed =
        ideas == null && ideasAsync.hasError && !ideasAsync.isLoading;
    final hintHeight = _textHeight(
      context,
      _hint,
      _hintStyle,
      media.size.width - 32,
    );
    final textBottom = reading
        ? media.padding.bottom + 12 + 48 + media.textScaler.scale(11) * 1.4 + 16
        : media.padding.bottom + 10 + hintHeight + 12;
    final skeletonTop = math.max(headerHeight + 20, media.padding.top + 86);
    final count = ideas?.length ?? 0;
    final active = count == 0 ? 0 : math.min(_active, count - 1);

    Widget body;
    if (ideas != null) {
      body = PageView.builder(
        key: ValueKey('reels-pages-$_pageGen'),
        controller: _page,
        scrollDirection: Axis.vertical,
        itemCount: ideas.length,
        onPageChanged: (i) => setState(() => _active = i),
        itemBuilder: (_, i) => _ReelPage(
          idea: ideas[i],
          active: i == active,
          last: i == ideas.length - 1,
          reading: reading,
          headerHeight: headerHeight,
          textBottom: textBottom,
          onTap: (global) => _onPageTap(ideas[i], global),
          onSave: () => _toggleSave(ideas[i]),
          onComments: () => _openComments(ideas[i]),
          onShare: () => _share(ideas[i]),
          onLoadNew: _loadNew,
        ),
      );
      // One stable tree, so the pages keep their place while new ideas
      // load; the covered idea and rail are not read meanwhile.
      body = Stack(
        children: [
          Positioned.fill(
            child: ExcludeSemantics(excluding: _loadingNew, child: body),
          ),
          if (_loadingNew)
            Positioned.fill(
              child: AbsorbPointer(
                child: ColoredBox(
                  color: AppColors.night,
                  child: _Skeleton(top: skeletonTop),
                ),
              ),
            ),
        ],
      );
    } else if (failed) {
      body = _LoadError(onRetry: () => ref.invalidate(cmpysIdeasProvider));
    } else {
      body = _Skeleton(top: skeletonTop);
    }

    final heart = _heart;
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: Scaffold(
        backgroundColor: AppColors.night,
        body: Stack(
          children: [
            Positioned.fill(child: body),
            if (heart != null)
              Positioned(
                key: ValueKey('reels-heart-${heart.key}'),
                left: heart.at.dx - 50,
                top: heart.at.dy - 50,
                child: _HeartBurst(
                  key: const ValueKey('reels-heart-burst'),
                  onEnd: () {
                    if (mounted && _heart?.key == heart.key) {
                      setState(() => _heart = null);
                    }
                  },
                ),
              ),
            Positioned(
              top: media.padding.top + 8,
              left: 16,
              right: 16,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Semantics(
                    key: const ValueKey('reels-position'),
                    container: true,
                    label: count == 0 ? null : 'Idea ${active + 1} of $count',
                    child: ExcludeSemantics(
                      child: SizedBox(
                        height: 3,
                        child: Row(
                          children: [
                            for (var k = 0; k < count; k++) ...[
                              if (k > 0) const SizedBox(width: 4),
                              Expanded(
                                child: AnimatedContainer(
                                  key: ValueKey('reels-segment-$k'),
                                  duration: MotionConfig.enabled(context)
                                      ? const Duration(milliseconds: 400)
                                      : Duration.zero,
                                  decoration: BoxDecoration(
                                    color: k <= active ? Colors.white : _segOff,
                                    borderRadius: BorderRadius.circular(9),
                                  ),
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      V3IconButton(
                        icon: V3Icons.x,
                        label: 'Close',
                        dark: true,
                        onPressed: () => Navigator.of(context).maybePop(),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: plan.resolving
                            ? const Align(
                                key: ValueKey('reels-title-skeleton'),
                                alignment: Alignment.centerLeft,
                                child: SizedBox(
                                  width: 128,
                                  child: V3Skel(dark: true, height: 14),
                                ),
                              )
                            : Text(title, style: _titleStyle),
                      ),
                      const SizedBox(width: 10),
                      V3IconButton(
                        icon: V3Icons.up,
                        label: 'Previous',
                        dark: true,
                        size: 36,
                        onPressed: active > 0 && !_loadingNew
                            ? () => _go(-1, count)
                            : null,
                      ),
                      const SizedBox(width: 10),
                      V3IconButton(
                        icon: V3Icons.down,
                        label: 'Next',
                        dark: true,
                        size: 36,
                        onPressed: active < count - 1 && !_loadingNew
                            ? () => _go(1, count)
                            : null,
                      ),
                    ],
                  ),
                ],
              ),
            ),
            if (!reading && !failed)
              Positioned(
                left: 16,
                right: 16,
                bottom: media.padding.bottom + 10,
                child: IgnorePointer(
                  child: Text(
                    _hint,
                    key: const ValueKey('reels-hint'),
                    textAlign: TextAlign.center,
                    style: _hintStyle,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _Skeleton extends StatelessWidget {
  const _Skeleton({required this.top});
  final double top;

  @override
  Widget build(BuildContext context) {
    Widget bar(double factor, double height, double gap) => Padding(
      padding: EdgeInsets.only(top: gap),
      child: FractionallySizedBox(
        alignment: Alignment.centerLeft,
        widthFactor: factor,
        child: V3Skel(dark: true, height: height),
      ),
    );
    return Semantics(
      label: 'Loading ideas',
      child: Padding(
        padding: EdgeInsets.fromLTRB(28, top, 28, 0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            bar(.85, 36, 0),
            bar(.70, 36, 12),
            bar(.50, 36, 12),
            bar(.40, 14, 30),
          ],
        ),
      ),
    );
  }
}

class _LoadError extends StatelessWidget {
  const _LoadError({required this.onRetry});
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 96),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const V3Icon(V3Icons.wifiOff, size: 36, color: Colors.white),
            const SizedBox(height: 16),
            Text(
              'Couldn’t load your ideas. Check your connection and try again.',
              textAlign: TextAlign.center,
              style: AppTypography.sans(
                16,
              ).copyWith(color: Colors.white, height: 1.5),
            ),
            const SizedBox(height: 22),
            V3Button(
              kind: V3ButtonKind.light,
              icon: V3Icons.refresh,
              onPressed: onRetry,
              child: const Text('Try again'),
            ),
          ],
        ),
      ),
    );
  }
}

class _ReelPage extends ConsumerStatefulWidget {
  const _ReelPage({
    required this.idea,
    required this.active,
    required this.last,
    required this.reading,
    required this.headerHeight,
    required this.textBottom,
    required this.onTap,
    required this.onSave,
    required this.onComments,
    required this.onShare,
    required this.onLoadNew,
  });

  final CmpysIdea idea;
  final bool active;

  /// The last idea carries the "You’re all caught up" end affordance.
  final bool last;
  final bool reading;
  final double headerHeight;

  /// Bottom edge of the quote viewport: above the hint (or the rail row).
  final double textBottom;
  final ValueChanged<Offset> onTap;
  final VoidCallback onSave;
  final VoidCallback onComments;
  final VoidCallback onShare;
  final VoidCallback onLoadNew;

  @override
  ConsumerState<_ReelPage> createState() => _ReelPageState();
}

class _ReelPageState extends ConsumerState<_ReelPage>
    with SingleTickerProviderStateMixin {
  // One timeline for the staggered entrance: tag .5s from .1s, quote .7s
  // from .15s, attribution .6s from .35s.
  late final AnimationController _enter = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1000),
  );
  final ScrollController _scroll = ScrollController();

  late final Animation<double> _tag = CurvedAnimation(
    parent: _enter,
    curve: const Interval(.1, .6, curve: Curves.ease),
  );
  late final Animation<double> _quote = CurvedAnimation(
    parent: _enter,
    curve: const Interval(.15, .85, curve: AppMotion.out),
  );
  late final Animation<double> _by = CurvedAnimation(
    parent: _enter,
    curve: const Interval(.35, .95, curve: Curves.ease),
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _sync(initial: true);
  }

  @override
  void didUpdateWidget(_ReelPage old) {
    super.didUpdateWidget(old);
    if (old.active != widget.active) _sync();
  }

  void _sync({bool initial = false}) {
    if (!widget.active) {
      // The idea leaving fades out briefly, as the design's transitions do.
      if (initial || !MotionConfig.enabled(context)) {
        _enter.value = 0;
      } else {
        _enter.animateBack(0, duration: const Duration(milliseconds: 400));
      }
    } else if (!MotionConfig.enabled(context)) {
      _enter.value = 1;
    } else if (!initial || _enter.value == 0) {
      if (!_enter.isAnimating && _enter.value < 1) _enter.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _enter.dispose();
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final idea = widget.idea;
    final media = MediaQuery.of(context);
    final st = ref.watch(
      cmpysStoreProvider.select((s) => s.ideaState[idea.id]),
    );
    final liked = st?.liked ?? false;
    final saved = st?.saved ?? false;
    final comments = idea.comments.length + (st?.comments.length ?? 0);
    final prov = ideaProvenanceOf(idea);
    final src = _sourceOf(idea);
    final reading = widget.reading;
    final textBottom = widget.textBottom;
    final motion = MotionConfig.enabled(context);

    final rail = [
      _RailButton(
        icon: V3Icons.heart,
        label: 'Like idea',
        on: liked,
        color: AppColors.ember,
        onTap: () => ref.read(cmpysStoreProvider.notifier).likeIdea(idea.id),
      ),
      _RailButton(
        icon: V3Icons.chat,
        label: 'Comments',
        count: comments,
        onTap: widget.onComments,
      ),
      _RailButton(
        icon: V3Icons.bookmark,
        label: 'Save idea',
        on: saved,
        color: AppColors.gold,
        onTap: widget.onSave,
      ),
      _RailButton(
        icon: V3Icons.share,
        label: 'Share idea',
        onTap: widget.onShare,
      ),
    ];

    return GestureDetector(
      key: ValueKey('reel-${idea.id}'),
      behavior: HitTestBehavior.opaque,
      excludeFromSemantics: true,
      onTapUp: (d) => widget.onTap(d.globalPosition),
      child: ColoredBox(
        color: Color.lerp(idea.tone, AppColors.night, 0.62)!,
        child: Stack(
          clipBehavior: Clip.hardEdge,
          children: [
            Positioned(
              right: -120,
              top: 120,
              child: RepaintBoundary(
                child: _Drift(animate: widget.active && motion),
              ),
            ),
            const Positioned.fill(child: V3Grain()),
            Positioned(
              left: 16,
              top: media.padding.top + 36,
              child: ExcludeSemantics(
                child: Text(
                  '“',
                  style: AppTypography.display(
                    220,
                  ).copyWith(color: _quoteMark, height: 1),
                ),
              ),
            ),
            Positioned(
              left: reading ? 18 : 26,
              right: reading ? 18 : 84,
              top: widget.headerHeight + 8,
              bottom: textBottom,
              child: LayoutBuilder(
                builder: (context, constraints) => Scrollbar(
                  controller: _scroll,
                  thumbVisibility: reading,
                  child: SingleChildScrollView(
                    key: ValueKey('idea-reading-${idea.id}'),
                    controller: _scroll,
                    child: ConstrainedBox(
                      constraints: BoxConstraints(
                        minHeight: constraints.maxHeight,
                      ),
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            FadeTransition(
                              opacity: _tag,
                              // The tag is one 24 pt line; large text on a
                              // narrow column scales it down, never clips.
                              child: FittedBox(
                                fit: BoxFit.scaleDown,
                                alignment: Alignment.centerLeft,
                                child: V3Tag(
                                  color: Colors.white,
                                  background: _glass,
                                  icon: prov.icon,
                                  child: Text(prov.label),
                                ),
                              ),
                            ),
                            const SizedBox(height: 18),
                            AnimatedBuilder(
                              animation: _quote,
                              builder: (_, child) => Opacity(
                                opacity: _quote.value.clamp(0.0, 1.0),
                                child: Transform.translate(
                                  offset: Offset(0, 20 * (1 - _quote.value)),
                                  child: child,
                                ),
                              ),
                              child: Text(
                                idea.text,
                                style: AppTypography.read(
                                  idea.text.length > 80 ? 27 : 34,
                                ).copyWith(color: Colors.white, height: 1.3),
                              ),
                            ),
                            const SizedBox(height: 22),
                            FadeTransition(
                              opacity: _by,
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    idea.author,
                                    style: AppTypography.sans(
                                      15,
                                      FontWeight.w600,
                                    ).copyWith(color: Colors.white),
                                  ),
                                  if (src != null) ...[
                                    const SizedBox(height: 3),
                                    Text(
                                      src,
                                      style: AppTypography.sans(
                                        12.5,
                                      ).copyWith(color: AppColors.nink3),
                                    ),
                                  ],
                                ],
                              ),
                            ),
                            if (widget.last)
                              FadeTransition(
                                opacity: _by,
                                child: Padding(
                                  padding: const EdgeInsets.only(top: 28),
                                  child: Column(
                                    key: const ValueKey('reels-end'),
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        'You’re all caught up',
                                        style: AppTypography.sans(
                                          13.5,
                                          FontWeight.w600,
                                        ).copyWith(color: AppColors.nink2),
                                      ),
                                      const SizedBox(height: 10),
                                      V3Button(
                                        kind: V3ButtonKind.glass,
                                        size: V3Size.sm,
                                        icon: V3Icons.refresh,
                                        onPressed: widget.onLoadNew,
                                        child: const Text('Load new ideas'),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
            if (reading)
              Positioned(
                left: 18,
                right: 18,
                bottom: media.padding.bottom + 12,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: rail,
                ),
              )
            else
              Positioned(
                right: 14,
                bottom: media.padding.bottom + 86,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    for (var k = 0; k < rail.length; k++) ...[
                      if (k > 0) const SizedBox(height: 18),
                      rail[k],
                    ],
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// One side-rail action: a 48 pt glass disc, popping when it turns on, with
/// an optional count underneath.
class _RailButton extends StatelessWidget {
  const _RailButton({
    required this.icon,
    required this.label,
    required this.onTap,
    this.on,
    this.color,
    this.count = 0,
  });

  final V3Icons icon;
  final String label;
  final VoidCallback onTap;

  /// Null for actions that do not toggle.
  final bool? on;
  final Color? color;
  final int count;

  @override
  Widget build(BuildContext context) {
    final active = on ?? false;
    final tint = active ? color : null;
    Widget disc = Container(
      width: 48,
      height: 48,
      alignment: Alignment.center,
      decoration: const BoxDecoration(color: _glass, shape: BoxShape.circle),
      child: V3Icon(icon, size: 22, color: tint ?? Colors.white, fill: tint),
    );
    if (active) {
      disc = V3Pop(duration: const Duration(milliseconds: 400), child: disc);
    }
    return Semantics(
      container: true,
      button: true,
      label: label,
      value: count > 0 ? '$count' : null,
      toggled: on,
      onTap: onTap,
      child: ExcludeSemantics(
        child: V3Pressable(
          onTap: onTap,
          focusRadius: BorderRadius.circular(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              KeyedSubtree(key: ValueKey(active), child: disc),
              if (count > 0) ...[
                const SizedBox(height: 4),
                Text(
                  '$count',
                  style: AppTypography.sans(11, FontWeight.w600).copyWith(
                    color: Colors.white,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// The soft light that drifts behind each idea (`drift 9s` keyframes). Still
/// when motion is reduced or the page is not current.
class _Drift extends StatefulWidget {
  const _Drift({required this.animate});
  final bool animate;

  @override
  State<_Drift> createState() => _DriftState();
}

class _DriftState extends State<_Drift> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 4500),
  );

  @override
  void initState() {
    super.initState();
    _sync();
  }

  @override
  void didUpdateWidget(_Drift old) {
    super.didUpdateWidget(old);
    if (old.animate != widget.animate) _sync();
  }

  void _sync() {
    if (widget.animate) {
      if (!_c.isAnimating) _c.repeat(reverse: true);
    } else {
      _c.stop();
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    const glow = DecoratedBox(
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: RadialGradient(
          colors: [Color(0x1FFFFFFF), Color(0x00FFFFFF)],
          stops: [0, .65],
        ),
      ),
      child: SizedBox(width: 380, height: 380),
    );
    return IgnorePointer(
      child: AnimatedBuilder(
        animation: _c,
        builder: (_, child) {
          final t = Curves.easeInOut.transform(_c.value);
          return Transform.translate(
            offset: Offset(6 * t, -8 * t),
            child: child,
          );
        },
        child: glow,
      ),
    );
  }
}

/// The double-tap heart (`heart .9s var(--out)` keyframes).
class _HeartBurst extends StatefulWidget {
  const _HeartBurst({super.key, required this.onEnd});
  final VoidCallback onEnd;

  @override
  State<_HeartBurst> createState() => _HeartBurstState();
}

class _HeartBurstState extends State<_HeartBurst>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  );

  @override
  void initState() {
    super.initState();
    _c.forward().whenComplete(() {
      if (mounted) widget.onEnd();
    });
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  static double _seg(double t, double a, double b) =>
      AppMotion.out.transform(((t - a) / (b - a)).clamp(0.0, 1.0));

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: AnimatedBuilder(
        animation: _c,
        builder: (_, child) {
          final t = _c.value;
          double scale, opacity, dy = 0;
          if (t < .25) {
            final p = _seg(t, 0, .25);
            scale = .2 + 1.0 * p;
            opacity = p;
          } else if (t < .6) {
            scale = 1.2 - .2 * _seg(t, .25, .6);
            opacity = 1;
          } else {
            final p = _seg(t, .6, 1);
            scale = 1 + .1 * p;
            opacity = 1 - p;
            dy = -40 * p;
          }
          return Transform.translate(
            offset: Offset(0, dy),
            child: Transform.scale(
              scale: scale,
              child: Opacity(opacity: opacity.clamp(0.0, 1.0), child: child),
            ),
          );
        },
        child: const V3Icon(
          V3Icons.heart,
          size: 100,
          color: AppColors.ember,
          fill: AppColors.ember,
        ),
      ),
    );
  }
}

/// The on-device comments for one idea (design `Sheet title="Comments"`).
class _CommentsSheet extends ConsumerStatefulWidget {
  const _CommentsSheet({required this.idea});
  final CmpysIdea idea;

  @override
  ConsumerState<_CommentsSheet> createState() => _CommentsSheetState();
}

class _CommentsSheetState extends ConsumerState<_CommentsSheet> {
  final TextEditingController _text = TextEditingController();

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  void _post() {
    final text = _text.text.trim();
    if (text.isEmpty) return;
    final name = ref.read(cmpysStoreProvider).user.name.trim();
    ref.read(cmpysStoreProvider.notifier).commentIdea(widget.idea.id, (
      who: name.isEmpty ? 'You' : name,
      text: text,
    ));
    _text.clear();
  }

  @override
  Widget build(BuildContext context) {
    final local = ref.watch(
      cmpysStoreProvider.select((s) => s.ideaState[widget.idea.id]?.comments),
    );
    final comments = [...widget.idea.comments, ...?local];
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (comments.isEmpty)
          Text(
            'No comments yet. Add a thought you want to remember.',
            style: AppTypography.sans(14).copyWith(color: AppColors.ink2),
          )
        else
          for (var k = 0; k < comments.length; k++)
            V3Rise(
              duration: const Duration(milliseconds: 400),
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 10),
                decoration: k == 0
                    ? null
                    : const BoxDecoration(
                        border: Border(top: BorderSide(color: AppColors.hair)),
                      ),
                child: Text.rich(
                  TextSpan(
                    children: [
                      TextSpan(
                        text: comments[k].who,
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                      TextSpan(text: ' ${comments[k].text}'),
                    ],
                  ),
                  style: AppTypography.sans(
                    14.5,
                  ).copyWith(color: AppColors.ink),
                ),
              ),
            ),
        const SizedBox(height: 14),
        Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Expanded(
              child: V3Field(
                controller: _text,
                placeholder: 'Add a comment',
                textInputAction: TextInputAction.send,
                textCapitalization: TextCapitalization.sentences,
                onSubmitted: (_) => _post(),
              ),
            ),
            const SizedBox(width: 8),
            ValueListenableBuilder<TextEditingValue>(
              valueListenable: _text,
              builder: (_, value, _) => V3Button(
                size: V3Size.md,
                onPressed: value.text.trim().isEmpty ? null : _post,
                child: const Text('Post'),
              ),
            ),
          ],
        ),
      ],
    );
  }
}
