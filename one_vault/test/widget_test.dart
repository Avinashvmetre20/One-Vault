import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:one_vault/app/app.dart';
import 'package:one_vault/app/app_state.dart';

Widget _app({bool loggedIn = true}) {
  return MyApp(
    appState: loggedIn
        ? AppState.authenticated()
        : AppState(restoreOnStart: false),
  );
}

void main() {
  testWidgets('Login screen is shown when logged out', (tester) async {
    tester.view.physicalSize = const Size(400, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(_app(loggedIn: false));
    await tester.pumpAndSettle();

    expect(find.text('Welcome back'), findsOneWidget);
    expect(find.text('Log in'), findsOneWidget);
    expect(find.text('Register'), findsOneWidget);
  });

  testWidgets('Register screen opens from login', (tester) async {
    tester.view.physicalSize = const Size(400, 1100);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(_app(loggedIn: false));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Register'));
    await tester.pumpAndSettle();

    expect(find.text('Create account'), findsWidgets);
    expect(find.text('Full name'), findsOneWidget);
    expect(find.text('Confirm password'), findsOneWidget);
  });

  testWidgets('Home dashboard renders V1 content', (tester) async {
    tester.view.physicalSize = const Size(400, 1400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(_app());
    await tester.pumpAndSettle();

    expect(find.text('Avinash'), findsOneWidget);
    expect(find.text('OneVault'), findsOneWidget);
    expect(find.text('Quick Actions'), findsOneWidget);
    expect(find.text('My Profile'), findsOneWidget);
    expect(find.text('Passwords'), findsOneWidget);
    expect(find.text('Documents'), findsOneWidget);
    expect(find.text('This month'), findsOneWidget);
    expect(find.byTooltip('Home'), findsOneWidget);
    expect(find.byTooltip('Vault'), findsOneWidget);
    expect(find.byTooltip('Money'), findsOneWidget);
    expect(find.byTooltip('Planner'), findsOneWidget);
    expect(find.byTooltip('More'), findsOneWidget);
  });

  testWidgets('Action grid does not overflow on medium widths', (tester) async {
    tester.view.physicalSize = const Size(450, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(_app());
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text('My Profile'), findsOneWidget);
  });

  testWidgets('Bottom navigation switches to More', (tester) async {
    await tester.pumpWidget(_app());
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('More'));
    await tester.pumpAndSettle();

    expect(find.text('Security'), findsOneWidget);
    expect(find.text('Settings'), findsWidgets);
    expect(find.text('Log out'), findsOneWidget);
  });

  testWidgets('Money and Planner tabs show expected hubs', (tester) async {
    await tester.pumpWidget(_app());
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Money'));
    await tester.pumpAndSettle();
    expect(find.text('HDFC Bank'), findsOneWidget);
    expect(find.text('Accounts'), findsOneWidget);

    await tester.tap(find.byTooltip('Planner'));
    await tester.pumpAndSettle();
    expect(find.text('Tasks'), findsOneWidget);
    expect(find.text('Notes'), findsOneWidget);
    expect(find.text('Reminders'), findsOneWidget);
  });

  testWidgets('Vault tab opens password list with dummy data', (tester) async {
    await tester.pumpWidget(_app());
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Vault'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Passwords'));
    await tester.pumpAndSettle();

    expect(find.text('HDFC NetBanking'), findsOneWidget);
    await tester.drag(find.byKey(const Key('password-list')), const Offset(0, -500));
    await tester.pumpAndSettle();
    expect(find.text('Gmail'), findsOneWidget);
  });
}
