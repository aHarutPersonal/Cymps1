import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('feature code uses CmpysPageRoute/CmpysSheetRoute, not MaterialPageRoute',
      () {
    final offenders = Directory('lib/features')
        .listSync(recursive: true)
        .whereType<File>()
        .where((f) => f.path.endsWith('.dart'))
        .where((f) => f.readAsStringSync().contains('MaterialPageRoute'))
        .map((f) => f.path)
        .toList();
    expect(offenders, isEmpty,
        reason:
            'Push details with CmpysPageRoute (or CmpysSheetRoute for modal '
            'entry screens) from lib/core/ui/motion/page_transition.dart.');
  });
}
