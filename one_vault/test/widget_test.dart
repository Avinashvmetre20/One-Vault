import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:one_vault/main.dart';

void main() {
  testWidgets('Home dashboard renders credentials content', (tester) async {
    await tester.pumpWidget(const MyApp());

    expect(find.text('Avinash'), findsOneWidget);
    expect(find.text('OneVault'), findsOneWidget);
    expect(find.text('Quick Actions'), findsOneWidget);
    expect(find.text('My Profile'), findsOneWidget);
    expect(find.text('Passwords'), findsOneWidget);
    expect(find.text('Documents'), findsOneWidget);
    expect(find.text('Home'), findsOneWidget);
    expect(find.text('Profile'), findsOneWidget);
    expect(find.text('Settings'), findsNWidgets(2));
  });

  testWidgets('Action grid does not overflow on medium widths', (tester) async {
    tester.view.physicalSize = const Size(450, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(const MyApp());

    expect(tester.takeException(), isNull);
    expect(find.text('My Profile'), findsOneWidget);
  });

  testWidgets('Bottom navigation switches to Profile', (tester) async {
    await tester.pumpWidget(const MyApp());

    await tester.tap(find.text('Profile'));
    await tester.pumpAndSettle();

    expect(
      find.text('Your personal details will live here.'),
      findsOneWidget,
    );
  });
}
