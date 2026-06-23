import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cmpys/app/app.dart';

void main() {
  test('CMPYS app root is constructible', () {
    expect(const App(), isA<Widget>());
    expect(const App(), isA<App>());
  });
}
