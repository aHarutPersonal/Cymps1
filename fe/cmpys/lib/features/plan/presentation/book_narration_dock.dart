import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/design_tokens.dart';
import '../../../core/ui/motion/motion_config.dart';
import '../state/book_narration_remote_controller.dart';
import 'book_narration.dart';

enum _BookNarrationDockOption { stop }

/// Compact, text-free playback surface shared by the reader and app shell.
///
/// Labels remain available through tooltips, semantics, and popup overlays;
/// the persistent surface itself deliberately contains no visible text.
class BookNarrationDock extends ConsumerWidget {
  const BookNarrationDock({
    super.key,
    this.controller,
    this.margin = const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
    this.backgroundColor,
    this.foregroundColor,
    this.maxWidth = 420,
  });

  static const double preferredHeight = 72;

  /// Optional injection point for previews and focused tests. Production callers
  /// normally omit this and use [bookNarrationRemoteControllerProvider].
  final BookNarrationRemoteController? controller;
  final EdgeInsetsGeometry margin;
  final Color? backgroundColor;
  final Color? foregroundColor;
  final double maxWidth;

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

    final dark = Theme.of(context).brightness == Brightness.dark;
    final background =
        backgroundColor ?? (dark ? const Color(0xFF25262D) : AppColors.card);
    final foreground =
        foregroundColor ?? (dark ? const Color(0xFFF2F0EA) : AppColors.ink);
    final playbackState = remote.preparing
        ? 'Preparing'
        : remote.playing
        ? 'Playing'
        : 'Paused';
    final semanticValue = remote.semanticText.isEmpty
        ? playbackState
        : '$playbackState. ${remote.semanticText}';

