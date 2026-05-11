import 'package:flutter_test/flutter_test.dart';
import 'package:cmpys/features/intake/models/intake_models.dart';

void main() {
  test('achievement intake questions expose chat display labels', () {
    const question = IntakeQuestion(
      id: 'achievement_1',
      title: 'Proof of Progress',
      prompt: 'Tell me about a recent achievement you are proud of.',
      type: 'multiline',
      category: 'career',
      isRequired: true,
    );

    expect(question.chatEyebrow, 'CAREER');
    expect(
      question.chatPrompt,
      'Tell me about a recent achievement you are proud of.',
    );
    expect(question.answerHint, 'Share the situation, action, and result...');
  });
}
