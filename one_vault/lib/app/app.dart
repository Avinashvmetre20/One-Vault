import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../features/planner/data/planner_models.dart';
import '../features/planner/data/reminder_notifications.dart';
import 'app_state.dart';
import 'app_scope.dart';
import 'router.dart';
import 'routes.dart';
import 'theme/app_theme.dart';

class MyApp extends StatefulWidget {
  const MyApp({super.key, this.appState});

  final AppState? appState;

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> with WidgetsBindingObserver {
  late final AppState _appState;
  late final GoRouter _router;
  int? _pendingAlarmId;
  bool _didRestoreAlarms = false;

  @override
  void initState() {
    super.initState();
    _appState = widget.appState ?? AppState();
    _router = createRouter(_appState);
    _bindAlarms();
    _appState.addListener(_onAppStateChanged);
    WidgetsBinding.instance.addObserver(this);
    if (_appState.restoreOnStart) {
      unawaited(_appState.restoreSession());
    } else {
      _onAppStateChanged();
    }
  }

  void _bindAlarms() {
    ReminderNotifications.instance.attach(
      actions: ReminderAlarmActions(
        loadPending: () async {
          final items = <PlannerReminder>[];
          var offset = 0;
          while (true) {
            final page = await _appState.planner.reminders(
              scope: 'upcoming',
              limit: 100,
              offset: offset,
            );
            items.addAll(page.items);
            offset += page.items.length;
            if (page.items.length < 100 || items.length >= page.total) break;
          }
          return items;
        },
        advanceRecurring: (id) => _appState.planner.completeReminder(id),
        snooze: (id, minutes) => _appState.planner.snoozeReminder(id, minutes: minutes),
        dismiss: (id) => _appState.planner.completeReminder(id),
      ),
      onTriggered: _openTriggered,
    );
  }

  void _onAppStateChanged() {
    if (!_appState.isReady || !_appState.isLoggedIn) {
      if (_didRestoreAlarms) {
        unawaited(ReminderNotifications.instance.cancelAllManaged());
      }
      _didRestoreAlarms = false;
      return;
    }
    if (!_didRestoreAlarms) {
      _didRestoreAlarms = true;
      unawaited(ReminderNotifications.instance.handlePendingLaunch());
    }
    _openPendingAlarmIfReady();
  }

  void _openTriggered(int reminderId) {
    unawaited(_routeTriggered(reminderId));
  }

  Future<void> _routeTriggered(int reminderId) async {
    if (!_appState.isReady || !_appState.isLoggedIn) {
      _pendingAlarmId = reminderId;
      return;
    }
    try {
      final item = await _appState.planner.reminder(reminderId);
      if (!item.isAlarm) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          _router.go(AppRoutes.reminderDetail(reminderId));
        });
        return;
      }
    } catch (_) {}
    _pendingAlarmId = reminderId;
    _openPendingAlarmIfReady();
  }

  void _openPendingAlarmIfReady() {
    if (!_appState.isReady || !_appState.isLoggedIn) return;
    final id = _pendingAlarmId;
    if (id == null) return;
    final path = _router.routeInformationProvider.value.uri.path;
    if (path == AppRoutes.reminderRinging(id)) {
      _pendingAlarmId = null;
      return;
    }
    _pendingAlarmId = null;
    ReminderNotifications.instance.markRinging(id);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _router.go(AppRoutes.reminderRinging(id));
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden) {
      _appState.vault.onBackgrounded();
    } else if (state == AppLifecycleState.resumed) {
      _appState.vault.onResumed();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _appState.removeListener(_onAppStateChanged);
    _router.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AppScope(
      notifier: _appState,
      child: ListenableBuilder(
        listenable: _appState,
        builder: (context, _) {
          return MaterialApp.router(
            title: 'OneVault',
            debugShowCheckedModeBanner: false,
            theme: AppTheme.light(),
            darkTheme: AppTheme.dark(),
            themeMode: _appState.themeMode,
            routerConfig: _router,
          );
        },
      ),
    );
  }
}
