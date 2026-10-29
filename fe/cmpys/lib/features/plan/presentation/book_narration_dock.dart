import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/assets.dart';
import '../../../app/design_tokens.dart';
import '../../../core/ui/haptics.dart';
import '../../../core/ui/motion/motion_config.dart';
import '../../../core/ui/v3/v3.dart';
import '../state/book_narration_remote_controller.dart';
import 'book_narration.dart';

/// The design's `fmtT`: whole minutes, then seconds padded to two digits.
String formatBookNarrationTime(Duration time) {
  final seconds = math.max(0, time.inSeconds);
  return '${seconds ~/ 60}:${(seconds % 60).toString().padLeft(2, '0')}';
}

/// A speed as the design prints it (`${speed}×`): 1×, 1.25×, 1.5×, 0.75×.
String bookNarrationSpeedLabel(double speed) {
  final number = speed == speed.roundToDouble()
      ? speed.toInt().toString()
      : speed.toStringAsFixed(2).replaceFirst(RegExp(r'0$'), '');
  return '$number×';
}

/// The disclosure under the full player. Without a known author the line
/// keeps only its first sentence.
String bookNarrationVoiceDisclosure(String author) {
  final name = author.trim();
  return name.isEmpty
      ? 'AI-generated voice.'
      : 'AI-generated voice. Not $name’s voice.';
}

/// The tab a narrated book's reader was opened in, for the player's
/// sub-line: Today (branch 0), You (4), else Plan (also for an unknown
/// branch).
String bookNarrationOrigin(int? branchIndex) => switch (branchIndex) {
  0 => 'Today',
  4 => 'You',
  _ => 'Plan',
};

/// The mini player (design `Dock`): cover, title, chapter · time · speed,
/// waves and play/pause on a dark glass pill, with an ember progress hairline.
/// Tapping it opens the full player.
class BookNarrationDock extends ConsumerWidget {
  const BookNarrationDock({
    super.key,
    this.controller,
    this.onOpen,
    this.onOpenAppMenu,
  });

  /// Height of the pill: 8 + a 50 pt cover + 8.
  static const double preferredHeight = 66;

  /// Key on the pill.
  static const dockKey = Key('book-narration-player');

  /// Key on the progress hairline (its width is the progress).
  static const hairlineKey = Key('book-narration-hairline');

  /// Optional injection point for previews and focused tests. Production callers
  /// normally omit this and use [bookNarrationRemoteControllerProvider].
  final BookNarrationRemoteController? controller;

  /// Replaces opening the full player (tests and previews).
  final VoidCallback? onOpen;

