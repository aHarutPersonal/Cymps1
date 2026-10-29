import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../app/design_tokens.dart';
import '../motion/motion_config.dart';
import 'buttons.dart';
import 'chips.dart';
import 'feedback.dart';
import 'field.dart';
import 'icons.dart';
import 'motion.dart';
import 'surfaces.dart';
import 'text.dart';

/// Where the [WinSheet] is opened from: the Mentor tab (the mentor replies in
/// chat) or the record (a short mentor note is saved with the entry).
enum WinSheetMode { chat, record }

/// A reported win, as the [WinSheet] hands it back.
@immutable
class V3Win {
  const V3Win({
    required this.text,
    required this.dim,
    required this.size,
    this.note = '',
    this.link = '',
  });

  /// What the learner did (4–120 characters).
  final String text;

  /// The v3 dimension id: `knowledge`, `practice`, `capital`, `network` or
  /// `judgment`.
  final String dim;

  /// 1 Small step, 2 Solid step, 3 Milestone.
  final int size;
  final String note;
  final String link;

  /// The design's `[note, link].filter(Boolean).join(' · ')`.
  String get evidence =>
      [note, link].where((s) => s.trim().isNotEmpty).join(' · ');
}

/// A dimension row of the win sheet (`WIN_DIMS`), keyed by the v3 dimension
/// id. [tint] and [deep] are the design's `oklch(0.95 0.035 h)` and
/// `oklch(0.52 0.14 h)` for the row's hue, converted to sRGB.
@immutable
class WinDim {
  const WinDim({
    required this.id,
    required this.label,
    required this.description,
    required this.icon,
    required this.tint,
    required this.deep,
  });
  final String id;
  final String label;
  final String description;
  final V3Icons icon;
  final Color tint;
  final Color deep;
}

const winDims = <WinDim>[
  WinDim(
    id: 'knowledge',
    label: 'Knowledge',
    description: 'Something you now understand',
    icon: V3Icons.book,
    tint: Color(0xFFEBECFF), // h 285
    deep: Color(0xFF6359B5),
  ),
  WinDim(
    id: 'practice',
    label: 'Practice',
    description: 'Work you did and can show',
    icon: V3Icons.edit,
    tint: Color(0xFFFFE7DD), // h 42
    deep: Color(0xFFA8471B),
  ),
  WinDim(
    id: 'capital',
    label: 'Capital',
    description: 'Money, tools or resources built',
    icon: V3Icons.layers,
    tint: Color(0xFFDDF6E4), // h 155
    deep: Color(0xFF007F43),
  ),
  WinDim(
    id: 'network',
    label: 'Network',
    description: 'People you learned from',
    icon: V3Icons.users,
    tint: Color(0xFFD8F4FF), // h 230
    deep: Color(0xFF0075A9),
  ),
  WinDim(
    id: 'judgment',
    label: 'Judgment',
    description: 'A decision you wrote down',
    icon: V3Icons.target,
    tint: Color(0xFFF9EDD5), // h 85
    deep: Color(0xFF8D6000),
  ),
];

/// The [WinDim] for a v3 dimension id (Knowledge when unknown).
WinDim winDimOf(String id) =>
    winDims.firstWhere((d) => d.id == id, orElse: () => winDims.first);

/// `WIN_SIZES`.
const winSizes = <({int value, String label, String description})>[
  (value: 1, label: 'Small step', description: 'Did it once, on purpose'),
  (value: 2, label: 'Solid step', description: 'Harder than last time'),
  (value: 3, label: 'Milestone', description: 'A first, or a turning point'),
];

/// `WIN_STARTS`.
const winStarts = <String>[
  'Finished a tutorial',
  'Read a full filing',
  'Wrote my own analysis',
  'Asked an expert a question',
];

/// `WIN_EXAMPLES`, rotated as the placeholder of the first step.
const winExamples = <String>[
  'Read Coca-Cola’s 10-K cover to cover',
  'Computed owner earnings for a real company',
  'Explained a moat to a friend without notes',
];

/// The most characters a win's text may have (the "n/120" counter).
const winMaxLength = 120;

