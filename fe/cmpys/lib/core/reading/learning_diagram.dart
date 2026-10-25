import 'learning_comparison.dart';

class LearningDiagramLine {
  const LearningDiagramLine(
    this.parts, {
    this.branch = false,
    this.columns = false,
    this.bidirectional = false,
    this.parentLineIndex,
    this.directed = false,
    this.parentPartIndex = 0,
    this.entryPartIndex = 0,
    this.reverseLinks = const [],
  });
  final List<ComparisonTextRange> parts;
  final bool branch;
  final bool columns;
  final bool bidirectional;
  final int? parentLineIndex;
  final bool directed;
  final int parentPartIndex;
  final int entryPartIndex;

  /// Direction of each horizontal link: -1 left, 0 bidirectional, 1 right.
  final List<int> reverseLinks;
}

/// Conservative recognition of framed teaching notes and bracket/arrow flows.
/// No evaluation, inferred facts, or reordering of columns is performed.
class LearningDiagram {
  const LearningDiagram(this.text, this.heading, this.lines);
  final String text;
  final ComparisonTextRange? heading;
  final List<LearningDiagramLine> lines;

  static LearningDiagram? parse(String source, {String language = ''}) {
    if (!const ['', 'text', 'plaintext', 'diagram'].contains(language)) {
      return null;
    }
    var raw = source.trim().split('\n');
    if (raw.length < 3 || raw.length > 80) return null;
    final border = RegExp(r'^\+[=-]{3,}\+$');
    final boxed =
        border.hasMatch(raw.first.trim()) && border.hasMatch(raw.last.trim());
    String? title;
    if (boxed) {
      final rows = <String>[];
      for (final row in raw.skip(1).take(raw.length - 2)) {
        final value = row.trim();
        if (!value.startsWith('|') || !value.endsWith('|')) return null;
        rows.add(value.substring(1, value.length - 1));
      }
      if (rows.isEmpty ||
          !RegExp(
            r'^[A-Z0-9][A-Z0-9 &:/().%\-]{3,100}$',
          ).hasMatch(rows.first.trim())) {
        return null;
      }
      title = rows.first.trim();
      raw = rows.skip(1).toList();
    } else {
      // Require actual bracketed nodes and explicit diagram connectors.
      if (!source.contains('[') || !RegExp(r'─[─►]|[│├└▼]').hasMatch(source)) {
        return null;
      }
    }
    if (raw.any(
      (line) => RegExp(
        r'[{};]|=>\s*\{|\b(?:def|class|import)\s|console\.|print\(',
      ).hasMatch(line),
    )) {
      return null;
    }
    final structural = RegExp(r'^[\s+|\-=─━│▼►▶→←<>├└┌┐┘┤┬┴┼]+$');
    final arrows = RegExp(r'<[-=]+>|<[-=]+|[-=]+>|[─━]+[►▶→]|[←→►▶]');
    final matrix = raw.any(
      (line) => RegExp(r'\[[^\]]+\]\s{2,}\[[^\]]+\]').hasMatch(line),
    );
    final buffer = StringBuffer();
    ComparisonTextRange append(String value) {
      if (buffer.isNotEmpty) buffer.write('\n');
      final start = buffer.length;
      buffer.write(value.replaceAll(RegExp(r'\s+'), ' ').trim());
      return ComparisonTextRange(start, buffer.length);
    }

    final heading = title == null ? null : append(title);
    final lines = <LearningDiagramLine>[];
    var pendingConnection = false;
    var directed = false;
    int? rootLine;
    int? connectionColumn;
    final sourceRanges = <List<ComparisonTextRange>>[];
    int? partAt(int row, int column) {
      final ranges = sourceRanges[row];
      if (ranges.length == 1) return 0;
      for (var i = 0; i < ranges.length; i++) {
        if (column >= ranges[i].start && column < ranges[i].end) return i;
      }
      return null; // A connector in a gap has no unambiguous endpoint.
    }

    for (final rawLine in raw) {
      var line = rawLine.trim();
      if (line.isEmpty) continue;
      if (structural.hasMatch(line)) {
        if (RegExp(r'^[│|▼]$').hasMatch(line)) {
          final column = rawLine.indexOf(line);
          if (connectionColumn != null && connectionColumn != column) {
            return null;
          }
          connectionColumn = column;
          pendingConnection = true;
          directed |= line == '▼';
        } else if (!RegExp(r'^[-=+]+$').hasMatch(line)) {
          return null;
        }
        continue;
      }
      final branch = RegExp(r'^[├└|│][─━=\-]+[►▶→>]').hasMatch(line);
      final branchColumn = rawLine.indexOf(RegExp(r'[├└|│]'));
      var contentStart = rawLine.indexOf(RegExp(r'\S'));
      if (branch || line.startsWith('|') || line.startsWith('│')) {
        if (!branch) return null;
        final prefix = RegExp(r'^[|│├└─━=\-\s]+[►▶→>]\s*').firstMatch(line)!;
        contentStart += prefix.end;
        line = line.substring(prefix.end);
      }
      final columns =
          matrix &&
          !arrows.hasMatch(line) &&
          RegExp(r'\S\s{2,}\S').hasMatch(line);
      final separators = (columns ? RegExp(r'\s{2,}') : arrows)
          .allMatches(line)
          .toList();
      final spans = <ComparisonTextRange>[];
      var start = 0;
      for (final end in [...separators.map((m) => m.start), line.length]) {
        spans.add(
          ComparisonTextRange(contentStart + start, contentStart + end),
        );
        if (end < line.length) start = separators[spans.length - 1].end;
      }
      var parts = (columns ? line.split(RegExp(r'\s{2,}')) : line.split(arrows))
          .map((part) => part.replaceAll(RegExp(r'[\[\]]'), '').trim())
          .toList();
      if (parts.isEmpty || parts.length > 4 || parts.any((p) => p.isEmpty)) {
        return null;
      }
      // Unsupported pipes/branch fragments stay in the original code fallback.
      if (parts.any((part) => RegExp(r'[|│├└]').hasMatch(part))) return null;
      if ((branch && rootLine == null) ||
          (pendingConnection && lines.isEmpty)) {
        return null;
      }
      final parent = branch || pendingConnection ? rootLine : null;
      sourceRanges.add(spans);
      final column = branch ? branchColumn : connectionColumn;
      final parentPart = parent == null ? 0 : partAt(parent, column!);
      final entryPart = parent == null || branch
          ? 0
          : partAt(lines.length, column!);
      if (parentPart == null || entryPart == null) return null;
      lines.add(
        LearningDiagramLine(
          [for (final part in parts) append(part)],
          branch: branch,
          columns: columns,
          bidirectional: line.contains('<--'),
          parentLineIndex: parent,
          directed: directed || branch,
          parentPartIndex: parentPart,
          entryPartIndex: entryPart,
          reverseLinks: columns
              ? const []
              : [
                  for (final arrow in separators)
                    arrow[0]!.startsWith('<')
                        ? (arrow[0]!.endsWith('>') ? 0 : -1)
                        : arrow[0] == '←'
                        ? -1
                        : 1,
                ],
        ),
      );
      if (!branch) rootLine = lines.length - 1;
      pendingConnection = false;
      directed = false;
      connectionColumn = null;
    }
    if (pendingConnection) return null;
    if (lines.length < 2 || lines.length > 40) return null;
    return LearningDiagram(buffer.toString(), heading, lines);
  }
}