  /// The tab shell's App menu, offered from the full player's More sheet.
  final Future<void> Function()? onOpenAppMenu;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final injectedController = controller;
    if (injectedController != null) {
      return ListenableBuilder(
        listenable: injectedController,
        builder: (context, _) => _buildDock(context, injectedController),
      );
    }
    return _buildDock(
      context,
      ref.watch(bookNarrationRemoteControllerProvider),
    );
  }

  Widget _buildDock(
    BuildContext context,
    BookNarrationRemoteController remote,
  ) {
    if (!remote.active) return const SizedBox.shrink();

    final playbackState = remote.preparing
        ? 'Preparing'
        : remote.playing
        ? 'Playing'
        : 'Paused';
    final semanticValue = remote.semanticText.isEmpty
        ? playbackState
        : '$playbackState. ${remote.semanticText}';
    final title = remote.title.isEmpty ? 'Now listening' : remote.title;
    final chapter = remote.chapterIndex;
    final meta = [
      if (chapter != null) 'Ch. ${chapter + 1}',
      '${formatBookNarrationTime(remote.listeningElapsed)} / '
          '${formatBookNarrationTime(remote.listeningDuration)}',
      bookNarrationSpeedLabel(remote.speed),
    ].join(' · ');
    const radius = BorderRadius.all(Radius.circular(22));

    return Semantics(
      container: true,
      explicitChildNodes: true,
      label: 'Audiobook controls',
      value: semanticValue,
      child: Stack(
        children: [
          V3Pressable(
            semanticLabel: 'Open player, $title',
            onTap:
                onOpen ??
                () => unawaited(
                  showBookNarrationPlayer(
                    context,
                    controller: controller,
                    onOpenAppMenu: onOpenAppMenu,
                  ),
                ),
            focusRadius: radius,
            minTapTarget: 0,
            child: Container(
              key: dockKey,
              constraints: const BoxConstraints(minHeight: preferredHeight),
              decoration: const BoxDecoration(
                borderRadius: radius,
                boxShadow: [
                  BoxShadow(
                    color: Color(0x66000000),
                    offset: Offset(0, 16),
                    blurRadius: 34,
                    spreadRadius: -10,
                  ),
                ],
              ),
              child: ClipRRect(
                borderRadius: radius,
                child: BackdropFilter(
                  filter: ui.ImageFilter.blur(sigmaX: 16, sigmaY: 16),
                  child: ColoredBox(
                    // rgba(23,21,26,.94)
                    color: const Color(0xF017151A),
                    child: Stack(
                      children: [
                        Padding(
                          padding: const EdgeInsets.fromLTRB(8, 8, 10, 8),
                          child: Row(
                            children: [
                              _cover(
                                resourceId: remote.resourceId,
                                title: remote.title,
                                author: remote.author,
                                width: 38,
                                height: 50,
                                radius: 6,
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      title,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: AppTypography.sans(
                                        13.5,
                                        FontWeight.w600,
                                      ).copyWith(color: Colors.white),
                                    ),
                                    const SizedBox(height: 1),
                                    Text(
                                      meta,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: AppTypography.sans(11.5)
                                          .merge(AppTypography.tnum)
                                          .copyWith(color: AppColors.nink3),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 12),
                              SizedBox(
                                width: 40,
                                child: BookNarrationWaves(
                                  playing: remote.playing,
                                  count: 6,
                                  height: 18,
                                ),
                              ),
                              const SizedBox(width: 12),
                              // The play disc sits over the pill (below), so
                              // it keeps its own tap and semantics.
                              const SizedBox(width: 40, height: 40),
                            ],
                          ),
                        ),
                        Positioned(
                          left: 0,
                          right: 0,
                          bottom: 0,
                          height: 2,
                          child: Align(
                            alignment: Alignment.centerLeft,
                            child: FractionallySizedBox(
                              key: hairlineKey,
                              widthFactor: remote.progress,
                              heightFactor: 1,
                              child: const ColoredBox(color: AppColors.ember),
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
          Positioned(
            right: 8,
            top: 0,
            bottom: 0,
            child: Center(
              child: _PlayDisc(
                key: const Key('book-narration-play-pause'),
                remote: remote,
                size: 40,
                iconSize: 16,
                iconColor: AppColors.ink,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

Widget _cover({
  required String? resourceId,
  required String title,
  required String author,
  required double width,
  required double height,
  required double radius,
}) {
  final shown = title.isEmpty ? 'Book' : title;
  return V3Cover(
    title: v3CoverTitle(shown),
    author: author,
    background: v3CoverGround(resourceId ?? shown),
    foreground: kV3CoverInk,
    width: width,
    height: height,
    radius: radius,
  );
}

/// The white play/pause disc of the dock and the full player. Preparing
/// shows a spinner; a tap then cancels, as pausing does.
class _PlayDisc extends StatelessWidget {
  const _PlayDisc({
    super.key,
    required this.remote,
    required this.size,
    required this.iconSize,
    required this.iconColor,
  });

  final BookNarrationRemoteController remote;
  final double size;
  final double iconSize;
  final Color iconColor;

  @override
  Widget build(BuildContext context) {
    final busy = remote.playing || remote.preparing;
    return V3Pressable(
      semanticLabel: busy ? 'Pause' : 'Play',
      onTap: () => unawaited(remote.toggle()),
      child: Container(
        width: size,
        height: size,
        alignment: Alignment.center,
        decoration: const BoxDecoration(
          color: Colors.white,
          shape: BoxShape.circle,
        ),
        child: remote.preparing
            ? V3Spinner(color: iconColor, size: iconSize, semanticLabel: null)
            : V3Icon(
                remote.playing ? V3Icons.pause : V3Icons.play,
                size: iconSize,
                color: iconColor,
              ),
      ),
    );
  }
}

/// Opens the full-screen player over everything (design `FullPlayer`, which
/// slides up over the tabs).
Future<void> showBookNarrationPlayer(
  BuildContext context, {
  BookNarrationRemoteController? controller,
  Future<void> Function()? onOpenAppMenu,
}) {
  final motion = MotionConfig.enabled(context);
  final duration = motion ? const Duration(milliseconds: 600) : Duration.zero;
  return Navigator.of(context, rootNavigator: true).push<void>(
    PageRouteBuilder<void>(
      transitionDuration: duration,
      reverseTransitionDuration: duration,
      pageBuilder: (_, _, _) => BookNarrationFullPlayer(
        controller: controller,
        onOpenAppMenu: onOpenAppMenu,
      ),
      transitionsBuilder: (_, animation, _, child) => SlideTransition(
        // `transform: translateY(100%)` → none, `.6s var(--io)`.
        position: Tween(
          begin: const Offset(0, 1),
          end: Offset.zero,
        ).animate(CurvedAnimation(parent: animation, curve: AppMotion.io)),
        child: child,
      ),
    ),
  );
}

/// What the player shows, kept after the session ends so the closing slide
/// does not blank (the design's `lastN`).
@immutable
class _PlayerView {
  _PlayerView.of(BookNarrationRemoteController remote)
    : resourceId = remote.resourceId,
      title = remote.title,
      author = remote.author,
      chapterIndex = remote.chapterIndex,
      chapterTitle = remote.chapterTitle,
      elapsed = remote.listeningElapsed,
      duration = remote.listeningDuration,
      progress = remote.progress,
      speed = remote.speed,
      playing = remote.playing,
      preparing = remote.preparing,
      branchIndex = remote.branchIndex;

  final String? resourceId;
  final String title;
  final String author;
  final int? chapterIndex;
  final String chapterTitle;
  final Duration elapsed;
  final Duration duration;
  final double progress;
  final double speed;
  final bool playing;
  final bool preparing;
  final int? branchIndex;
}

/// The full-screen night player (design `FullPlayer`): cover, waves, a seek
/// bar with elapsed and −remaining time, ±15 s, play/pause, speed, Chapters,
/// Stop and the AI-voice disclosure.
class BookNarrationFullPlayer extends ConsumerStatefulWidget {
  const BookNarrationFullPlayer({
    super.key,
    this.controller,
    this.onOpenAppMenu,
  });

  /// Key on the speed button.
  static const speedKey = Key('book-narration-speed');

  /// Key on the seek bar's touch area.
  static const seekKey = Key('book-narration-seek');

  /// Key on the background video (absent with reduced motion).
  static const videoKey = Key('book-narration-video');

  /// Key on the gradient laid over the video once it plays.
  static const videoOverlayKey = Key('book-narration-video-overlay');

  final BookNarrationRemoteController? controller;

  /// The tab shell's App menu: switch tabs while the reader keeps narrating.
  /// Null outside the shell.
  final Future<void> Function()? onOpenAppMenu;

  @override
  ConsumerState<BookNarrationFullPlayer> createState() =>
      _BookNarrationFullPlayerState();
}

class _BookNarrationFullPlayerState
    extends ConsumerState<BookNarrationFullPlayer> {
  _PlayerView? _last;
  bool _closing = false;

  /// Whether the background video has started showing (its gradient then
  /// fades in over it; without it the player stays today's design).
  bool _videoShown = false;

  /// The player's route, watched so the video stops as soon as the player
  /// starts closing (by any path: Back, a swipe, Stop, the session ending).
  Animation<double>? _routeAnimation;
  bool _leaving = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final animation = ModalRoute.of(context)?.animation;
    if (identical(animation, _routeAnimation)) return;
    _routeAnimation?.removeStatusListener(_onRouteStatus);
    _routeAnimation = animation?..addStatusListener(_onRouteStatus);
  }

  void _onRouteStatus(AnimationStatus status) {
    final leaving =
        status == AnimationStatus.reverse ||
        status == AnimationStatus.dismissed;
    if (leaving != _leaving && mounted) setState(() => _leaving = leaving);
  }

  @override
  void dispose() {
    _routeAnimation?.removeStatusListener(_onRouteStatus);
    super.dispose();
  }

  BookNarrationRemoteController get _remote =>
      widget.controller ?? ref.watch(bookNarrationRemoteControllerProvider);

  /// Pops the player now, while it is the top route. A later push (the
  /// Chapters sheet) can then never swallow the pop; when nothing was popped
  /// the player stays usable.
  bool _close() {
    if (_closing) return false;
    final route = ModalRoute.of(context);
    if (route == null || !route.isCurrent) return false;
    _closing = true;
    Navigator.of(context).pop();
    return true;
  }

  /// The session ended elsewhere (stopped, or replaced by nothing): leave.
  void _closeWhenEnded() {
    if (_closing) return;
    _closing = true;
    SchedulerBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final route = ModalRoute.of(context);
      if (route == null || !route.isActive) return;
      if (route.isCurrent) {
        Navigator.of(context).pop();
      } else {
        Navigator.of(context).removeRoute(route);
      }
    });
  }

  Future<void> _stop(BookNarrationRemoteController remote) async {
    _close();
    await remote.stop();
  }

  Future<void> _chapters(BookNarrationRemoteController remote) async {
    if (!_close()) return;
    await remote.showChapters();
  }

  static const _appMenu = 'app-menu';

  Future<void> _showMore(BookNarrationRemoteController remote) async {
    final openAppMenu = widget.onOpenAppMenu;
    final choice = await showV3Sheet<Object>(
      context,
      dark: true,
      builder: (sheetContext) => Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'NARRATION STYLE',
            style: AppTypography.kick.copyWith(color: AppColors.nink3),
          ),
          const SizedBox(height: 4),
          for (final style in BookNarrationStyle.values)
            V3Pressable(
              selected: style == remote.style,
              onTap: () => Navigator.of(sheetContext).pop(style),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            style.label,
                            style: AppTypography.sans(
                              15,
                              FontWeight.w600,
                            ).copyWith(color: Colors.white),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            style.description,
                            style: AppTypography.sans(
                              12.5,
                            ).copyWith(color: AppColors.nink3),
                          ),
                        ],
                      ),
                    ),
                    if (style == remote.style)
                      const V3Icon(
                        V3Icons.check,
                        size: 18,
                        color: AppColors.ember,
                      ),
                  ],
                ),
              ),
            ),
          if (openAppMenu != null) ...[
            const SizedBox(height: 8),
            const Divider(height: 1, color: Color(0x1FFFFFFF)),
            V3Pressable(
              key: const Key('book-narration-app-menu'),
              onTap: () => Navigator.of(sheetContext).pop(_appMenu),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 14),
                child: Row(
                  children: [
                    const V3Icon(V3Icons.home, size: 19, color: Colors.white),
                    const SizedBox(width: 14),
                    Text(
                      'App menu',
                      style: AppTypography.sans(
                        15,
                        FontWeight.w600,
                      ).copyWith(color: Colors.white),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
    if (!mounted) return;
    if (choice is BookNarrationStyle) {
      await remote.setStyle(choice);
    } else if (choice == _appMenu && openAppMenu != null) {
      // The reader stays mounted under the tabs and keeps narrating.
      if (_close()) await openAppMenu();
    }
  }

  @override
  Widget build(BuildContext context) {
    final remote = _remote;
    return ListenableBuilder(
      listenable: remote,
      builder: (context, _) {
        if (remote.active) {
          _last = _PlayerView.of(remote);
        } else {
          _closeWhenEnded();
        }
        final view = _last ?? _PlayerView.of(remote);
        return _body(context, remote, view);
      },
    );
  }

  Widget _body(
    BuildContext context,
    BookNarrationRemoteController remote,
    _PlayerView view,
  ) {
    final motion = MotionConfig.enabled(context);
    final media = MediaQuery.of(context);
    final width = media.size.width;
    final title = view.title.isEmpty ? 'Now listening' : view.title;
    final ground = v3CoverGround(view.resourceId ?? title);
    final origin = bookNarrationOrigin(view.branchIndex);
    final chapter = view.chapterIndex;
    final remaining = view.duration - view.elapsed;
    final white = AppTypography.sans(
      12,
    ).merge(AppTypography.tnum).copyWith(color: AppColors.nink3);

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: Material(
        color: AppColors.night,
        child: Stack(
          children: [
            // The cover's colour breathing behind it.
            Positioned(
              left: width / 2 - 230,
              top: 250 - 230,
              width: 460,
              height: 460,
              child: IgnorePointer(
                child: _Breathe(
                  active: view.playing && motion,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: RadialGradient(
                        radius: .7071,
                        colors: [ground, ground.withValues(alpha: 0)],
                        stops: const [0, .65],
                      ),
                    ),
                  ),
                ),
              ),
            ),
            // The ambient `listen` loop: only while this player is open and
            // the narration plays (a closing or covered player is not the
            // current route, so the video pauses). Paused, it dims,
            // desaturates and drifts out. Reduced motion: no video.
            if (motion) ...[
              Positioned.fill(
                child: IgnorePointer(
                  child: V3LoopVideo(
                    key: BookNarrationFullPlayer.videoKey,
                    asset: AppAssets.videoListening,
                    fallback: const SizedBox.expand(),
                    playing: view.playing && !_leaving,
                    // `opacity 1s, filter 1s, transform 2s var(--out)`.
                    opacity: view.playing ? .75 : .4,
                    opacityDuration: const Duration(seconds: 1),
                    opacityCurve: Curves.ease,
                    saturation: view.playing ? 1 : .5,
                    filterDuration: const Duration(seconds: 1),
                    scale: view.playing ? 1 : 1.06,
                    scaleDuration: const Duration(seconds: 2),
                    onReady: (shown) {
                      if (mounted && shown != _videoShown) {
                        setState(() => _videoShown = shown);
                      }
                    },
                  ),
                ),
              ),
              Positioned.fill(
                child: IgnorePointer(
                  child: AnimatedOpacity(
                    key: BookNarrationFullPlayer.videoOverlayKey,
                    opacity: _videoShown ? 1 : 0,
                    duration: const Duration(milliseconds: 1200),
                    curve: AppMotion.out,
                    child: const DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [
                            Color(0x990E0C14),
                            Color(0x330E0C14),
                            Color(0x8C0E0C14),
                            Color(0xF20E0C14),
                          ],
                          stops: [0, .35, .65, 1],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
            const Positioned.fill(child: V3Grain()),
            Column(
              children: [
                V3TopBar(
                  dark: true,
                  onBack: _close,
                  backIcon: V3Icons.down,
                  title: 'Now listening',
                  sub: '$origin · ${v3CoverTitle(title)} guide',
                  right: V3IconButton(
                    icon: V3Icons.more,
                    dark: true,
                    label: 'More',
                    onPressed: remote.active
                        ? () => unawaited(_showMore(remote))
                        : null,
                  ),
                ),
                Expanded(
                  child: CustomScrollView(
                    slivers: [
                      SliverFillRemaining(
                        hasScrollBody: false,
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(28, 20, 28, 0),
                          child: Column(
                            children: [
                              const SizedBox(height: 10),
                              AnimatedScale(
                                // Reduced motion: a static cover.
                                scale: !motion || view.playing ? 1 : .92,
                                duration: motion
                                    ? const Duration(milliseconds: 600)
                                    : Duration.zero,
                                curve: AppMotion.spring,
                                child: _cover(
                                  resourceId: view.resourceId,
                                  title: view.title,
                                  author: view.author,
                                  width: 210,
                                  height: 300,
                                  radius: 16,
                                ),
                              ),
                              const SizedBox(height: 28),
                              Text(
                                title,
                                textAlign: TextAlign.center,
                                style: AppTypography.display(
                                  30,
                                ).copyWith(color: Colors.white),
                              ),
                              if (chapter != null) ...[
                                const SizedBox(height: 4),
                                Text(
                                  view.chapterTitle.isEmpty
                                      ? 'Chapter ${chapter + 1}'
                                      : 'Chapter ${chapter + 1} · '
                                            '${view.chapterTitle}',
                                  textAlign: TextAlign.center,
                                  style: AppTypography.sans(
                                    14,
                                  ).copyWith(color: AppColors.nink2),
                                ),
                              ],
                              const SizedBox(height: 22),
                              BookNarrationWaves(playing: view.playing),
                              // The seek bar's 44 pt touch area centres its
                              // track where the design's 18 pt row does.
                              const SizedBox(height: 3),
                              _SeekBar(
                                key: BookNarrationFullPlayer.seekKey,
                                progress: view.progress,
                                onSeek: remote.seek,
                              ),
                              Transform.translate(
                                offset: const Offset(0, -13),
                                child: Padding(
                                  padding: const EdgeInsets.only(top: 6),
                                  child: Row(
                                    mainAxisAlignment:
                                        MainAxisAlignment.spaceBetween,
                                    children: [
                                      Text(
                                        formatBookNarrationTime(view.elapsed),
                                        style: white,
                                      ),
                                      Text(
                                        '−${formatBookNarrationTime(remaining)}',
                                        style: white,
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                              const SizedBox(height: 1),
                              Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  _SkipButton(
                                    key: const Key('book-narration-back-15'),
                                    icon: V3Icons.back15,
                                    label: 'Back 15 seconds',
                                    onTap: () => unawaited(
                                      remote.skip(const Duration(seconds: -15)),
                                    ),
                                  ),
                                  const SizedBox(width: 28),
                                  _PlayDisc(
                                    key: const Key(
                                      'book-narration-full-play-pause',
                                    ),
                                    remote: remote,
                                    size: 78,
                                    iconSize: 30,
                                    iconColor: AppColors.night,
                                  ),
                                  const SizedBox(width: 28),
                                  _SkipButton(
                                    key: const Key('book-narration-forward-15'),
                                    icon: V3Icons.fwd15,
                                    label: 'Forward 15 seconds',
                                    onTap: () => unawaited(
                                      remote.skip(const Duration(seconds: 15)),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 22),
                              Wrap(
                                alignment: WrapAlignment.center,
                                spacing: 10,
                                runSpacing: 10,
                                children: [
                                  V3Button(
                                    key: BookNarrationFullPlayer.speedKey,
                                    size: V3Size.sm,
                                    kind: V3ButtonKind.glass,
                                    onPressed: () =>
                                        unawaited(remote.cycleSpeed()),
                                    child: Text(
                                      bookNarrationSpeedLabel(view.speed),
                                      style: AppTypography.tnum,
                                    ),
                                  ),
                                  V3Button(
                                    size: V3Size.sm,
                                    kind: V3ButtonKind.glass,
                                    icon: V3Icons.list,
                                    onPressed: () =>
                                        unawaited(_chapters(remote)),
                                    child: const Text('Chapters'),
                                  ),
                                  V3Button(
                                    size: V3Size.sm,
                                    kind: V3ButtonKind.glass,
                                    icon: V3Icons.x,
                                    onPressed: () => unawaited(_stop(remote)),
                                    child: const Text('Stop'),
                                  ),
                                ],
                              ),
                              const Spacer(),
                              Padding(
                                padding: EdgeInsets.only(
                                  top: 16,
                                  bottom: 40 + media.padding.bottom,
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    const V3Icon(
                                      V3Icons.info,
                                      size: 13,
                                      color: AppColors.nink3,
                                    ),
                                    const SizedBox(width: 6),
                                    Flexible(
                                      child: Text(
                                        bookNarrationVoiceDisclosure(
                                          view.author,
                                        ),
                                        textAlign: TextAlign.center,
                                        style: AppTypography.sans(11.5)
                                            .copyWith(
                                              color: AppColors.nink3,
                                              height: 1.5,
                                            ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _SkipButton extends StatelessWidget {
  const _SkipButton({
    super.key,
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final V3Icons icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return V3Pressable(
      semanticLabel: label,
      onTap: onTap,
      child: SizedBox.square(
        dimension: 44,
        child: Stack(
          alignment: Alignment.center,
          children: [
            V3Icon(icon, size: 30, color: Colors.white),
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(
                '15',
                style: AppTypography.sans(
                  9,
                  FontWeight.w700,
                ).copyWith(color: Colors.white, height: 1),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The player's seek bar: a 4 pt track with a white fill and a 14 pt thumb.
/// A tap or a drag seeks; the track sits in a 44 pt touch area.
class _SeekBar extends StatefulWidget {
  const _SeekBar({super.key, required this.progress, required this.onSeek});

  final double progress;
  final Future<void> Function(double progress) onSeek;

  @override
  State<_SeekBar> createState() => _SeekBarState();
}

class _SeekBarState extends State<_SeekBar> {
  double? _preview;

  double get _value => (_preview ?? widget.progress).clamp(0.0, 1.0).toDouble();

  void _previewAt(double dx, double width) {
    if (width <= 0) return;
    setState(() => _preview = (dx / width).clamp(0.0, 1.0).toDouble());
  }

  Future<void> _commit(double value) async {
    final next = value.clamp(0.0, 1.0).toDouble();
    setState(() => _preview = next);
    playHaptic(context, AppHaptic.selection);
    try {
      await widget.onSeek(next);
    } finally {
      if (mounted) setState(() => _preview = null);
    }
  }

  /// The bar's width at gesture time (no LayoutBuilder: the player's
  /// filling column measures intrinsic heights).
  double get _width => context.size?.width ?? 0;

  @override
  Widget build(BuildContext context) {
    final percent = (_value * 100).round();
    return Semantics(
      slider: true,
      label: 'Audiobook progress',
      value: '$percent percent',
      increasedValue: '${(percent + 5).clamp(0, 100)} percent',
      decreasedValue: '${(percent - 5).clamp(0, 100)} percent',
      onIncrease: () => unawaited(_commit(_value + .05)),
      onDecrease: () => unawaited(_commit(_value - .05)),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapUp: (details) {
          final width = _width;
          if (width > 0) unawaited(_commit(details.localPosition.dx / width));
        },
        onHorizontalDragStart: (details) =>
            _previewAt(details.localPosition.dx, _width),
        onHorizontalDragUpdate: (details) =>
            _previewAt(details.localPosition.dx, _width),
        onHorizontalDragEnd: (_) {
          final preview = _preview;
          if (preview != null) unawaited(_commit(preview));
        },
        onHorizontalDragCancel: () => setState(() => _preview = null),
        child: SizedBox(
          height: 44,
          width: double.infinity,
          child: CustomPaint(painter: _SeekPainter(_value)),
        ),
      ),
    );
  }
}

class _SeekPainter extends CustomPainter {
  const _SeekPainter(this.value);

  final double value;

  @override
  void paint(Canvas canvas, Size size) {
    final y = size.height / 2;
    final track = RRect.fromRectAndRadius(
      Rect.fromLTWH(0, y - 2, size.width, 4),
      const Radius.circular(9),
    );
    canvas.drawRRect(track, Paint()..color = const Color(0x29FFFFFF));
    final x = size.width * value;
    final white = Paint()..color = Colors.white;
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(0, y - 2, x, 4),
        const Radius.circular(9),
      ),
      white,
    );
    canvas.drawCircle(Offset(x, y), 7, white);
  }

  @override
  bool shouldRepaint(_SeekPainter oldDelegate) => oldDelegate.value != value;
}

/// The glow behind the cover: `breathe 4s ease-in-out infinite` while
/// playing, still otherwise.
class _Breathe extends StatefulWidget {
  const _Breathe({required this.active, required this.child});

  final bool active;
  final Widget child;

  @override
  State<_Breathe> createState() => _BreatheState();
}

class _BreatheState extends State<_Breathe>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 4),
  );

  /// `breathe`: up over the first half of the cycle and back down over the
  /// second, each half `ease-in-out`; 0 at both ends of the cycle.
  late final Animation<double> _breath = _controller.drive(
    TweenSequence<double>([
      TweenSequenceItem(
        tween: Tween<double>(
          begin: 0,
          end: 1,
        ).chain(CurveTween(curve: Curves.easeInOut)),
        weight: 1,
      ),
      TweenSequenceItem(
        tween: Tween<double>(
          begin: 1,
          end: 0,
        ).chain(CurveTween(curve: Curves.easeInOut)),
        weight: 1,
      ),
    ]),
  );
  late final Animation<double> _opacity = Tween<double>(
    begin: .55,
    end: .9,
  ).animate(_breath);
  late final Animation<double> _scale = Tween<double>(
    begin: 1,
    end: 1.08,
  ).animate(_breath);

  /// Still: the glow's own `opacity: .9`, unscaled.
  static const Animation<double> _restOpacity = AlwaysStoppedAnimation(.9);
  static const Animation<double> _restScale = AlwaysStoppedAnimation(1);

  @override
  void initState() {
    super.initState();
    _sync();
  }

  @override
  void didUpdateWidget(_Breathe oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.active != widget.active) _sync();
  }

  void _sync() {
    if (widget.active) {
      if (!_controller.isAnimating) _controller.repeat();
    } else {
      _controller
        ..stop()
        ..value = 0;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Keyframe opacity .55–.9 replaces the element's .9 while it animates.
    return FadeTransition(
      opacity: widget.active ? _opacity : _restOpacity,
      child: ScaleTransition(
        scale: widget.active ? _scale : _restScale,
        child: widget.child,
      ),
    );
  }
}

/// The design's `Waves`: [count] rounded bars (heights `.25 + |sin(i·1.7)·.75|`)
/// that pulse with the `bar` keyframes while [playing] and rest at 35 % when
/// paused. Under reduced motion they hold still.
class BookNarrationWaves extends StatefulWidget {
  const BookNarrationWaves({
    super.key,
    required this.playing,
    this.count = 34,
    this.color = Colors.white,
    this.height = 46,
  });

  final bool playing;
  final int count;
  final Color color;
  final double height;

  @override
  State<BookNarrationWaves> createState() => _BookNarrationWavesState();
}

class _BookNarrationWavesState extends State<BookNarrationWaves>
    with TickerProviderStateMixin {
  late final Ticker _ticker = createTicker(_tick);
  final ValueNotifier<double> _seconds = ValueNotifier<double>(0);

  /// 0 = live (playing), 1 = resting at 35 % (`transition: transform .4s`).
  late final AnimationController _rest = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 400),
    value: widget.playing ? 0 : 1,
  );
  bool _motion = true;

  void _tick(Duration elapsed) =>
      _seconds.value = elapsed.inMicroseconds / Duration.microsecondsPerSecond;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _motion = MotionConfig.enabled(context);
    _sync(animate: false);
  }

  @override
  void didUpdateWidget(BookNarrationWaves oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.playing != widget.playing) _sync(animate: true);
  }

  void _sync({required bool animate}) {
    final live = widget.playing && _motion;
    if (live) {
      _rest.value = 0;
      if (!_ticker.isActive) _ticker.start();
      return;
    }
    if (!_motion || !animate) {
      _rest.value = widget.playing ? 0 : 1;
      if (_ticker.isActive) _ticker.stop();
      return;
    }
    // Paused with motion: ease from the live bars to rest, then stop.
    _rest.forward().whenCompleteOrCancel(() {
      if (mounted && !widget.playing && _ticker.isActive) _ticker.stop();
    });
  }

  @override
  void dispose() {
    _ticker.dispose();
    _rest.dispose();
    _seconds.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ExcludeSemantics(
      child: RepaintBoundary(
        child: SizedBox(
          height: widget.height,
          width: double.infinity,
          child: CustomPaint(
            painter: _WavesPainter(
              count: widget.count,
              color: widget.color,
              seconds: _seconds,
              rest: _rest,
              animated: _motion,
            ),
          ),
        ),
      ),
    );
  }
}

class _WavesPainter extends CustomPainter {
  _WavesPainter({
    required this.count,
    required this.color,
    required this.seconds,
    required this.rest,
    required this.animated,
  }) : super(repaint: Listenable.merge([seconds, rest]));

  final int count;
  final Color color;
  final ValueListenable<double> seconds;
  final Animation<double> rest;
  final bool animated;

  static const double _gap = 3;

  /// `bar` keyframes: scaleY .3 → 1 → .3, ease-in-out each half, lasting
  /// `.8 + (i % 5)·.15` s after an `i·.04` s delay (unscaled before it).
  static double _live(int i, double t) {
    final local = t - i * .04;
    if (local < 0) return 1;
    final period = .8 + (i % 5) * .15;
    final phase = (local % period) / period;
    final half = phase < .5 ? phase / .5 : 1 - (phase - .5) / .5;
    return .3 + .7 * Curves.easeInOut.transform(half);
  }

  @override
  void paint(Canvas canvas, Size size) {
    if (count <= 0) return;
    final barWidth = (size.width - _gap * (count - 1)) / count;
    if (barWidth <= 0) return;
    final paint = Paint()..color = color.withValues(alpha: color.a * .85);
    final resting = rest.value;
    for (var i = 0; i < count; i++) {
      final v = .25 + (math.sin(i * 1.7) * .75).abs();
      final live = animated ? _live(i, seconds.value) : 1.0;
      final scale = ui.lerpDouble(live, .35, resting)!;
      final barHeight = size.height * v * scale;
      final rect = Rect.fromCenter(
        center: Offset(i * (barWidth + _gap) + barWidth / 2, size.height / 2),
        width: barWidth,
        height: barHeight,
      );
      final radius = math.min(9.0, math.min(barWidth, barHeight) / 2);
      canvas.drawRRect(
        RRect.fromRectAndRadius(rect, Radius.circular(radius)),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(_WavesPainter oldDelegate) =>
      oldDelegate.count != count ||
      oldDelegate.color != color ||
      oldDelegate.animated != animated;
}