/// Opens the [WinSheet] and resolves to the saved win, or null when the
/// learner leaves before "Send". A win that was saved and then dismissed
/// (scrim, back) still resolves to it, so the caller can follow up.
Future<V3Win?> showWinSheet(
  BuildContext context, {
  WinSheetMode mode = WinSheetMode.chat,
  required String mentorShort,
  ImageProvider? mentorImage,
  String mentorInitials = '',
  Color? mentorTint,
  int age = 0,
  Future<void> Function(V3Win win)? onSave,
}) async {
  V3Win? saved;
  final done = await showV3Sheet<V3Win>(
    context,
    max: 0.92,
    builder: (sheetContext) => WinSheet(
      mode: mode,
      mentorShort: mentorShort,
      mentorImage: mentorImage,
      mentorInitials: mentorInitials,
      mentorTint: mentorTint,
      age: age,
      onSave: (win) async {
        await onSave?.call(win);
        saved = win;
      },
      onDone: (win) => Navigator.of(sheetContext).pop(win),
      onClose: () => Navigator.of(sheetContext).maybePop(),
    ),
  );
  return done ?? saved;
}

/// "Report a win" (`v3/chat.jsx` WinSheet), four steps and a confirmation:
/// what you did (rotating examples, the 120-character counter, starters),
/// what it shows (dimension rows with tints), how big it was (size bars,
/// optional evidence and link), then check and send (the card flies out)
/// and "Added to your record".
///
/// [onSave] runs on "Send" while the card flies out; if it throws, the
/// sheet stays on the check step and shows a toast. [onDone] receives the
/// win from the last button ("See the reply" in chat, "Done" in record).
class WinSheet extends StatefulWidget {
  const WinSheet({
    super.key,
    this.mode = WinSheetMode.chat,
    required this.mentorShort,
    this.mentorImage,
    this.mentorInitials = '',
    this.mentorTint,
    this.age = 0,
    this.onSave,
    required this.onDone,
    this.onClose,
  });

  final WinSheetMode mode;
  final String mentorShort;
  final ImageProvider? mentorImage;
  final String mentorInitials;
  final Color? mentorTint;

  /// The learner's age; 0 (unknown) drops the "Age" tag and "at age".
  final int age;
  final Future<void> Function(V3Win win)? onSave;
  final ValueChanged<V3Win> onDone;
  final VoidCallback? onClose;

  /// Keys for tests and later tasks.
  static const textFieldKey = ValueKey('win-sheet-text');
  static const linkFieldKey = ValueKey('win-sheet-link');
  static const cardKey = ValueKey('win-sheet-card');
  static const counterKey = ValueKey('win-sheet-counter');

  @override
  State<WinSheet> createState() => _WinSheetState();
}

class _WinSheetState extends State<WinSheet> {
  static const _titles = [
    'What did you do?',
    'What does it show?',
    'How big was it?',
    'Check and send',
  ];

  final _text = TextEditingController();
  final _note = TextEditingController();
  final _link = TextEditingController();
  int _step = 0;
  int _dir = 1;
  String? _dim;
  int? _size;
  bool _sending = false;
  int _example = 0;
  Timer? _rotate;
  Timer? _advance;

  @override
  void initState() {
    super.initState();
    _text.addListener(_changed);
    _syncRotation();
  }

  @override
  void dispose() {
    _rotate?.cancel();
    _advance?.cancel();
    _text.dispose();
    _note.dispose();
    _link.dispose();
    super.dispose();
  }

  void _changed() => setState(() {});

  /// The examples rotate every 2.6 s while the first step is open.
  void _syncRotation() {
    if (_step == 0) {
      _rotate ??= Timer.periodic(const Duration(milliseconds: 2600), (_) {
        if (mounted) {
          setState(() => _example = (_example + 1) % winExamples.length);
        }
      });
    } else {
      _rotate?.cancel();
      _rotate = null;
    }
  }

  void _go(int n) {
    _advance?.cancel();
    setState(() {
      _dir = n > _step ? 1 : -1;
      _step = n;
    });
    _syncRotation();
  }

  bool get _ok => switch (_step) {
    0 => _text.text.trim().length >= 4,
    1 => _dim != null,
    2 => _size != null,
    _ => true,
  };

  V3Win get _win => V3Win(
    text: _text.text.trim(),
    dim: _dim ?? winDims.first.id,
    size: _size ?? 1,
    note: _note.text.trim(),
    link: _link.text.trim(),
  );

