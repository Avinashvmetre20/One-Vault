import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../../app/app_scope.dart';
import '../../../../app/routes.dart';
import '../../../../core/widgets/empty_state.dart';
import '../../../../core/widgets/list_tile_card.dart';
import '../../../../app/theme/app_colors.dart';
import '../../../../app/theme/app_dimensions.dart';
import '../../data/planner_models.dart';
import '../../data/planner_service.dart';
import '../../data/reminder_notifications.dart';

mixin PlannerTickReload<T extends StatefulWidget> on State<T> {
  ValueNotifier<int>? _plannerTick;

  @protected
  Future<void> reloadPlannerData();

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final tick = AppScope.of(context).plannerTick;
    if (!identical(_plannerTick, tick)) {
      _plannerTick?.removeListener(_handlePlannerTick);
      _plannerTick = tick;
      _plannerTick!.addListener(_handlePlannerTick);
    }
  }

  void _handlePlannerTick() {
    if (mounted) reloadPlannerData();
  }

  @override
  void dispose() {
    _plannerTick?.removeListener(_handlePlannerTick);
    super.dispose();
  }
}

class PlannerHubScreen extends StatefulWidget {
  const PlannerHubScreen({super.key});

  @override
  State<PlannerHubScreen> createState() => _PlannerHubScreenState();
}

class _PlannerHubScreenState extends State<PlannerHubScreen>
    with PlannerTickReload {
  PlannerSummary _summary = const PlannerSummary();
  bool _loading = false;
  bool _opened = false;
  bool _didRestoreAlarms = false;
  ValueNotifier<int>? _shellIndex;

  PlannerService get _api => AppScope.of(context).planner;

  static const _plannerTab = 3;

  @override
  Future<void> reloadPlannerData() {
    if (!_opened) return Future.value();
    return _load();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final index = AppScope.of(context).shellTabIndex;
    if (!identical(_shellIndex, index)) {
      _shellIndex?.removeListener(_onShellTab);
      _shellIndex = index;
      _shellIndex!.addListener(_onShellTab);
    }
    _onShellTab();
  }

  void _onShellTab() {
    if (!mounted) return;
    if (_shellIndex?.value != _plannerTab) return;
    if (_opened) return;
    _opened = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _load();
    });
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final summary = await _api.summary();
      if (!_didRestoreAlarms) {
        _didRestoreAlarms = true;
        unawaited(ReminderNotifications.instance.restorePending());
      }
      if (!mounted) return;
      setState(() {
        _summary = summary;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loading = false);
    }
  }

  @override
  void dispose() {
    _shellIndex?.removeListener(_onShellTab);
    super.dispose();
  }

  Future<void> _open(String route) async {
    await context.push(route);
    if (mounted) _load();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Planner')),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: AppDimensions.pagePadding,
          children: [
            if (_loading)
              const Padding(
                padding: EdgeInsets.only(bottom: 12),
                child: LinearProgressIndicator(minHeight: 2),
              ),
            if (_summary.tasksToday > 0 ||
                _summary.remindersToday > 0 ||
                _summary.alarmsToday > 0 ||
                _summary.eventsToday > 0)
              Padding(
                padding: const EdgeInsets.only(bottom: 16),
                child: Text(
                  'Today · ${_summary.tasksToday} tasks · ${_summary.alarmsToday} alarms · ${_summary.remindersToday} reminders · ${_summary.eventsToday} events',
                  style: TextStyle(color: AppColors.muted(context)),
                ),
              ),
            ListTileCard(
              icon: Icons.check_circle_outline,
              title: 'Tasks',
              subtitle: '${_summary.tasksOpen} open',
              onTap: () => _open(AppRoutes.tasks),
              margin: AppDimensions.itemSpacing,
            ),
            ListTileCard(
              icon: Icons.sticky_note_2_outlined,
              title: 'Notes',
              subtitle: '${_summary.notesTotal} notes',
              onTap: () => _open(AppRoutes.notes),
              margin: AppDimensions.itemSpacing,
            ),
            ListTileCard(
              icon: Icons.alarm,
              title: 'Alarms',
              subtitle: '${_summary.alarmsUpcoming} set',
              onTap: () => _open(AppRoutes.alarms),
              margin: AppDimensions.itemSpacing,
            ),
            ListTileCard(
              icon: Icons.notifications_outlined,
              title: 'Reminders',
              subtitle: '${_summary.remindersUpcoming} upcoming',
              onTap: () => _open(AppRoutes.reminders),
              margin: AppDimensions.itemSpacing,
            ),
            ListTileCard(
              icon: Icons.calendar_month_outlined,
              title: 'Calendar',
              subtitle: 'Agenda and schedule',
              onTap: () => _open(AppRoutes.calendar),
              margin: AppDimensions.itemSpacing,
            ),
          ],
        ),
      ),
    );
  }
}

class PlannerErrorState extends StatelessWidget {
  const PlannerErrorState({super.key, required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return EmptyState(
      icon: Icons.wifi_off_rounded,
      title: 'Could not load',
      subtitle: message,
      action: FilledButton(onPressed: onRetry, child: const Text('Try again')),
    );
  }
}
