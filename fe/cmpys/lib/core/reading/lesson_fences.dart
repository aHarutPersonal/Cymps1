// Native tutorial_v1 lesson blocks: a pure Dart mirror of the backend grammar
// in cmpys/backend/app/services/planning/tutorial_blocks.py and of the section
// contract in tutorial_visuals.py.
//
// Every parser takes a fence body (the lines between the opening ```kind line
// and the closing ``` line) and returns a block, or null when the body breaks
// its grammar. The reader then shows that body as plain lines, so generator
// drift never blanks a section.
//
// Differences from the backend, all deliberately lenient for rendering:
// - Banned characters ({ } ; => and HTML tags) are a backend rejection only;
//   the A6 report says the reader may simply render them.
// - Totals are checked with doubles plus 1e-9 instead of exact decimals.
// - `comparison` and `diagram` keep their existing reader parsers
//   (learning_comparison.dart / learning_diagram.dart).

/// The six native fence kinds, as `BLOCK_KINDS` in tutorial_blocks.py.
const lessonFenceKinds = <String>{
  'formula',
  'chart',
  'steps',
  'check',
  'diagram',
  'comparison',
};

/// Kinds the reader gathers into "Seeing it": the primary visuals
/// (formula, diagram, comparison) and the worked example's chart.
const lessonVisualKinds = <String>{'formula', 'chart', 'diagram', 'comparison'};

// ── grammar primitives ──────────────────────────────────────────────────────

final _number = RegExp(r'^[+\-−]?[0-9]+(\.[0-9]+)?$');
final _header = RegExp(r'^(title|type|unit)\s*:\s*(.*)$', caseSensitive: false);
final _term = RegExp(r'^([=+\-−±×÷])\s+(\S.*)$');
final _option = RegExp(r'^-\s+\[([ xX])\]\s+(.*)$');
final _answer = RegExp(
  r'^answer\s*:([^|]*)\|\s*unit\s*:([^|]*)\|\s*tolerance\s*:([^|]*)$',
  caseSensitive: false,
);
final _question = RegExp(r'^Q\s*:(.*)$', caseSensitive: false);
final _why = RegExp(r'^Why\s*:(.*)$', caseSensitive: false);

/// Thrown inside a parser; the public entry points turn it into null.
class _Reject implements Exception {
  const _Reject();
}

const _reject = _Reject();

List<String> _lines(String body) => [
  for (final line in body.split(RegExp(r'\r\n|\r|\n')))
    if (line.trim().isNotEmpty) line.trim(),
];

/// Trimmed text of 1..[limit] code points (0..[limit] when [empty]).
String _text(String value, int limit, {bool empty = false}) {
  final text = value.trim();
  final length = text.runes.length;
  if ((length == 0 && !empty) || length > limit) throw _reject;
  return text;
}

/// A NUMBER as the grammar defines it, kept with its display text.
class LessonNumber {
  const LessonNumber._(this.value, this.text, this.places);

  /// The numeric value.
  final double value;

  /// The number as written, with an ASCII minus shown as "−".
  final String text;

  /// Decimal places as written ("4.50" has 2).
  final int places;

  /// The digits without their sign ("−24" → "24").
  String get magnitude => text.replaceFirst(RegExp(r'^[+\-−]'), '');
}

LessonNumber _parseNumber(String raw) {
  final text = raw.trim();
  if (!_number.hasMatch(text)) throw _reject;
  final value = double.parse(text.replaceAll('−', '-'));
  // A digit run too long for a double parses to Infinity: not a number.
  if (!value.isFinite) throw _reject;
  final dot = text.indexOf('.');
  return LessonNumber._(
    value,
    text.startsWith('-') ? '−${text.substring(1)}' : text,
    dot < 0 ? 0 : text.length - dot - 1,
  );
}

String _sign(String value) => value == '-' ? '−' : value;

/// Leading `key: value` lines; the rows start at the first other line.
(Map<String, String>, List<String>) _headers(
  List<String> lines,
  Set<String> allowed,
  List<String> required,
) {
  final headers = <String, String>{};
  var index = 0;
  while (index < lines.length) {
    final match = _header.firstMatch(lines[index]);
    if (match == null) break;
    final key = match[1]!.toLowerCase();
    if (!allowed.contains(key)) break;
    if (headers.containsKey(key)) throw _reject;
    headers[key] = match[2]!.trim();
    index++;
  }
  if (required.any((key) => !headers.containsKey(key))) throw _reject;
  return (headers, lines.sublist(index));
}

