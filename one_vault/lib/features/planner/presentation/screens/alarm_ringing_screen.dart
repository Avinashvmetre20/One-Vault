import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../../app/app_scope.dart';
import '../../../../app/routes.dart';
import '../../../../app/theme/app_colors.dart';
import '../../../../app/theme/app_dimensions.dart';
import '../../../../shared/helpers/formatters.dart';
import '../../../../shared/helpers/snack.dart';
import '../../data/planner_models.dart';
import '../../data/planner_service.dart';
import '../../data/reminder_notifications.dart';

Future<int?> showReminderSnoozeSheet(BuildContext context) {
  return showModalBottomSheet<int>(
    context: context,
    builder: (context) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: const [
          _SnoozeOption(minutes: 5, label: '5 minutes'),
          _SnoozeOption(minutes: 10, label: '10 minutes'),
          _SnoozeOption(minutes: 30, label: '30 minutes'),
          _SnoozeOption(minutes: 60, label: '1 hour'),
        ],
      ),
    ),
  );
}

class _SnoozeOption extends StatelessWidget {
  const _SnoozeOption({required this.minutes, required this.label});

  final int minutes;
  final String label;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      title: Text(label),
      onTap: () => Navigator.pop(context, minutes),
    );
  }
}

class AlarmRingingScreen extends StatefulWidget {
  const AlarmRingingScreen({super.key, required this.id});

  final int id;

  @override
  State<AlarmRingingScreen> createState() => _AlarmRingingScreenState();
}

class _AlarmRingingScreenState extends State<AlarmRingingScreen> {
  PlannerReminder? _item;
  bool _loading = true;
  bool _busy = false;
  String? _error;

  PlannerService get _api => AppScope.of(context).planner;

  @override
  void initState() {
    super.initState();
    ReminderNotifications.instance.markRinging(widget.id);
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  @override
  void dispose() {
    ReminderNotifications.instance.clearRinging(widget.id);
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final item = await _api.reminder(widget.id);
      if (!mounted) return;
      setState(() {
        _item = item;
        _loading = false;
        _error = null;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error.toString();
        _loading = false;
      });
    }
  }

  Future<void> _snooze() async {
    final minutes = await showReminderSnoozeSheet(context);
    if (minutes == null || !mounted) return;
    await _finish(() async {
      await ReminderNotifications.instance.stopRinging(widget.id);
      final updated = await _api.snoozeReminder(widget.id, minutes: minutes);
      await ReminderNotifications.instance.sync(updated);
    });
  }

  Future<void> _dismiss() async {
    await _finish(() async {
      await ReminderNotifications.instance.stopRinging(widget.id);
      final updated = await _api.completeReminder(widget.id);
      await ReminderNotifications.instance.sync(updated);
    });
  }

  Future<void> _finish(Future<void> Function() action) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await action();
      if (!mounted) return;
      if (context.canPop()) {
        context.pop();
      } else {
        context.go(_item?.isAlarm == true ? AppRoutes.alarms : AppRoutes.reminders);
      }
    } catch (error) {
      if (!mounted) return;
      setState(() => _busy = false);
      showAppSnack(context, error.toString());
    }
  }

  @override
  Widget build(BuildContext context) {
    final item = _item;
    return PopScope(
      canPop: false,
      child: Scaffold(
        backgroundColor: AppColors.scaffold,
        body: SafeArea(
          child: _loading
              ? const Center(child: CircularProgressIndicator())
              : _error != null || item == null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(_error ?? 'Reminder not found'),
                        const SizedBox(height: 16),
                        FilledButton(
                          onPressed: () => context.go(AppRoutes.planner),
                          child: const Text('Close'),
                        ),
                      ],
                    ),
                  ),
                )
              : Padding(
                  padding: const EdgeInsets.fromLTRB(24, 32, 24, 24),
                  child: Column(
                    children: [
                      const Spacer(),
                      Container(
                        width: 96,
                        height: 96,
                        decoration: BoxDecoration(
                          color: AppColors.iconWash,
                          borderRadius: BorderRadius.circular(AppDimensions.radiusXl),
                        ),
                        child: Icon(
                          item.isAlarm ? Icons.alarm : Icons.notifications_active_rounded,
                          size: 48,
                          color: AppColors.primary,
                        ),
                      ),
                      const SizedBox(height: 28),
                      Text(
                        item.title,
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        Formatters.time(item.when),
                        style: Theme.of(context).textTheme.displaySmall?.copyWith(
                          fontWeight: FontWeight.w700,
                          color: AppColors.primary,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        Formatters.date(item.when),
                        style: TextStyle(color: Colors.grey.shade600, fontSize: 16),
                      ),
                      if (item.description.isNotEmpty) ...[
                        const SizedBox(height: 16),
                        Text(
                          item.description,
                          textAlign: TextAlign.center,
                          style: TextStyle(color: Colors.grey.shade700, height: 1.4),
                        ),
                      ],
                      if (item.taskTitle != null && item.taskTitle!.isNotEmpty) ...[
                        const SizedBox(height: 18),
                        Text(
                          'Planner task: ${item.taskTitle}',
                          textAlign: TextAlign.center,
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                        if (item.taskId != null)
                          TextButton(
                            onPressed: () => context.push(AppRoutes.taskDetail(item.taskId!)),
                            child: const Text('Open task'),
                          ),
                      ],
                      const Spacer(),
                      SizedBox(
                        width: double.infinity,
                        child: FilledButton(
                          onPressed: _busy ? null : _snooze,
                          child: const Padding(
                            padding: EdgeInsets.symmetric(vertical: 14),
                            child: Text('Snooze'),
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      SizedBox(
                        width: double.infinity,
                        child: OutlinedButton(
                          onPressed: _busy ? null : _dismiss,
                          child: const Padding(
                            padding: EdgeInsets.symmetric(vertical: 14),
                            child: Text('Dismiss'),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
        ),
      ),
    );
  }
}
