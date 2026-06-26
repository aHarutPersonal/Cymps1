import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('app source does not keep legacy visual design copy', () {
    // Genuinely-legacy copy from a superseded idol-selection UI. Note: generic
    // words like "trajectory" and "north star" are NOT banned — they're part of
    // the referenced CMPYS design's own copy ("Changed your trajectory" impact
    // label, "Your north star" goal step).
    final bannedPatterns = <RegExp>[
      RegExp(r'Target_Selection'),
      RegExp(r'Analyze Trajectory', caseSensitive: false),
      RegExp(r'Search titan', caseSensitive: false),
      RegExp(r'No stars found', caseSensitive: false),
      RegExp(r'Choose Idol', caseSensitive: false),
      RegExp(r'Select an idol', caseSensitive: false),
      RegExp(r'No idol selected', caseSensitive: false),
      RegExp(r"Don't see your idol", caseSensitive: false),
      RegExp(r'perfect idol', caseSensitive: false),
      RegExp(r'figma_refs', caseSensitive: false),
      RegExp(r'Your selected mentor is no longer available'),
      RegExp(r'Pick a benchmark', caseSensitive: false),
    ];

    final offenders = <String>[];
    for (final entity in Directory('lib').listSync(recursive: true)) {
      if (entity is! File || !entity.path.endsWith('.dart')) continue;
      if (entity.path.endsWith('.freezed.dart') ||
          entity.path.endsWith('.g.dart')) {
        continue;
      }
      final content = entity.readAsStringSync();
      for (final pattern in bannedPatterns) {
        if (pattern.hasMatch(content)) {
          offenders.add('${entity.path}: ${pattern.pattern}');
        }
      }
    }

    final pubspec = File('pubspec.yaml').readAsStringSync();
    for (final pattern in bannedPatterns) {
      if (pattern.hasMatch(pubspec)) {
        offenders.add('pubspec.yaml: ${pattern.pattern}');
      }
    }

    expect(offenders, isEmpty);
  });
}
