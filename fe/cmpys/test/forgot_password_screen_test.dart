import 'package:cmpys/features/auth/presentation/forgot_password_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('forgot password validates and confirms recovery', (
    tester,
  ) async {
    await tester.pumpWidget(const MaterialApp(home: ForgotPasswordScreen()));

    expect(find.text('Recover access'), findsOneWidget);

    await tester.tap(find.text('Send Recovery Link'));
    await tester.pump();
    expect(find.text('Enter your account email'), findsOneWidget);

    await tester.enterText(find.byType(TextFormField), 'person@example.com');
    await tester.tap(find.text('Send Recovery Link'));
    await tester.pump();

    expect(find.text('Check your inbox'), findsOneWidget);
    expect(find.text('Send Again'), findsOneWidget);
  });
}