  Future<void> _send() async {
    if (_sending) return;
    setState(() => _sending = true);
    final motion = MotionConfig.enabled(context);
    try {
      await Future.wait([
        Future<void>.sync(() => widget.onSave?.call(_win)),
        if (motion) Future<void>.delayed(const Duration(milliseconds: 1300)),
      ]);
      if (!mounted) return;
      setState(() => _sending = false);
      _go(4);
    } catch (_) {
      if (!mounted) return;
      setState(() => _sending = false);
      showV3Toast(
        context,
        'Couldn’t save your win. Try again.',
        icon: V3Icons.alert,
        tone: V3ToastTone.warn,
      );
    }
  }

  void _pickDim(String id) {
    setState(() => _dim = id);
    _advance?.cancel();
    _advance = Timer(const Duration(milliseconds: 320), () {
      if (mounted && _step == 1) _go(2);
    });
  }

  void _close() {
    if (widget.onClose != null) {
      widget.onClose!();
    } else {
      Navigator.of(context).maybePop();
    }
  }

  bool get _chat => widget.mode == WinSheetMode.chat;

  @override
  Widget build(BuildContext context) {
    final motion = MotionConfig.enabled(context);
    // While the win saves, nothing dismisses the sheet (scrim, drag, system
    // back), so the chat bubble and reply that follow are never lost.
    return PopScope(canPop: !_sending, child: _body(motion));
  }

