// In-app YouTube playback for plan video materials, laid out as the design's
// `VideoViewer` (`v3/library.jsx`): the night page, a full-width 16:9
// player, the Video access badge, the title, and the "Why it’s here" card.

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:youtube_player_iframe/youtube_player_iframe.dart';

import '../../../app/design_tokens.dart';
import '../../../core/ui/v3/v3.dart';
import '../models/plan_models.dart';
import 'material_web_screen.dart';
import '../../../core/ui/motion/page_transition.dart';

class MaterialVideoScreen extends StatefulWidget {
  const MaterialVideoScreen({
    super.key,
    required this.material,
    required this.videoId,
    this.tryAfter,
    this.verification,
    this.evidenceUrl,
    @visibleForTesting this.playerOverride,
  });

  final PlanMaterialDetail material;
  final String videoId;
  final String? tryAfter;
  final String? verification;
  final String? evidenceUrl;

  /// Test seam: stands in for the YouTube player, whose web view cannot run
  /// in widget tests. The page around it is unchanged.
  final Widget? playerOverride;

  @override
  State<MaterialVideoScreen> createState() => _MaterialVideoScreenState();
}

class _MaterialVideoScreenState extends State<MaterialVideoScreen> {
  YoutubePlayerController? _controller;
  StreamSubscription<YoutubePlayerValue>? _subscription;
  bool _playbackFailed = false;
  bool _playerReady = false;
  bool _isPlaying = false;

  @override
  void initState() {
    super.initState();
    if (widget.playerOverride != null) return;
    _controller = YoutubePlayerController.fromVideoId(
      videoId: widget.videoId,
      autoPlay: false,
      params: const YoutubePlayerParams(
        showFullscreenButton: true,
        strictRelatedVideos: true,
      ),
    );
    _subscription = _controller!.stream.listen((value) {
      final failed = _playbackFailed || value.error != YoutubeError.none;
      final ready = value.playerState != PlayerState.unknown;
      final playing = value.playerState == PlayerState.playing;
      if (mounted &&
          (failed != _playbackFailed ||
              ready != _playerReady ||
              playing != _isPlaying)) {
        setState(() {
          _playbackFailed = failed;
          _playerReady = ready;
          _isPlaying = playing;
        });
      }
    });
  }

  @override
  void dispose() {
    _subscription?.cancel();
    _controller?.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final m = widget.material;
    final author = m.authorOrCreator?.trim() ?? '';
    final reason = m.reason?.trim() ?? '';
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: Scaffold(
        backgroundColor: AppColors.night,
        body: DefaultTextStyle(
          style: AppTypography.sans(16).copyWith(color: Colors.white),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              V3TopBar(
                dark: true,
                title: 'Video',
                onBack: () => Navigator.of(context).maybePop(),
              ),
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: AspectRatio(
                  aspectRatio: 16 / 9,
                  child: ColoredBox(
                    color: AppColors.night2,
                    child:
                        widget.playerOverride ??
                        YoutubePlayer(controller: _controller!),
                  ),
                ),
              ),
              Expanded(
                child: SingleChildScrollView(
                  padding: EdgeInsets.fromLTRB(
                    22,
                    20,
                    22,
                    20 + MediaQuery.paddingOf(context).bottom,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (_controller != null && !_playbackFailed) ...[
                        V3Button(
                          kind: V3ButtonKind.glass,
                          onPressed: !_playerReady
                              ? null
                              : () async {
                                  try {
                                    if (_isPlaying) {
                                      await _controller!.pauseVideo();
                                    } else {
                                      await _controller!.playVideo();
                                    }
                                  } catch (_) {
                                    if (mounted) {
                                      setState(() => _playbackFailed = true);
                                    }
                                  }
                                },
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(_isPlaying ? Icons.pause : Icons.play_arrow),
                              const SizedBox(width: 8),
                              Text(
                                !_playerReady
                                    ? 'Loading video…'
                                    : _isPlaying
                                    ? 'Pause video'
                                    : 'Play video',
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 16),
                      ],
                      const Align(
                        alignment: Alignment.centerLeft,
                        child: V3AccessBadge(type: AccessType.video),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        m.title,
                        style: AppTypography.sans(
                          22,
                          FontWeight.w600,
                        ).copyWith(height: 1.25, color: Colors.white),
                      ),
                      if (author.isNotEmpty) ...[
                        const SizedBox(height: 4),
                        Text(
                          author,
                          style: AppTypography.sans(
                            13.5,
                          ).copyWith(color: AppColors.nink3),
                        ),
                      ],
                      if (reason.isNotEmpty) ...[
                        const SizedBox(height: 18),
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            color: AppColors.night2,
                            borderRadius: BorderRadius.circular(16),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Why it’s here',
                                style: AppTypography.sans(
                                  12,
                                  FontWeight.w600,
                                ).copyWith(color: AppColors.nink3),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                reason,
                                style: AppTypography.sans(
                                  14.5,
                                ).copyWith(height: 1.5, color: Colors.white),
                              ),
                            ],
                          ),
                        ),
                      ],
                      if (widget.verification != null) ...[
                        const SizedBox(height: 16),
                        Text(
                          widget.verification!,
                          style: AppTypography.sans(
                            12,
                          ).copyWith(color: AppColors.nink3),
                        ),
                      ],
                      if (widget.tryAfter != null) ...[
                        const SizedBox(height: 20),
                        Text(
                          'Try after watching',
                          style: AppTypography.sans(17, FontWeight.w600),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          widget.tryAfter!,
                          style: AppTypography.sans(15).copyWith(height: 1.5),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Optional practice · watching does not complete your mission.',
                          style: AppTypography.sans(
                            12,
                          ).copyWith(color: AppColors.nink3),
                        ),
                      ],
                      if (widget.evidenceUrl != null &&
                          widget.evidenceUrl != widget.material.url &&
                          PlanMaterialDetail(
                                title: 'Video source',
                                url: widget.evidenceUrl,
                              ).directUrl !=
                              null) ...[
                        const SizedBox(height: 12),
                        V3Button(
                          kind: V3ButtonKind.glass,
                          onPressed: () => Navigator.of(context).push(
                            CmpysPageRoute<void>(
                              builder: (_) => MaterialWebScreen(
                                url: widget.evidenceUrl!,
                                title: 'Video source',
                              ),
                            ),
                          ),
                          child: const Text('View supporting source'),
                        ),
                      ],
                      const SizedBox(height: 20),
                      if (_playbackFailed)
                        const Text(
                          'This video cannot play here right now. You can try opening it on YouTube.',
                        ),
                      V3Button(
                        kind: V3ButtonKind.glass,
                        onPressed: () async {
                          final opened = await launchUrl(
                            Uri.https('www.youtube.com', '/watch', {
                              'v': widget.videoId,
                            }),
                            mode: LaunchMode.externalApplication,
                          );
                          if (!opened && context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text(
                                  'Couldn’t open YouTube. Please try again.',
                                ),
                              ),
                            );
                          }
                        },
                        child: const Text('Open on YouTube'),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
