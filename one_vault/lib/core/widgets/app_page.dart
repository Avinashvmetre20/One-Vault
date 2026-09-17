import 'package:flutter/material.dart';

import '../../app/theme/app_dimensions.dart';
import 'empty_state.dart';

class AppPage extends StatelessWidget {
  const AppPage({
    super.key,
    required this.title,
    required this.children,
    this.actions,
    this.fab,
    this.refresh,
    this.listKey,
    this.padding,
  });

  final String title;
  final List<Widget> children;
  final List<Widget>? actions;
  final Widget? fab;
  final Future<void> Function()? refresh;
  final Key? listKey;
  final EdgeInsetsGeometry? padding;

  @override
  Widget build(BuildContext context) {
    final list = ListView(
      key: listKey,
      padding: padding ??
          (fab == null ? AppDimensions.pagePadding : AppDimensions.pagePaddingFab),
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      children: children,
    );
    return Scaffold(
      appBar: AppBar(title: Text(title), actions: actions),
      floatingActionButton: fab,
      body: refresh == null ? list : RefreshIndicator(onRefresh: refresh!, child: list),
    );
  }
}

class AppDetailPage extends StatelessWidget {
  const AppDetailPage({
    super.key,
    required this.title,
    required this.children,
    this.actions,
  });

  final String title;
  final List<Widget> children;
  final List<Widget>? actions;

  @override
  Widget build(BuildContext context) {
    return AppPage(
      title: title,
      actions: actions,
      padding: AppDimensions.pagePadding,
      children: children,
    );
  }
}

class AppMissingPage extends StatelessWidget {
  const AppMissingPage({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  final IconData icon;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(),
      body: EmptyState(icon: icon, title: title, subtitle: subtitle),
    );
  }
}