  Widget _body(bool motion) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (_step < 4) _header(motion),
        _SlideIn(
          key: ValueKey(_step),
          dir: _dir,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (_step < 4)
                Padding(
                  padding: const EdgeInsets.only(bottom: 16),
                  child: Text(
                    _titles[_step],
                    style: AppTypography.display(
                      32,
                    ).copyWith(color: AppColors.ink),
                  ),
                ),
              switch (_step) {
                0 => _whatStep(motion),
                1 => _dimStep(),
                2 => _sizeStep(),
                3 => _checkStep(),
                _ => _doneStep(),
              },
            ],
          ),
        ),
        const SizedBox(height: 22),
        _footer(),
      ],
    );
  }

  Widget _header(bool motion) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 18),
      child: Row(
        children: [
          if (_step > 0)
            V3IconButton(
              icon: V3Icons.left,
              label: 'Back',
              size: 34,
              onPressed: _sending ? null : () => _go(_step - 1),
            )
          else
            Container(
              width: 38,
              height: 38,
              decoration: const BoxDecoration(
                color: AppColors.goldSoft,
                shape: BoxShape.circle,
              ),
              alignment: Alignment.center,
              child: const V3Icon(
                V3Icons.trophy,
                size: 18,
                color: AppColors.gold2,
              ),
            ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Report a win · ${_step + 1} of 4'.toUpperCase(),
                  style: AppTypography.kick,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 6),
                Row(
                  children: [
                    for (var i = 0; i < 4; i++) ...[
                      if (i > 0) const SizedBox(width: 4),
                      Expanded(
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(9),
                          child: Container(
                            height: 4,
                            color: AppColors.hair,
                            alignment: Alignment.centerLeft,
                            child: AnimatedFractionallySizedBox(
                              duration: motion
                                  ? const Duration(milliseconds: 500)
                                  : Duration.zero,
                              curve: AppMotion.out,
                              widthFactor: i <= _step ? 1 : 0,
                              heightFactor: 1,
                              child: const ColoredBox(color: AppColors.gold),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          V3IconButton(
            icon: V3Icons.x,
            label: 'Close',
            size: 34,
            onPressed: _sending ? null : _close,
          ),
        ],
      ),
    );
  }

  Widget _whatStep(bool motion) {
    final length = _text.text.characters.length;
    final textStyle = AppTypography.sans(
      17,
    ).copyWith(height: 1.45, color: AppColors.ink);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Stack(
          children: [
            // The counter sits in the box's flow under the three lines, so
            // large text grows the box instead of covering the third line.
            Container(
              padding: const EdgeInsets.fromLTRB(16, 16, 14, 12),
              decoration: BoxDecoration(
                color: AppColors.paper,
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: AppColors.hair, width: 1.5),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Padding(
                    padding: const EdgeInsets.only(right: 2),
                    child: Semantics(
                      label: 'What did you do?',
                      child: TextField(
                        key: WinSheet.textFieldKey,
                        controller: _text,
                        autofocus: true,
                        minLines: 3,
                        maxLines: 3,
                        style: textStyle,
                        cursorColor: AppColors.ember,
                        textCapitalization: TextCapitalization.sentences,
                        inputFormatters: [
                          LengthLimitingTextInputFormatter(winMaxLength),
                        ],
                        decoration: const InputDecoration.collapsed(
                          hintText: null,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 2),
                  Align(
                    alignment: Alignment.centerRight,
                    child: Text(
                      '$length/$winMaxLength',
                      key: WinSheet.counterKey,
                      style: AppTypography.sans(11.5)
                          .merge(AppTypography.tnum)
                          .copyWith(
                            color: length > 90
                                ? AppColors.ember2
                                : AppColors.ink3,
                          ),
                    ),
                  ),
                ],
              ),
            ),
            if (_text.text.isEmpty)
              Positioned(
                left: 18,
                top: 17,
                right: 18,
                child: IgnorePointer(
                  child: ExcludeSemantics(
                    child: V3Rise(
                      key: ValueKey(_example),
                      duration: const Duration(milliseconds: 500),
                      child: Text(
                        'e.g. ${winExamples[_example]}',
                        style: textStyle.copyWith(color: AppColors.ink3),
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
        Padding(
          padding: const EdgeInsets.only(top: 18, bottom: 10),
          child: Text('Or start from'.toUpperCase(), style: AppTypography.kick),
        ),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (var i = 0; i < winStarts.length; i++)
              V3Rise(
                delay: Duration(milliseconds: i * 40),
                child: V3Chip(
                  on: _text.text == winStarts[i],
                  onPressed: () {
                    _text.value = TextEditingValue(
                      text: winStarts[i],
                      selection: TextSelection.collapsed(
                        offset: winStarts[i].length,
                      ),
                    );
                  },
                  child: Text(winStarts[i]),
                ),
              ),
          ],
        ),
      ],
    );
  }

  Widget _dimStep() {
    final motion = MotionConfig.enabled(context);
    final quick = motion ? const Duration(milliseconds: 250) : Duration.zero;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var i = 0; i < winDims.length; i++) ...[
          if (i > 0) const SizedBox(height: 8),
          V3Rise(
            delay: Duration(milliseconds: i * 50),
            child: Builder(
              builder: (context) {
                final d = winDims[i];
                final on = _dim == d.id;
                return V3Pressable(
                  onTap: () => _pickDim(d.id),
                  selected: on,
                  semanticLabel: '${d.label}. ${d.description}',
                  focusRadius: BorderRadius.circular(18),
                  child: AnimatedContainer(
                    duration: quick,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: on ? d.tint : AppColors.card,
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(
                        color: on ? d.deep : AppColors.hair,
                        width: 1.5,
                      ),
                    ),
                    child: Row(
                      children: [
                        AnimatedRotation(
                          duration: motion
                              ? const Duration(milliseconds: 300)
                              : Duration.zero,
                          turns: on ? -4 / 360 : 0,
                          child: AnimatedScale(
                            duration: motion
                                ? const Duration(milliseconds: 300)
                                : Duration.zero,
                            scale: on ? 1.06 : 1,
                            child: AnimatedContainer(
                              duration: motion
                                  ? const Duration(milliseconds: 300)
                                  : Duration.zero,
                              width: 44,
                              height: 44,
                              decoration: BoxDecoration(
                                color: on ? d.deep : d.tint,
                                borderRadius: BorderRadius.circular(14),
                              ),
                              alignment: Alignment.center,
                              child: V3Icon(
                                d.icon,
                                size: 20,
                                color: on ? Colors.white : d.deep,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                d.label,
                                style: AppTypography.sans(
                                  15.5,
                                  FontWeight.w600,
                                ).copyWith(color: AppColors.ink),
                              ),
                              const SizedBox(height: 1),
                              Text(
                                d.description,
                                style: AppTypography.sans(
                                  12.5,
                                ).copyWith(color: AppColors.ink2),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 14),
                        Container(
                          width: 22,
                          height: 22,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: on ? d.deep : Colors.transparent,
                            border: on
                                ? null
                                : Border.all(
                                    color: AppColors.hair2,
                                    width: 1.5,
                                  ),
                          ),
                          alignment: Alignment.center,
                          child: on
                              ? const V3Pop(
                                  duration: Duration(milliseconds: 300),
                                  child: V3Icon(
                                    V3Icons.check,
                                    size: 12,
                                    strokeWidth: 3,
                                    color: Colors.white,
                                  ),
                                )
                              : null,
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ],
    );
  }

  Widget _sizeStep() {
    final motion = MotionConfig.enabled(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (var i = 0; i < winSizes.length; i++) ...[
                if (i > 0) const SizedBox(width: 8),
                Expanded(
                  child: V3Rise(
                    delay: Duration(milliseconds: i * 60),
                    child: _sizeCard(winSizes[i], motion),
                  ),
                ),
              ],
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.only(top: 20, bottom: 8),
          child: Text(
            'Evidence · optional'.toUpperCase(),
            style: AppTypography.kick,
          ),
        ),
        V3Field(
          controller: _note,
          multiline: true,
          rows: 2,
          placeholder: 'What made it hard, or what you’d do differently',
          inputFormatters: [LengthLimitingTextInputFormatter(5000)],
          onChanged: (_) => setState(() {}),
        ),
        const SizedBox(height: 8),
        Container(
          constraints: const BoxConstraints(minHeight: 50),
          padding: const EdgeInsets.symmetric(horizontal: 14),
          decoration: BoxDecoration(
            color: AppColors.card,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppColors.hair, width: 1.5),
          ),
          child: Row(
            children: [
              const V3Icon(V3Icons.link, size: 17, color: AppColors.ink3),
              const SizedBox(width: 10),
              Expanded(
                child: TextField(
                  key: WinSheet.linkFieldKey,
                  controller: _link,
                  keyboardType: TextInputType.url,
                  autocorrect: false,
                  onChanged: (_) => setState(() {}),
                  inputFormatters: [LengthLimitingTextInputFormatter(2048)],
                  style: AppTypography.sans(15).copyWith(color: AppColors.ink),
                  cursorColor: AppColors.ember,
                  decoration: InputDecoration.collapsed(
                    hintText: 'Link to your work (optional)',
                    hintStyle: AppTypography.sans(
                      15,
                    ).copyWith(color: AppColors.ink3),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _sizeCard(
    ({int value, String label, String description}) s,
    bool motion,
  ) {
    final on = _size == s.value;
    final quick = motion ? const Duration(milliseconds: 250) : Duration.zero;
    return V3Pressable(
      onTap: () => setState(() => _size = s.value),
      selected: on,
      semanticLabel: '${s.label}. ${s.description}',
      focusRadius: BorderRadius.circular(18),
      child: AnimatedContainer(
        duration: quick,
        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 8),
        decoration: BoxDecoration(
          color: on ? AppColors.ink : AppColors.card,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: on ? AppColors.ink : AppColors.hair,
            width: 1.5,
          ),
        ),
        child: Column(
          children: [
            SizedBox(
              height: 54,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  for (var k = 1; k <= 3; k++) ...[
                    if (k > 1) const SizedBox(width: 4),
                    // scaleY(.92 → 1) from the bottom, staggered 60 ms.
                    AnimatedContainer(
                      duration: motion
                          ? Duration(milliseconds: 400 + k * 60)
                          : Duration.zero,
                      curve: AppMotion.spring,
                      width: 12,
                      height: (14 + k * 13) * (on ? 1.0 : 0.92),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(4),
                        color: k <= s.value
                            ? (on ? AppColors.gold : AppColors.gold2)
                            : (on ? const Color(0x2EFFFFFF) : AppColors.paper2),
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 10),
            FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                s.label,
                maxLines: 1,
                style: AppTypography.sans(
                  14,
                  FontWeight.w600,
                ).copyWith(color: on ? Colors.white : AppColors.ink),
              ),
            ),
            const SizedBox(height: 10),
            Text(
              s.description,
              textAlign: TextAlign.center,
              style: AppTypography.sans(11.5).copyWith(
                height: 1.35,
                color: on ? const Color(0xA6FFFFFF) : AppColors.ink3,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _avatar(double size) => V3Avatar(
    image: widget.mentorImage,
    initials: widget.mentorInitials,
    tint: widget.mentorTint,
    size: size,
    gray: true,
  );

  Widget _checkStep() {
    final d = winDimOf(_dim ?? winDims.first.id);
    final size = _size ?? 1;
    final note = _note.text.trim();
    final link = _link.text.trim();
    final card = Container(
      key: WinSheet.cardKey,
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: AppColors.hair),
        boxShadow: const [
          BoxShadow(
            color: Color(0x8017151A),
            blurRadius: 40,
            spreadRadius: -26,
            offset: Offset(0, 20),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(height: 4, color: AppColors.ember),
          Padding(
            padding: const EdgeInsets.all(18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    V3Tag(
                      background: d.tint,
                      color: d.deep,
                      icon: d.icon,
                      child: Text(d.label),
                    ),
                    if (widget.age > 0) ...[
                      const SizedBox(width: 6),
                      V3Tag(child: Text('Age ${widget.age}')),
                    ],
                    const Spacer(),
                    SizedBox(
                      height: 16,
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          for (var k = 1; k <= 3; k++) ...[
                            if (k > 1) const SizedBox(width: 2),
                            Container(
                              width: 4,
                              height: 4.0 + k * 4,
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(2),
                                color: k <= size
                                    ? AppColors.gold2
                                    : AppColors.hair,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Text(
                  _text.text.trim(),
                  style: AppTypography.sans(19, FontWeight.w600).copyWith(
                    letterSpacing: -0.015 * 19,
                    height: 1.3,
                    color: AppColors.ink,
                  ),
                ),
                if (note.isNotEmpty || link.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text.rich(
                      TextSpan(
                        children: [
                          TextSpan(text: note),
                          if (note.isNotEmpty && link.isNotEmpty)
                            const TextSpan(text: ' · '),
                          if (link.isNotEmpty)
                            TextSpan(
                              text: link,
                              style: const TextStyle(color: AppColors.ember2),
                            ),
                        ],
                      ),
                      style: AppTypography.sans(
                        13.5,
                      ).copyWith(height: 1.5, color: AppColors.ink2),
                    ),
                  ),
                // Record wins carry no mentor note, so there is nothing to
                // promise here (only chat wins get a reply).
                if (_chat) ...[
                  const SizedBox(height: 14),
                  const _DashedLine(),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      _avatar(22),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          '${widget.mentorShort} will reply in chat',
                          style: AppTypography.sans(
                            12.5,
                          ).copyWith(color: AppColors.ink3),
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _FlyOut(
          fly: _sending,
          child: V3Pop(
            duration: const Duration(milliseconds: 500),
            child: card,
          ),
        ),
        const SizedBox(height: 14),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Padding(
              padding: EdgeInsets.only(top: 1),
              child: V3Icon(V3Icons.info, size: 14, color: AppColors.ink3),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'Saved to Your record on this device. A reported win isn’t a verified achievement.',
                style: AppTypography.sans(
                  12.5,
                ).copyWith(height: 1.45, color: AppColors.ink3),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _doneStep() {
    final d = winDimOf(_dim ?? winDims.first.id);
    final ageText = widget.age > 0 ? ' at age ${widget.age}' : '';
    return Padding(
      padding: const EdgeInsets.only(top: 18, bottom: 4),
      child: Column(
        children: [
          SizedBox(
            width: 92,
            height: 92,
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                const Positioned.fill(
                  child: V3Pop(
                    duration: Duration(milliseconds: 600),
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: AppColors.gold,
                        shape: BoxShape.circle,
                      ),
                    ),
                  ),
                ),
                const Center(
                  child: V3Icon(
                    V3Icons.trophy,
                    size: 40,
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                ),
                const Positioned.fill(
                  child: IgnorePointer(
                    child: V3Burst(
                      color: AppColors.gold,
                      radius: 62,
                      count: 14,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          V3Rise(
            delay: const Duration(milliseconds: 150),
            child: Text(
              'Added to your record',
              textAlign: TextAlign.center,
              style: AppTypography.display(34).copyWith(color: AppColors.ink),
            ),
          ),
          const SizedBox(height: 8),
          V3Rise(
            delay: const Duration(milliseconds: 250),
            child: Text.rich(
              TextSpan(
                children: [
                  const TextSpan(text: 'Filed under '),
                  TextSpan(
                    text: d.label,
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      color: d.deep,
                    ),
                  ),
                  TextSpan(
                    text: _chat
                        ? '$ageText. ${widget.mentorShort} is reading it now.'
                        : '$ageText.',
                  ),
                ],
              ),
              textAlign: TextAlign.center,
              style: AppTypography.sans(
                14.5,
              ).copyWith(height: 1.5, color: AppColors.ink2),
            ),
          ),
          const SizedBox(height: 18),
          V3Rise(
            delay: const Duration(milliseconds: 350),
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.paper,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Row(
                children: [
                  if (_chat) ...[_avatar(34), const SizedBox(width: 10)],
                  Expanded(
                    child: DefaultTextStyle.merge(
                      style: AppTypography.sans(
                        13.5,
                      ).copyWith(color: AppColors.ink2),
                      child: _chat
                          ? const Row(
                              children: [
                                Flexible(child: Text('Writing a reply')),
                                SizedBox(width: 8),
                                V3Typing(),
                              ],
                            )
                          : const Text('Saved to your record.'),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _footer() {
    if (_step < 3) {
      return V3Button(
        full: true,
        disabled: !_ok,
        iconRight: V3Icons.arrowR,
        onPressed: () => _go(_step + 1),
        child: const Text('Continue'),
      );
    }
    if (_step == 3) {
      return V3Button(
        full: true,
        loading: _sending,
        icon: V3Icons.send,
        onPressed: _send,
        child: Text('Send to ${widget.mentorShort}'),
      );
    }
    return V3Button(
      full: true,
      kind: V3ButtonKind.dark,
      iconRight: _chat ? V3Icons.arrowR : null,
      onPressed: () => widget.onDone(_win),
      child: Text(_chat ? 'See the reply' : 'Done'),
    );
  }
}

/// The step body's entrance (`wsR` / `wsL`): fade in while sliding 36 pt
/// from the side the learner is moving towards.
class _SlideIn extends StatelessWidget {
  const _SlideIn({super.key, required this.dir, required this.child});
  final int dir;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (!MotionConfig.enabled(context)) return child;
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: const Duration(milliseconds: 450),
      curve: AppMotion.out,
      child: child,
      builder: (context, v, child) => Opacity(
        opacity: v.clamp(0.0, 1.0),
        child: Transform.translate(
          offset: Offset(dir * 36 * (1 - v), 0),
          child: child,
        ),
      ),
    );
  }
}

/// The check card's send (`wsFly`, 1.1 s): it lifts 30 pt and shrinks to .92
/// by 60 %, then flies 140 pt up, shrinking to .6, turning −4° and fading.
class _FlyOut extends StatelessWidget {
  const _FlyOut({required this.fly, required this.child});
  final bool fly;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final on = fly && MotionConfig.enabled(context);
    // Always the same tree (identity transforms at rest), so the card's
    // state — its pop-in — survives the send.
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: on ? 1 : 0),
      duration: on ? const Duration(milliseconds: 1100) : Duration.zero,
      curve: AppMotion.io,
      child: child,
      builder: (context, t, child) {
        double dy, scale, turn, opacity;
        if (t <= 0.6) {
          final k = t / 0.6;
          dy = -30 * k;
          scale = 1 - 0.08 * k;
          turn = 0;
          opacity = 1;
        } else {
          final k = (t - 0.6) / 0.4;
          dy = -30 - 110 * k;
          scale = 0.92 - 0.32 * k;
          turn = -4 * k;
          opacity = 1 - k;
        }
        return Opacity(
          opacity: opacity.clamp(0.0, 1.0),
          child: Transform.translate(
            offset: Offset(0, dy),
            child: Transform.rotate(
              angle: turn * 3.141592653589793 / 180,
              child: Transform.scale(scale: scale, child: child),
            ),
          ),
        );
      },
    );
  }
}

/// `border-top: 1px dashed var(--hair2)`.
class _DashedLine extends StatelessWidget {
  const _DashedLine();

  @override
  Widget build(BuildContext context) => const SizedBox(
    height: 1,
    width: double.infinity,
    child: CustomPaint(painter: _DashPainter()),
  );
}

class _DashPainter extends CustomPainter {
  const _DashPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = AppColors.hair2
      ..strokeWidth = 1;
    for (var x = 0.0; x < size.width; x += 6) {
      canvas.drawLine(
        Offset(x, 0.5),
        Offset((x + 3).clamp(0, size.width), 0.5),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(_DashPainter oldDelegate) => false;
}
