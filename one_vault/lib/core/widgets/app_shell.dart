import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'floating_tab_bar.dart';

class AppShell extends StatelessWidget {
  const AppShell({super.key, required this.navigationShell});

  final StatefulNavigationShell navigationShell;

  static const _barClearance = 90.0;

  static const _tabs = [
    FloatingTabItem(
      icon: Icons.home_outlined,
      activeIcon: Icons.home_rounded,
      label: 'Home',
    ),
    FloatingTabItem(
      icon: Icons.shield_outlined,
      activeIcon: Icons.shield_rounded,
      label: 'Vault',
    ),
    FloatingTabItem(
      icon: Icons.account_balance_wallet_outlined,
      activeIcon: Icons.account_balance_wallet_rounded,
      label: 'Money',
    ),
    FloatingTabItem(
      icon: Icons.check_circle_outline,
      activeIcon: Icons.check_circle_rounded,
      label: 'Planner',
    ),
    FloatingTabItem(
      icon: Icons.more_horiz_rounded,
      activeIcon: Icons.more_horiz_rounded,
      label: 'More',
    ),
  ];

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);

    return Scaffold(
      extendBody: true,
      body: MediaQuery(
        data: media.copyWith(
          padding: media.padding.copyWith(
            bottom: media.padding.bottom + _barClearance,
          ),
        ),
        child: navigationShell,
      ),
      bottomNavigationBar: Material(
        color: Colors.transparent,
        elevation: 0,
        child: FloatingTabBar(
          currentIndex: navigationShell.currentIndex,
          items: _tabs,
          onTap: (index) {
            navigationShell.goBranch(
              index,
              initialLocation: index == navigationShell.currentIndex,
            );
          },
        ),
      ),
    );
  }
}
