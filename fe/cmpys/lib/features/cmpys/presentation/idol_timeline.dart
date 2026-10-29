import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/design_tokens.dart';
import '../../../core/ui/v3/v3.dart';
import '../../session/data/session_repository.dart';
import '../../session/models/session_models.dart';

/// How [CmpysIdolTimeline] lays out its entries.
enum CmpysIdolTimelineLayout {
  /// The mentor preview (`v3/onboard2.jsx` MentorPreview): a rail of dots
  /// with the age above each event.
  dots,

  /// The mentor context screen (`v3/you.jsx` MentorScreen): one row per
  /// event, the age in a fixed column, hairlines between rows.
  rows,
}

/// The design's `oklch(0.8 0.12 42)`, converted to sRGB once: the age label of
/// the highlighted node.
const Color _emberLight = Color(0xFFFFA37F);

/// A mentor's documented timeline from the idol catalog, on the night
/// ground, with the event at the user's own [age] highlighted in ember.
///
/// It loads on entry, shows skeletons while loading, an inline "Try again"
/// on failure, and "No documented timeline yet." for a mentor the catalog
/// does not know. Shared by the mentor preview and the mentor context screen.
class CmpysIdolTimeline extends ConsumerStatefulWidget {
  const CmpysIdolTimeline({
    super.key,
    required this.idolName,
    required this.age,
    this.layout = CmpysIdolTimelineLayout.dots,
  });

  final String idolName;

  /// The user's age; the entry at this age is highlighted. Null (or an age
  /// no entry has) highlights nothing.
  final int? age;

  final CmpysIdolTimelineLayout layout;

  @override
  ConsumerState<CmpysIdolTimeline> createState() => _CmpysIdolTimelineState();
}

class _CmpysIdolTimelineState extends ConsumerState<CmpysIdolTimeline> {
  /// Loads again: the timeline is the shared [idolTimelineProvider].
  void _retry() => ref.invalidate(idolTimelineProvider(widget.idolName));

  bool _mine(IdolTimelineEntry entry) =>
      widget.age != null && entry.age == widget.age;

  /// The highlight is colour only on screen; screen readers hear it.
  String _label(IdolTimelineEntry entry) =>
      _mine(entry) ? 'Age ${entry.age}, your age' : 'Age ${entry.age}';

  @override
  Widget build(BuildContext context) {
    // A new name is a new family key, so it loads on its own.
    final timeline = ref.watch(idolTimelineProvider(widget.idolName));
    final loading = timeline.isLoading;
    final failed = !loading && timeline.hasError;
    final entries = timeline.valueOrNull ?? const <IdolTimelineEntry>[];
    if (loading && widget.layout == CmpysIdolTimelineLayout.rows) {
      // Skeleton rows aligned with the age column and the event text.
      return Column(children: [_skeletonRow(null), _skeletonRow(220)]);
    }
    if (loading) {
      return const Padding(
        padding: EdgeInsets.only(left: 22),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            V3Skel(dark: true, width: 56, height: 12),
            SizedBox(height: 10),
            V3Skel(dark: true, height: 15),
            SizedBox(height: 26),
            V3Skel(dark: true, width: 56, height: 12),
            SizedBox(height: 10),
            V3Skel(dark: true, width: 220, height: 15),
          ],
        ),
      );
    }
    if (failed) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const V3Icon(V3Icons.alert, size: 16, color: AppColors.nink3),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Couldn’t load the timeline.',
                  style: AppTypography.sans(
                    15,
                  ).copyWith(color: AppColors.nink2),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          V3Button(
            kind: V3ButtonKind.glass,
            size: V3Size.sm,
            icon: V3Icons.refresh,
            onPressed: _retry,
            child: const Text('Try again'),
          ),
        ],
      );
    }
    if (entries.isEmpty) {
      return Text(
        'No documented timeline yet.',
        style: AppTypography.sans(15).copyWith(color: AppColors.nink3),
      );
    }
    if (widget.layout == CmpysIdolTimelineLayout.rows) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (var i = 0; i < entries.length; i++)
            V3Rise(
              delay: Duration(milliseconds: math.min(i, 8) * 60),
              child: _row(i, entries[i]),
            ),
        ],
      );
    }
    return Stack(
      children: [
        const Positioned(
          left: 5,
          top: 6,
          bottom: 6,
          width: 1.5,
          child: ColoredBox(color: Color(0x24FFFFFF)),
        ),
        Padding(
          padding: const EdgeInsets.only(left: 22),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (var i = 0; i < entries.length; i++)
                V3Rise(
                  delay: Duration(milliseconds: math.min(i, 8) * 70),
                  child: _node(i, entries[i]),
                ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _skeletonRow(double? textWidth) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        children: [
          const SizedBox(
            width: 52,
            child: Align(
              alignment: Alignment.centerLeft,
              child: V3Skel(dark: true, width: 44, height: 13),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Align(
              alignment: Alignment.centerLeft,
              child: V3Skel(dark: true, width: textWidth, height: 15),
            ),
          ),
        ],
      ),
    );
  }

  Widget _node(int index, IdolTimelineEntry entry) {
    final mine = _mine(entry);
    return Padding(
      padding: const EdgeInsets.only(bottom: 18),
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned(
            left: -22,
            top: 4,
            child: Container(
              key: ValueKey('timeline-dot-$index'),
              width: 12,
              height: 12,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: mine ? AppColors.ember : AppColors.night3,
                border: Border.all(color: const Color(0x66FFFFFF), width: 2),
              ),
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Age ${entry.age}',
                key: ValueKey('timeline-age-$index'),
                semanticsLabel: _label(entry),
                style: AppTypography.sans(12, FontWeight.w600)
                    .merge(AppTypography.tnum)
                    .copyWith(color: mine ? _emberLight : AppColors.nink3),
              ),
              const SizedBox(height: 2),
              Text(
                entry.text,
                style: AppTypography.sans(
                  15,
                ).copyWith(height: 1.45, color: Colors.white),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _row(int index, IdolTimelineEntry entry) {
    final mine = _mine(entry);
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 10),
      decoration: BoxDecoration(
        border: index == 0
            ? null
            : const Border(top: BorderSide(color: Color(0x14FFFFFF))),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 52,
            child: Text(
              'Age ${entry.age}',
              key: ValueKey('timeline-age-$index'),
              semanticsLabel: _label(entry),
              style: AppTypography.sans(13, FontWeight.w700)
                  .merge(AppTypography.tnum)
                  .copyWith(color: mine ? _emberLight : AppColors.nink3),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Text(
              entry.text,
              style: AppTypography.sans(
                14.5,
              ).copyWith(height: 1.45, color: Colors.white),
            ),
          ),
        ],
      ),
    );
  }
}
