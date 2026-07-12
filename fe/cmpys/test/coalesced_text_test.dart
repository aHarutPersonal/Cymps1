import 'package:cmpys/core/network/coalesced_text.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('publishes first chunk immediately and coalesces later chunks', (
    tester,
  ) async {
    final updates = <String>[];
    final text = CoalescedText(onUpdate: updates.add);

    text.add('a');
    text.add('b');
    text.add('c');
    expect(updates, ['a']);

    await tester.pump(const Duration(milliseconds: 59));
    expect(updates, ['a']);
    await tester.pump(const Duration(milliseconds: 1));
    expect(updates, ['a', 'abc']);

    text.add('d');
    expect(text.close(), 'abcd');
    expect(updates, ['a', 'abc', 'abcd']);
    await tester.pump(const Duration(seconds: 1));
    expect(updates, ['a', 'abc', 'abcd']);
  });

  test('a burst keeps exact text with bounded publish work', () {
    final updates = <String>[];
    final text = CoalescedText(onUpdate: updates.add);

    for (var i = 0; i < 1000; i++) {
      text.add('x');
    }

    final finalValue = text.close();
    expect(finalValue, List.filled(1000, 'x').join());
    expect(updates.last, finalValue);
    expect(updates.length, 2);
  });
}