/// A stated total against its rows (Grammar update).
///
/// [relative] (waterfall): within 0.5% of the total, never stricter than half
/// a unit of the finest decimal shown. Otherwise (steps): equal up to display
/// rounding only, half a unit of the coarsest decimal shown.
void _requireTotal(
  List<LessonNumber> parts,
  LessonNumber total, {
  required bool relative,
}) {
  final places = [for (final part in parts) part.places, total.places];
  final p = relative
      ? places.reduce((a, b) => a > b ? a : b)
      : places.reduce((a, b) => a < b ? a : b);
  final rounding = 0.5 * _pow10(-p);
  final relativeAllowance = total.value.abs() * 0.005;
  final allowed = relative && relativeAllowance > rounding
      ? relativeAllowance
      : rounding;
  final sum = parts.fold<double>(0, (acc, part) => acc + part.value);
  if ((sum - total.value).abs() > allowed + 1e-9) throw _reject;
}

double _pow10(int exponent) {
  var result = 1.0;
  for (var i = 0; i < exponent.abs(); i++) {
    result *= 10;
  }
  return exponent < 0 ? 1 / result : result;
}

// ── formula ─────────────────────────────────────────────────────────────────

class FormulaTerm {
  const FormulaTerm(this.sign, this.label);

  /// One of = + − ± × ÷ (an ASCII "-" is stored as "−").
  final String sign;
  final String label;
}

class FormulaBlock {
  const FormulaBlock(this.title, this.terms);

  final String title;
  final List<FormulaTerm> terms;
}

FormulaBlock _formula(String body) {
  final (headers, rows) = _headers(_lines(body), {'title'}, ['title']);
  if (rows.length < 2 || rows.length > 6) throw _reject;
  final terms = <FormulaTerm>[];
  for (final line in rows) {
    final match = _term.firstMatch(line);
    if (match == null) throw _reject;
    terms.add(FormulaTerm(_sign(match[1]!), _text(match[2]!, 60)));
  }
  if (terms.first.sign != '=') throw _reject;
  return FormulaBlock(_text(headers['title']!, 60), terms);
}

// ── chart ───────────────────────────────────────────────────────────────────

enum ChartType { waterfall, bars }

class ChartRow {
  const ChartRow(this.label, this.number, {this.total = false});

  final String label;
  final LessonNumber number;

  /// A `= <label> | <number>` row (the waterfall's last row).
  final bool total;

  double get value => number.value;
  String get text => number.text;
}

class ChartBlock {
  const ChartBlock(this.type, this.title, this.unit, this.rows);

  final ChartType type;
  final String title;

  /// Null when the fence has no unit or an empty one.
  final String? unit;
  final List<ChartRow> rows;
}

ChartBlock _chart(String body) {
  final (headers, lines) = _headers(
    _lines(body),
    {'type', 'title', 'unit'},
    ['type', 'title'],
  );
  final type = switch (headers['type']!.toLowerCase()) {
    'waterfall' => ChartType.waterfall,
    'bars' => ChartType.bars,
    _ => throw _reject,
  };
  if (lines.length < 2 || lines.length > 8) throw _reject;
  final rows = <ChartRow>[];
  for (final line in lines) {
    final cells = line.split('|');
    if (cells.length != 2) throw _reject;
    final label = cells[0].trim();
    final total = label.startsWith('=');
    rows.add(
      ChartRow(
        _text(total ? label.substring(1) : label, 24),
        _parseNumber(cells[1]),
        total: total,
      ),
    );
  }
  final totals = [
    for (var i = 0; i < rows.length; i++)
      if (rows[i].total) i,
  ];
  if (type == ChartType.waterfall) {
    if (totals.length != 1 || totals.single != rows.length - 1) throw _reject;
    _requireTotal(
      [for (final row in rows.take(rows.length - 1)) row.number],
      rows.last.number,
      relative: true,
    );
  } else if (totals.isNotEmpty) {
    throw _reject;
  }
  final unit = _text(headers['unit'] ?? '', 12, empty: true);
  return ChartBlock(
    type,
    _text(headers['title']!, 80),
    unit.isEmpty ? null : unit,
    rows,
  );
}

