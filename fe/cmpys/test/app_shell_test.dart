import 'package:cmpys/core/ui/app_shell.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('app shell uses the canonical five-tab IA', () {
    expect(
      appShellDestinations.map((destination) => destination.label).toList(),
      ['Today', 'Plan', 'Chat', 'Compare', 'You'],
    );
  });

  test('floating navigation collapses before it can overflow', () {
    expect(AppShell.useIconOnlyNavigation(320, 14), isTrue);
    expect(AppShell.useIconOnlyNavigation(390, 18.2), isTrue);
    expect(AppShell.useIconOnlyNavigation(390, 14), isFalse);
  });

  testWidgets('branch content drops nav clearance while keyboard is open',
      (tester) async {
    double? clearance;
    await tester.pumpWidget(MaterialApp(
      home: MediaQuery(
        data: const MediaQueryData(viewInsets: EdgeInsets.only(bottom: 300)),
        child: Builder(builder: (context) {
          clearance = AppShell.bottomNavClearance(context, extra: 2);
          return const SizedBox.shrink();
        }),
      ),
    ));

    expect(clearance, 14);
  });
}