    return Padding(
      padding: margin,
      child: Center(
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: maxWidth),
          child: Semantics(
            container: true,
            explicitChildNodes: true,
            label: 'Audiobook controls',
            value: semanticValue,
            child: Container(
              key: const Key('book-narration-player'),
              height: preferredHeight,
              clipBehavior: Clip.antiAlias,
              decoration: BoxDecoration(
                color: background,
                borderRadius: AppRadii.brFull,
                border: Border.all(color: AppColors.hair),
                boxShadow: AppShadows.tabPill,
              ),
              child: Stack(
                children: [
                  Positioned(
                    top: 0,
                    left: 0,
                    right: 0,
                    height: 44,
                    child: _BookNarrationProgressRail(
                      key: const Key('book-narration-progress'),
                      progress: remote.progress,
                      trackColor: foreground.withValues(alpha: .14),
                      onSeek: remote.seek,
                    ),
                  ),
                  Positioned(
                    top: 16,
                    left: 0,
                    right: 0,
                    bottom: 4,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                        children: [
                          _styleMenu(
                            remote: remote,
                            background: background,
                            foreground: foreground,
                          ),
                          _iconAction(
                            key: const Key('book-narration-previous'),
                            tooltip: 'Previous sentence',
                            icon: Icons.skip_previous_rounded,
                            color: foreground,
                            onPressed: () => unawaited(remote.previous()),
                          ),
                          _primaryAction(context, remote),
                          _iconAction(
                            key: const Key('book-narration-next'),
                            tooltip: 'Next sentence',
                            icon: Icons.skip_next_rounded,
                            color: foreground,
                            onPressed: () => unawaited(remote.next()),
                          ),
                          _speedMenu(
                            remote: remote,
                            background: background,
                            foreground: foreground,
                          ),
                          _optionsMenu(
                            remote: remote,
                            background: background,
                            foreground: foreground,
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
    );
  }

  Widget _primaryAction(
    BuildContext context,
    BookNarrationRemoteController remote,
  ) {
    final tooltip = remote.preparing
        ? 'Cancel narration loading'
        : remote.playing
        ? 'Pause narration'
        : 'Play narration';
    final motionEnabled = MotionConfig.enabled(context);
    return SizedBox.square(
      dimension: 52,
      child: IconButton.filled(
        key: const Key('book-narration-play-pause'),
        tooltip: tooltip,
        onPressed: () => unawaited(remote.toggle()),
        style: IconButton.styleFrom(
          backgroundColor: AppColors.green2,
          foregroundColor: Colors.white,
          fixedSize: const Size.square(52),
          minimumSize: const Size.square(52),
          maximumSize: const Size.square(52),
          padding: EdgeInsets.zero,
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        ),
        icon: AnimatedSwitcher(
          duration: motionEnabled
              ? const Duration(milliseconds: 160)
              : Duration.zero,
          switchInCurve: AppCurves.easeOut,
          switchOutCurve: AppCurves.easeOut,
          child: remote.preparing
              ? const SizedBox.square(
                  key: ValueKey('preparing'),
                  dimension: 18,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                )
              : Icon(
                  remote.playing
                      ? Icons.pause_rounded
                      : Icons.play_arrow_rounded,
                  key: ValueKey(remote.playing ? 'pause' : 'play'),
                  size: 27,
                ),
        ),
      ),
    );
  }

  Widget _styleMenu({
    required BookNarrationRemoteController remote,
    required Color background,
    required Color foreground,
  }) {
    return SizedBox.square(
      dimension: 44,
      child: PopupMenuButton<BookNarrationStyle>(
        key: const Key('book-narration-style'),
        tooltip: 'Narration style, ${remote.style.label}',
        initialValue: remote.style,
        color: background,
        padding: EdgeInsets.zero,
        position: PopupMenuPosition.over,
        onSelected: (style) => unawaited(remote.setStyle(style)),
        itemBuilder: (context) => [
          for (final style in BookNarrationStyle.values)
            PopupMenuItem<BookNarrationStyle>(
              value: style,
              height: 64,
              child: Row(
                children: [
                  SizedBox(
                    width: 28,
                    child: style == remote.style
                        ? const Icon(
                            Icons.check_rounded,
                            size: 18,
                            color: AppColors.green2,
                          )
                        : null,
                  ),
                  Expanded(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          style.label,
                          style: AppTypography.bodyMedium.copyWith(
                            color: foreground,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          style.description,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: AppTypography.caption.copyWith(
                            color: foreground.withValues(alpha: .66),
                            fontSize: 11,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
        ],
        child: Center(
          child: Icon(Icons.auto_awesome_rounded, size: 20, color: foreground),
        ),
      ),
    );
  }

  Widget _speedMenu({
    required BookNarrationRemoteController remote,
    required Color background,
    required Color foreground,
  }) {
    return SizedBox.square(
      dimension: 44,
      child: PopupMenuButton<double>(
        key: const Key('book-narration-speed'),
        tooltip: 'Playback speed, ${_speedLabel(remote.speed)}',
        initialValue: remote.speed,
        color: background,
        padding: EdgeInsets.zero,
        position: PopupMenuPosition.over,
        onSelected: (speed) => unawaited(remote.setSpeed(speed)),
        itemBuilder: (context) => [
          for (final speed in const [0.75, 1.0, 1.25, 1.5, 2.0])
            PopupMenuItem<double>(
              value: speed,
              child: Row(
                children: [
                  SizedBox(
                    width: 28,
                    child: speed == remote.speed
                        ? const Icon(
                            Icons.check_rounded,
                            size: 18,
                            color: AppColors.green2,
                          )
                        : null,
                  ),
                  Text(
                    _speedLabel(speed),
                    style: AppTypography.bodyMedium.copyWith(color: foreground),
                  ),
                ],
              ),
            ),
        ],
        child: Center(
          child: Icon(Icons.speed_rounded, size: 21, color: foreground),
        ),
      ),
    );
  }

  Widget _optionsMenu({
    required BookNarrationRemoteController remote,
    required Color background,
    required Color foreground,
  }) {
    return SizedBox.square(
      dimension: 44,
      child: PopupMenuButton<_BookNarrationDockOption>(
        key: const Key('book-narration-options'),
        tooltip: 'Narration options',
        color: background,
        padding: EdgeInsets.zero,
        position: PopupMenuPosition.over,
        onSelected: (option) {
          if (option == _BookNarrationDockOption.stop) {
            unawaited(remote.stop());
          }
        },
        itemBuilder: (context) => [
          PopupMenuItem<_BookNarrationDockOption>(
            value: _BookNarrationDockOption.stop,
            child: Row(
              children: [
                const Icon(
                  Icons.stop_circle_outlined,
                  color: AppColors.danger,
                  size: 20,
                ),
                const SizedBox(width: 10),
                Text(
                  'Stop listening',
                  style: AppTypography.bodyMedium.copyWith(
                    color: AppColors.danger,
                  ),
                ),
              ],
            ),
          ),
        ],
        child: Center(
          child: Icon(Icons.more_horiz_rounded, size: 22, color: foreground),
        ),
      ),
    );
  }

  static Widget _iconAction({
    required Key key,
    required String tooltip,
    required IconData icon,
    required Color color,
    required VoidCallback onPressed,
  }) {
    return SizedBox.square(
      dimension: 44,
      child: IconButton(
        key: key,
        tooltip: tooltip,
        onPressed: onPressed,
        constraints: const BoxConstraints.tightFor(width: 44, height: 44),
        padding: EdgeInsets.zero,
        visualDensity: VisualDensity.standard,
        style: IconButton.styleFrom(
          foregroundColor: color,
          fixedSize: const Size.square(44),
          minimumSize: const Size.square(44),
          maximumSize: const Size.square(44),
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        ),
        icon: Icon(icon, size: 23),
      ),
    );
  }

  static String _speedLabel(double speed) {
    final number = speed == speed.roundToDouble()
        ? speed.toInt().toString()
        : speed.toStringAsFixed(2).replaceFirst(RegExp(r'0$'), '');
    return '$number×';
  }
}

class _BookNarrationProgressRail extends StatefulWidget {
  const _BookNarrationProgressRail({
    super.key,
    required this.progress,
    required this.trackColor,
    required this.onSeek,
  });

  final double progress;
  final Color trackColor;
  final Future<void> Function(double progress) onSeek;

  @override
  State<_BookNarrationProgressRail> createState() =>
      _BookNarrationProgressRailState();
}

class _BookNarrationProgressRailState
    extends State<_BookNarrationProgressRail> {
  double? _preview;

  double get _displayProgress =>
      (_preview ?? widget.progress).clamp(0.0, 1.0).toDouble();

  void _previewAt(double dx, double width) {
    if (width <= 0) return;
    final progress = (dx / width).clamp(0.0, 1.0).toDouble();
    if (_preview == progress) return;
    setState(() => _preview = progress);
  }

  Future<void> _commit(double progress) async {
    final next = progress.clamp(0.0, 1.0).toDouble();
    setState(() => _preview = next);
    HapticFeedback.selectionClick();
    try {
      await widget.onSeek(next);
    } finally {
      if (mounted) setState(() => _preview = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final percent = (_displayProgress * 100).round();
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        return Semantics(
          slider: true,
          label: 'Audiobook progress',
          value: '$percent percent',
          increasedValue: '${(percent + 5).clamp(0, 100)} percent',
          decreasedValue: '${(percent - 5).clamp(0, 100)} percent',
          onIncrease: () => unawaited(_commit(_displayProgress + .05)),
          onDecrease: () => unawaited(_commit(_displayProgress - .05)),
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTapUp: (details) =>
                unawaited(_commit(details.localPosition.dx / width)),
            onHorizontalDragStart: (details) =>
                _previewAt(details.localPosition.dx, width),
            onHorizontalDragUpdate: (details) =>
                _previewAt(details.localPosition.dx, width),
            onHorizontalDragEnd: (_) {
              final preview = _preview;
              if (preview != null) unawaited(_commit(preview));
            },
            onHorizontalDragCancel: () => setState(() => _preview = null),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Align(
                alignment: Alignment.topCenter,
                child: Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: ClipRRect(
                    borderRadius: AppRadii.brFull,
                    child: SizedBox(
                      height: 4,
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          ColoredBox(color: widget.trackColor),
                          Align(
                            alignment: Alignment.centerLeft,
                            child: FractionallySizedBox(
                              key: const Key('book-narration-progress-fill'),
                              widthFactor: _displayProgress,
                              heightFactor: 1,
                              child: const ColoredBox(color: AppColors.green2),
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
        );
      },
    );
  }
}