// ── steps ───────────────────────────────────────────────────────────────────

class StepRow {
  const StepRow(this.label, this.number, this.note);

  final String label;

  /// Null for a reasoning step with no number.
  final LessonNumber? number;
  final String note;

  double? get value => number?.value;
  String? get text => number?.text;
}

class StepTotal {
  const StepTotal(this.label, this.number);

  final String label;
  final LessonNumber number;

  double get value => number.value;
}

class StepsBlock {
  const StepsBlock(this.title, this.unit, this.rows, this.total);

  final String title;
  final String? unit;
  final List<StepRow> rows;
  final StepTotal? total;
}

StepsBlock _steps(String body) {
  final (headers, rest) = _headers(_lines(body), {'title', 'unit'}, ['title']);
  final lines = [...rest];
  StepTotal? total;
  if (lines.isNotEmpty && lines.last.startsWith('=')) {
    final cells = lines.removeLast().substring(1).split('|');
    if (cells.length != 2) throw _reject;
    total = StepTotal(_text(cells[0], 60), _parseNumber(cells[1]));
  }
  if (lines.length < 2 || lines.length > 6) throw _reject;
  final rows = <StepRow>[];
  for (final line in lines) {
    final cells = line.split('|');
    if (line.startsWith('=') || cells.length != 3) throw _reject;
    rows.add(
      StepRow(
        _text(cells[0], 60),
        cells[1].trim().isEmpty ? null : _parseNumber(cells[1]),
        _text(cells[2], 160),
      ),
    );
  }
  if (total != null) {
    final values = [
      for (final row in rows)
        if (row.number != null) row.number!,
    ];
    if (values.isEmpty) throw _reject;
    _requireTotal(values, total.number, relative: false);
  }
  final unit = _text(headers['unit'] ?? '', 12, empty: true);
  return StepsBlock(
    _text(headers['title']!, 80),
    unit.isEmpty ? null : unit,
    rows,
    total,
  );
}

// ── check ───────────────────────────────────────────────────────────────────

enum CheckKind { single, selectAll, numeric }

class CheckOption {
  const CheckOption(this.text, this.correct);

  final String text;
  final bool correct;
}

class NumericAnswer {
  const NumericAnswer(this.number, this.unit, this.tolerance);

  final LessonNumber number;

  /// May be empty.
  final String unit;

  /// Absolute, never negative.
  final double tolerance;

  double get value => number.value;

  /// Whether [guess] is within the fence's tolerance of the answer.
  bool accepts(double guess) => (guess - value).abs() <= tolerance + 1e-9;
}

class CheckBlock {
  const CheckBlock(this.question, this.options, this.numeric, this.why);

  final String question;

  /// Empty for a numeric check.
  final List<CheckOption> options;
  final NumericAnswer? numeric;
  final String why;

  /// Numeric, select-all (more than one `[x]`) or single choice.
  CheckKind get kind => numeric != null
      ? CheckKind.numeric
      : options.where((option) => option.correct).length > 1
      ? CheckKind.selectAll
      : CheckKind.single;
}

CheckBlock _check(String body) {
  final lines = _lines(body);
  final question = lines.isEmpty ? null : _question.firstMatch(lines.first);
  final why = lines.length > 1 ? _why.firstMatch(lines.last) : null;
  if (question == null || why == null) throw _reject;
  final middle = lines.sublist(1, lines.length - 1);
  final answer = middle.length == 1 ? _answer.firstMatch(middle.single) : null;
  NumericAnswer? numeric;
  var options = const <CheckOption>[];
  if (answer != null) {
    final tolerance = _parseNumber(answer[3]!);
    if (tolerance.value < 0) throw _reject;
    numeric = NumericAnswer(
      _parseNumber(answer[1]!),
      _text(answer[2]!, 12, empty: true),
      tolerance.value,
    );
  } else {
    if (middle.length < 2 || middle.length > 4) throw _reject;
    options = [
      for (final line in middle)
        switch (_option.firstMatch(line)) {
          final match? => CheckOption(_text(match[2]!, 120), match[1] != ' '),
          null => throw _reject,
        },
    ];
    if (!options.any((option) => option.correct)) throw _reject;
  }
  return CheckBlock(
    _text(question[1]!, 240),
    options,
    numeric,
    _text(why[1]!, 280),
  );
}

