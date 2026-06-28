import 'package:flutter_test/flutter_test.dart';
import 'package:cmpys/features/plan/presentation/cycle_completion_screen.dart';

class _FakeRepo implements CycleCompletionRepo {
  @override
  Future<({String narrative, String? capstoneTitle})> fetchCycleSummary(String id) async =>
      (narrative: 'You did great', capstoneTitle: 'Shipped MVP');
  @override
  Future<String> generateNext(String id) async => 'job-123';
}

void main() {
  test('startNextCycle forwards the new job id', () async {
    String? captured;
    final p = CycleCompletionPresenter(
      planId: 'p1', repo: _FakeRepo(), onJobId: (j) => captured = j);
    await p.start();
    expect(p.narrative, 'You did great');
    final job = await p.startNextCycle();
    expect(job, 'job-123');
    expect(captured, 'job-123');
  });
}
