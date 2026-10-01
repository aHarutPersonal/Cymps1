import 'package:cmpys/features/auth/presentation/forgot_password_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('unavailable recovery never claims to send an email', (
    tester,
  ) async {
    await tester.pumpWidget(const MaterialApp(home: ForgotPasswordScreen()));
    expect(find.text('Forgot your password?'), findsOneWidget);
    expect(
      find.text('Password reset by email is not available yet.'),
      findsOneWidget,
    );
    expect(find.byType(TextFormField), findsNothing);
    expect(find.text('Check your inbox'), findsNothing);
    expect(find.text('Back to sign in'), findsOneWidget);
  });
}
