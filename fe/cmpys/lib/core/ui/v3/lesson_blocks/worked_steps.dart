import 'package:flutter/material.dart';

import '../../../../app/design_tokens.dart';
import '../../../reading/lesson_fences.dart';
import '../../motion/motion_config.dart';
import '../buttons.dart';
import '../icons.dart';
import '../motion.dart';

/// `WorkedExample` from v3/tutorial.jsx: a `steps` fence revealed one step at
/// a time with "Next step", a running total of the valued steps so far, and
/// the total row as the final summary line. "Next step" is an interaction,
/// so it paces the steps with reduced motion too; only the rise is dropped.
class WorkedSteps extends StatefulWidget {
  const WorkedSteps({
    super.key,
    required this.block,
    this.theme = ReaderTheme.light,
    this.fontSize = 17.5,
  });

  final StepsBlock block;
  final ReaderTheme theme;

  /// The reader's body size; step notes are 1.5 pt smaller.
  final double fontSize;

  /// The running-total number.
  static const runningTotalKey = ValueKey('worked-steps-running-total');

  @override
  State<WorkedSteps> createState() => _WorkedStepsState();
}

class _WorkedStepsState extends State<WorkedSteps> {
  int _shown = 1;
  List<StepRow> get _rows => widget.block.rows;
  bool get _all => _shown >= _rows.length;
  bool get _valued => _rows.any((row) => row.number != null);

  String _format(double value, int places) {
    final text = value.abs().toStringAsFixed(places);
    return value < 0 && double.parse(text) != 0 ? '−$text' : text;
  }

  /// The sum of the valued steps shown so far; once every step is shown,
  /// the fence's stated total, so the number always matches the summary line
  /// whatever precision the rows use.
  String get _runningTotal {
    final total = widget.block.total;
    if (_all && total != null) return total.number.text;
    final valued = [
      for (final row in _rows)
        if (row.number != null) row.number!,
    ];
    final places = valued
        .map((number) => number.places)
        .fold<int>(0, (a, b) => a > b ? a : b);
    final sum = _rows
        .take(_shown)
        .where((row) => row.number != null)
        .fold<double>(0, (acc, row) => acc + row.value!);
    return _format(sum, places);
  }

  String _signed(StepRow row, int index) {
    final number = row.number!;
    if (row.value! < 0) return '−${number.magnitude}';
    return '${row.value! > 0 && index > 0 ? '+' : ''}${number.magnitude}';
  }

  String get _unitSuffix {
    final unit = widget.block.unit;
    return unit == null ? '' : ' $unit';
  }

  @override
  Widget build(BuildContext context) {
    final theme = widget.theme;
    final dark = theme == ReaderTheme.dark;
    final total = widget.block.total;
    final footer = _all
        ? total == null
              ? null
              : V3Rise(
                  duration: const Duration(milliseconds: 500),
                  child: Padding(
                    padding: const EdgeInsets.all(4),
                    child: Row(
                      children: [
                        const V3Icon(
                          V3Icons.check,
                          size: 16,
                          strokeWidth: 2.6,
                          color: AppColors.ember2,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            '${total.label}: ${total.number.text}$_unitSuffix',
                            style: AppTypography.sans(
                              14,
                              FontWeight.w600,
                            ).copyWith(color: AppColors.ember2),
                          ),
                        ),
                      ],
                    ),
                  ),
                )
        : V3Button(
            size: V3Size.md,
            kind: dark ? V3ButtonKind.glass : V3ButtonKind.line,
            full: true,
            iconRight: V3Icons.down,
            onPressed: () => setState(() => _shown++),
            child: const Text('Next step'),
          );
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: theme.card,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: theme.hair),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            decoration: BoxDecoration(
              border: Border(bottom: BorderSide(color: theme.hair)),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        widget.block.title,
                        style: AppTypography.sans(
                          14.5,
                          FontWeight.w600,
                        ).copyWith(color: theme.fg),
                      ),
                      Text(
                        'Step ${_shown.clamp(1, _rows.length)} of ${_rows.length}',
                        style: AppTypography.sans(
                          12,
                        ).copyWith(color: theme.fg2),
                      ),
                    ],
                  ),
                ),
                if (_valued)
                  // At large text the total scales down to share the row
                  // with the title instead of overflowing it.
                  Flexible(
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerRight,
                      child: Semantics(
                        liveRegion: true,
                        label: 'Running total $_runningTotal$_unitSuffix',
                        child: ExcludeSemantics(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              Text(
                                'Running total',
                                style: AppTypography.sans(
                                  11,
                                ).copyWith(color: theme.fg2),
                              ),
                              Row(
                                mainAxisSize: MainAxisSize.min,
                                crossAxisAlignment: CrossAxisAlignment.baseline,
                                textBaseline: TextBaseline.alphabetic,
                                children: [
                                  AnimatedDefaultTextStyle(
                                    duration: MotionConfig.enabled(context)
                                        ? const Duration(milliseconds: 300)
                                        : Duration.zero,
                                    style: AppTypography.display(28)
                                        .merge(AppTypography.tnum)
                                        .copyWith(
                                          color: _all
                                              ? AppColors.ember
                                              : theme.fg,
                                        ),
                                    child: Text(
                                      _runningTotal,
                                      key: WorkedSteps.runningTotalKey,
                                    ),
                                  ),
                                  if (widget.block.unit != null) ...[
                                    const SizedBox(width: 3),
                                    Text(
                                      widget.block.unit!,
                                      style: AppTypography.sans(
                                        12,
                                      ).copyWith(color: theme.fg2),
                                    ),
                                  ],
                                ],
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          for (var i = 0; i < _shown && i < _rows.length; i++)
            V3Rise(
              key: ValueKey('step-$i'),
              duration: const Duration(milliseconds: 500),
              child: _row(i, theme),
            ),
          if (footer != null)
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                border: Border(top: BorderSide(color: theme.hair)),
              ),
              child: footer,
            ),
        ],
      ),
    );
  }

  Widget _row(int i, ReaderTheme theme) {
    final row = _rows[i];
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        border: i == 0 ? null : Border(top: BorderSide(color: theme.hair)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(
                  row.label,
                  style: AppTypography.sans(
                    14.5,
                    FontWeight.w600,
                  ).copyWith(color: theme.fg),
                ),
              ),
              if (row.number != null) ...[
                const SizedBox(width: 10),
                Text(
                  _signed(row, i),
                  style: AppTypography.sans(14.5, FontWeight.w700)
                      .merge(AppTypography.tnum)
                      .copyWith(
                        color: row.value! < 0
                            ? AppColors.danger
                            : AppColors.sage2,
                      ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 4),
          Text(
            row.note,
            style: AppTypography.read(
              widget.fontSize - 1.5,
            ).copyWith(color: theme.fg2, height: 1.55),
          ),
        ],
      ),
    );
  }
}