// ── public parsers ──────────────────────────────────────────────────────────

T? _parse<T>(T Function(String) parser, String body) {
  try {
    return parser(body);
  } on _Reject {
    return null;
  } on FormatException {
    return null;
  }
}

FormulaBlock? parseFormulaFence(String body) => _parse(_formula, body);

ChartBlock? parseChartFence(String body) => _parse(_chart, body);

StepsBlock? parseStepsFence(String body) => _parse(_steps, body);

CheckBlock? parseCheckFence(String body) => _parse(_check, body);

// ── envelope ────────────────────────────────────────────────────────────────

/// `^```(kind)[ \t]*\r?\n(.*?)^```[ \t]*\r?$` with MULTILINE and DOTALL.
final _fence = RegExp(
  r'^```(formula|chart|steps|check|diagram|comparison)[ \t]*\r?\n([\s\S]*?)^```[ \t]*\r?$',
  multiLine: true,
);

/// One native fence found in lesson markdown.
class LessonFenceMatch {
  const LessonFenceMatch(this.kind, this.body, this.start, this.end);

  final String kind;
  final String body;
  final int start;
  final int end;
}

/// Every native block that opens at the start of a line.
List<LessonFenceMatch> findLessonFences(String text) => [
  for (final match in _fence.allMatches(text))
    LessonFenceMatch(match[1]!, match[2]!, match.start, match.end),
];

/// A run of lesson markdown: prose or one native fence.
sealed class LessonPiece {
  const LessonPiece();
}

class LessonProse extends LessonPiece {
  const LessonProse(this.markdown);

  final String markdown;
}

class LessonFence extends LessonPiece {
  const LessonFence(this.kind, this.body);

  final String kind;
  final String body;
}

/// Splits [markdown] into trimmed prose runs and native fences, in order.
List<LessonPiece> splitLessonPieces(String markdown) {
  final pieces = <LessonPiece>[];
  var cursor = 0;
  void prose(String text) {
    final trimmed = text.trim();
    if (trimmed.isNotEmpty) pieces.add(LessonProse(trimmed));
  }

  for (final fence in findLessonFences(markdown)) {
    prose(markdown.substring(cursor, fence.start));
    pieces.add(LessonFence(fence.kind, fence.body));
    cursor = fence.end;
  }
  prose(markdown.substring(cursor));
  return pieces;
}

// ── section contract ────────────────────────────────────────────────────────

/// Canonical backend headings (`PLAN_DETAIL_SECTION_ROWS`) → reader section id
/// and the design's label (`SECTIONS` in v3/tutorial.jsx). Guided Practice is
/// legacy-only and reads as "Try it".
const _canonical = <String, (String, String)>{
  'Why This Matters': ('why', 'Why this skill'),
  'Core Framework': ('idea', 'The idea'),
  'Worked Example': ('example', 'Worked example'),
  'Failure Modes': ('errors', 'Common errors'),
  'Guided Practice': ('try', 'Try it'),
  'Check Your Understanding': ('check', 'Check yourself'),
  'References': ('refs', 'References'),
};

/// Reader order: the design's `SECTIONS`, with legacy "Try it" where Guided
/// Practice sat in the backend order (after Failure Modes).
const _order = [
  'why',
  'idea',
  'visual',
  'example',
  'errors',
  'try',
  'check',
  'refs',
];

final _sectionHeading = RegExp(r'^## (.+?)[ \t]*$', multiLine: true);
final _anyHeading = RegExp(r'^## (.+?)[ \t]*\r?$', multiLine: true);

class LessonOutlineSection {
  const LessonOutlineSection(this.id, this.label, this.pieces);

  /// `why`, `idea`, `visual`, `example`, `errors`, `try`, `check`, `refs`;
  /// `lead` or `h<n>` for lessons without canonical headings.
  final String id;

  /// The kicker heading; null for an untitled lead.
  final String? label;
  final List<LessonPiece> pieces;
}

class LessonOutline {
  const LessonOutline(
    this.sections, {
    required this.canonical,
    required this.legacy,
  });

  final List<LessonOutlineSection> sections;

  /// The lesson uses the backend's canonical `## ` headings.
  final bool canonical;

  /// A legacy lesson: it has Guided Practice, or no canonical headings.
  final bool legacy;
}

