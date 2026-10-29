// In-app YouTube playback for plan video materials, laid out as the design's
// `VideoViewer` (`v3/library.jsx`): the night page, a full-width 16:9
// player, the Video access badge, the title, and the "Why it’s here" card.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:youtube_player_iframe/youtube_player_iframe.dart';

import '../../../app/design_tokens.dart';
import '../../../core/ui/v3/v3.dart';
import '../models/plan_models.dart';

class MaterialVideoScreen extends StatefulWidget {
  const MaterialVideoScreen({
    super.key,
    required this.material,
    required this.videoId,
    @visibleForTesting this.playerOverride,
  });

  final PlanMaterialDetail material;
  final String videoId;

  /// Test seam: stands in for the YouTube player, whose web view cannot run
  /// in widget tests. The page around it is unchanged.
  final Widget? playerOverride;

  @override
  State<MaterialVideoScreen> createState() => _MaterialVideoScreenState();
}

class _MaterialVideoScreenState extends State<MaterialVideoScreen> {
  YoutubePlayerController? _controller;

  @override
  void initState() {
    super.initState();
    if (widget.playerOverride != null) return;
    _controller = YoutubePlayerController.fromVideoId(
      videoId: widget.videoId,
      autoPlay: true,
      params: const YoutubePlayerParams(
        showFullscreenButton: true,
        strictRelatedVideos: true,
      ),
    );
  }

  @override
  void dispose() {
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
