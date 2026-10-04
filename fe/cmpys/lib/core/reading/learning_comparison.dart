/// A deliberately narrow reader format, not a general ASCII diagram parser.
/// The semantic text is shared by rendering, selection and speech offsets.
class ComparisonTextRange {
  const ComparisonTextRange(this.start, this.end);
  final int start;
  final int end;
}

class LearningComparisonSection {
  const LearningComparisonSection(this.heading, this.items);
  final ComparisonTextRange heading;
  final List<ComparisonTextRange> items;
}

class LearningComparison {
  const LearningComparison(this.text, this.sections, this.separator);
  final String text;
  final List<LearningComparisonSection> sections;
  final ComparisonTextRange separator;

  static LearningComparison? parse(String source, {String language = ''}) {
    if (!const ['', 'text', 'plaintext', 'comparison'].contains(language)) {
      return null;
    }
    final lines = source.trim().split('\n').map((line) => line.trim()).toList();
    final border = RegExp(r'^\+[=-]{3,}\+$');
    final groups = <List<String>>[];
    String? separator;
    if (lines.isNotEmpty && border.hasMatch(lines.first)) {
      var index = 0;
      while (index < lines.length) {
        if (!border.hasMatch(lines[index++])) return null;
        final group = <String>[];
        while (index < lines.length && !border.hasMatch(lines[index])) {
          final line = lines[index++];
          if (!line.startsWith('|') || !line.endsWith('|')) return null;
          final body = line.substring(1, line.length - 1).trim();
          // Multiple columns, operators and executable code are not this format.
          if (body.contains('|')) return null;
          if (body.isNotEmpty) group.add(body);
        }
        if (index == lines.length) return null;
        index++;
        groups.add(group);
        while (index < lines.length && lines[index].isEmpty) {
          index++;
        }
        if (groups.length == 1) {
          if (index == lines.length ||
              !RegExp(
                r'^(vs\.?|versus)$',
                caseSensitive: false,
              ).hasMatch(lines[index])) {
            return null;
          }
          separator = lines[index++];
          while (index < lines.length && lines[index].isEmpty) {
            index++;
          }
        } else if (index != lines.length) {
          return null;
        }
      }
    } else if (language == 'comparison') {
      final split = lines.indexWhere(
        (line) =>
            RegExp(r'^(vs\.?|versus)$', caseSensitive: false).hasMatch(line),
      );
      if (split < 1) return null;
      separator = lines[split];
      groups.add(lines.take(split).where((line) => line.isNotEmpty).toList());
      groups.add(
        lines.skip(split + 1).where((line) => line.isNotEmpty).toList(),
      );
    } else {
      return null;
    }
    if (groups.length != 2 || separator == null) return null;
    final parsed = <(String, List<String>)>[];
    for (final group in groups) {
      if (group.length < 3 ||
          group.first.length > 100 ||
          !RegExp(r'[A-Za-z]').hasMatch(group.first)) {
        return null;
      }
      final items = <String>[];
      for (final line in group.skip(1)) {
        final match = RegExp(
          r'^(?:(\d+)\.[ \t]+|[-•][ \t]+)(.+)$',
        ).firstMatch(line);
        if (match != null) {
          if (match.group(1) != null &&
              int.tryParse(match.group(1)!) != items.length + 1) {
            return null;
          }
          items.add(match.group(1) == null ? match.group(2)! : line);
        } else if (items.isNotEmpty) {
          items[items.length - 1] += ' $line';
        } else {
          return null;
        }
      }
      if (items.length < 2 || items.length > 12) return null;
      if (group.any((line) => RegExp(r'[{};]|=>|</?\w').hasMatch(line))) {
        return null;
      }
      parsed.add((group.first, items));
    }
    final buffer = StringBuffer();
    ComparisonTextRange append(String value) {
      if (buffer.isNotEmpty) buffer.write('\n');
      final start = buffer.length;
      buffer.write(value);
      return ComparisonTextRange(start, buffer.length);
    }

    final sections = <LearningComparisonSection>[];
    ComparisonTextRange? separatorRange;
    for (final group in parsed) {
      if (sections.isNotEmpty) separatorRange = append(separator);
      final heading = append(group.$1);
      sections.add(
        LearningComparisonSection(heading, [
          for (final item in group.$2) append(item),
        ]),
      );
    }
    return LearningComparison(buffer.toString(), sections, separatorRange!);
  }
}