/// Lines before the first section, without the `# Title` line.
String _lead(String text) =>
    text.split('\n').where((line) => !line.startsWith('# ')).join('\n').trim();

/// Reader sections for [markdown], following A6's section contract.
///
/// With canonical headings, each heading's body runs to the next canonical
/// heading and the first copy of a heading wins (`lesson_sections`). Native
/// visuals (formula, chart, diagram, comparison) from any section gather in
/// "Seeing it", which exists only when there is one; a missing heading
/// omits its section. Without canonical headings the lesson keeps its own
/// `## ` headings and its fences stay in place.
LessonOutline outlineLesson(String markdown) {
  final matches = [
    for (final match in _sectionHeading.allMatches(markdown))
      if (_canonical.containsKey(match[1])) match,
  ];
  if (matches.isEmpty) return _ownHeadings(markdown);

  final bodies = <String, String>{};
  for (var i = 0; i < matches.length; i++) {
    final end = i + 1 < matches.length ? matches[i + 1].start : markdown.length;
    final id = _canonical[matches[i][1]]!.$1;
    bodies.putIfAbsent(
      id,
      () => markdown.substring(matches[i].end, end).trim(),
    );
  }
  final pieces = <String, List<LessonPiece>>{};
  final visuals = <LessonPiece>[];
  for (final id in _order) {
    final body = bodies[id];
    if (body == null) continue;
    final kept = <LessonPiece>[];
    for (final piece in splitLessonPieces(body)) {
      if (piece is LessonFence &&
          lessonVisualKinds.contains(piece.kind) &&
          id != 'refs') {
        visuals.add(piece);
      } else {
        kept.add(piece);
      }
    }
    pieces[id] = kept;
  }
  if (visuals.isNotEmpty) pieces['visual'] = visuals;
  final labels = {
    for (final entry in _canonical.values) entry.$1: entry.$2,
    'visual': 'Seeing it',
  };
  final lead = _lead(markdown.substring(0, matches.first.start));
  return LessonOutline(
    [
      if (lead.isNotEmpty)
        LessonOutlineSection('lead', null, splitLessonPieces(lead)),
      for (final id in _order)
        if (pieces.containsKey(id))
          LessonOutlineSection(id, labels[id], pieces[id]!),
    ],
    canonical: true,
    legacy: bodies.containsKey('try'),
  );
}

LessonOutline _ownHeadings(String markdown) {
  final matches = _anyHeading.allMatches(markdown).toList();
  final sections = <LessonOutlineSection>[];
  final lead = _lead(
    matches.isEmpty ? markdown : markdown.substring(0, matches.first.start),
  );
  if (lead.isNotEmpty) {
    sections.add(LessonOutlineSection('lead', null, splitLessonPieces(lead)));
  }
  for (var i = 0; i < matches.length; i++) {
    final end = i + 1 < matches.length ? matches[i + 1].start : markdown.length;
    sections.add(
      LessonOutlineSection(
        'h$i',
        matches[i][1]!.trim(),
        splitLessonPieces(markdown.substring(matches[i].end, end)),
      ),
    );
  }
  return LessonOutline(sections, canonical: false, legacy: true);
}

// ── common errors ───────────────────────────────────────────────────────────

final _listItem = RegExp(r'^\s{0,3}(?:[-*+•]|\d+[.)])\s+(.*)$');

/// A Failure Modes body split into ✕ cards: the prose before the list, one
/// item per card (continuation lines joined), and any prose after it.
({String lead, List<String> items, String tail}) splitErrorItems(
  String markdown,
) {
  final lead = <String>[];
  final items = <String>[];
  final tail = <String>[];
  var inTail = false;
  var blank = false;
  for (final line in markdown.split('\n')) {
    final match = _listItem.firstMatch(line);
    if (inTail) {
      tail.add(line);
    } else if (match != null) {
      items.add(match[1]!.trim());
      blank = false;
    } else if (line.trim().isEmpty) {
      if (items.isEmpty) {
        lead.add(line);
      } else {
        blank = true;
      }
    } else if (items.isEmpty) {
      lead.add(line);
    } else if (blank && !line.startsWith(' ')) {
      inTail = true;
      tail.add(line);
    } else {
      items[items.length - 1] = '${items.last} ${line.trim()}';
    }
  }
  return (
    lead: lead.join('\n').trim(),
    items: items,
    tail: tail.join('\n').trim(),
  );
}
