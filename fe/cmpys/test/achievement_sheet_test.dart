import 'package:flutter_test/flutter_test.dart';
import 'package:cmpys/features/plan/presentation/achievement_sheet.dart';

void main() {
  test('AI suggestion applies only when user has not typed', () {
    final s = AchievementSheetState(initial: 'metric line');
    s.applySuggestion('AI line');
    expect(s.text, 'AI line');

    s.onUserType('my own words');
    s.applySuggestion('late AI line');
    expect(s.text, 'my own words'); // not overwritten
  });
}
