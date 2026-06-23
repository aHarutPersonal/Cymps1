import 'package:cmpys/features/profile/presentation/premium_paywall_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('premium paywall renders plan options', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: PremiumPaywallScreen()));

    expect(find.text('CMPYS Pro'), findsOneWidget);
    expect(find.text('Yearly Mastery'), findsOneWidget);
    expect(find.text('Monthly Pursuit'), findsOneWidget);
    expect(find.text('Unlock The Blueprint'), findsOneWidget);
  });
}
