import 'package:cmpys/core/ui/app_shell.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('app shell uses the canonical five-tab IA', () {
    expect(
      appShellDestinations.map((destination) => destination.label).toList(),
      ['Today', 'Plan', 'Chat', 'Compare', 'You'],
    );
  });
}
