import 'package:flutter_test/flutter_test.dart';
import 'package:cmpys/features/plan/models/plan_models.dart';

void main() {
  test('ToggleResult parses planComplete and missionTasksRemaining', () {
    final r = ToggleResult.fromJson({
      'completed': true,
      'planComplete': true,
      'missionTasksRemaining': 0,
    });
    expect(r.completed, true);
    expect(r.planComplete, true);
    expect(r.missionTasksRemaining, 0);
  });

  test('ToggleResult defaults planComplete to false', () {
    final r = ToggleResult.fromJson({'completed': false});
    expect(r.planComplete, false);
    expect(r.missionTasksRemaining, isNull);
  });
}
