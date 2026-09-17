import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../../app/app_scope.dart';
import '../../../../app/routes.dart';
import '../../../../core/widgets/empty_state.dart';
import '../../../../core/widgets/form_page.dart';
import '../../../../core/widgets/app_fields.dart';
import '../../../../core/widgets/list_tile_card.dart';
import '../../../../core/widgets/shell_fab.dart';
import '../../../../shared/helpers/formatters.dart';
import '../../../../shared/helpers/snack.dart';
import '../../data/planner_models.dart';
import '../../data/planner_service.dart';
import '../../data/reminder_notifications.dart';
import 'planner_screens.dart';
import 'reminder_screens.dart';

DateTime nextAlarmDateTime(TimeOfDay time, {DateTime? from}) {
  final now = from ?? DateTime.now();
  var at = DateTime(now.year, now.month, now.day, time.hour, time.minute);
  if (!at.isAfter(now.add(const Duration(seconds: 5)))) {
    at = at.add(const Duration(days: 1));
  }
  return at;
}

class AlarmListScreen extends StatefulWidget {
  const AlarmListScreen({super.key});

  @override
  State<AlarmListScreen> createState() => _AlarmListScreenState();
}

class _AlarmListScreenState extends State<AlarmListScreen> with PlannerTickReload {
  bool _loading = true;
  String? _error;
  List<PlannerReminder> _items = [];

  PlannerService get _api => AppScope.of(context).planner;

  @override
  Future<void> reloadPlannerData() => _load(silent: true);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load({bool silent = false}) async {
    if (!silent || _items.isEmpty) {
      setState(() {
        _loading = _items.isEmpty;
        _error = null;
      });
    }
    try {
      final page = await _api.reminders(scope: 'upcoming', kind: 'alarm');
      if (!mounted) return;
      setState(() {
        _items = page.items;
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

  Future<void> _addAlarm() async {
    await context.push(AppRoutes.alarmNew);
    if (mounted) _load();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Alarms'),
        actions: [
          IconButton(
            tooltip: 'Add alarm',
            onPressed: _addAlarm,
            icon: const Icon(Icons.add_rounded),
          ),
        ],
      ),
      floatingActionButton: ShellFab(
        heroTag: 'fab-alarms',
        tooltip: 'Add alarm',
        onPressed: _addAlarm,
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 160),
          children: [
            Text(
              'Wake-up alarms keep ringing until you snooze or dismiss.',
              style: TextStyle(color: Colors.grey.shade600),
            ),
            const SizedBox(height: 16),
            if (_loading)
              const Center(
                child: Padding(
                  padding: EdgeInsets.all(24),
                  child: CircularProgressIndicator(),
                ),
              )
            else if (_error != null)
              PlannerErrorState(message: _error!, onRetry: _load)
            else if (_items.isEmpty)
              EmptyState(
                icon: Icons.alarm_outlined,
                title: 'No alarms',
                subtitle: 'Set a wake-up alarm for early mornings.',
                action: FilledButton(
                  onPressed: _addAlarm,
                  child: const Text('Add alarm'),
                ),
              )
            else
              ..._items.map(
                (item) => Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: ListTileCard(
                    icon: Icons.alarm,
                    title: Formatters.time(item.when),
                    subtitle: '${item.title} · ${item.repeatType.label}',
                    onTap: () async {
                      await context.push(AppRoutes.alarmDetail(item.id));
                      if (mounted) _load();
                    },
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class AlarmFormScreen extends StatefulWidget {
  const AlarmFormScreen({super.key, this.id});

  final int? id;

  @override
  State<AlarmFormScreen> createState() => _AlarmFormScreenState();
}

class _AlarmFormScreenState extends State<AlarmFormScreen> {
  final _title = TextEditingController(text: 'Wake up');
  RepeatType _repeat = RepeatType.daily;
  TimeOfDay _time = const TimeOfDay(hour: 6, minute: 0);
  bool _soundOn = true;
  bool _saving = false;

  PlannerService get _api => AppScope.of(context).planner;

  DateTime get _when => nextAlarmDateTime(_time);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _hydrate());
  }

  Future<void> _hydrate() async {
    if (widget.id == null) return;
    try {
      final existing = await _api.reminder(widget.id!);
      if (!mounted) return;
      setState(() {
        _title.text = existing.title;
        _repeat = existing.repeatType == RepeatType.none ||
                existing.repeatType == RepeatType.daily ||
                existing.repeatType == RepeatType.weekly
            ? existing.repeatType
            : RepeatType.daily;
        _time = TimeOfDay.fromDateTime(existing.reminderAt.toLocal());
      });
      final soundOn = await ReminderNotifications.instance.soundEnabled(existing.id);
      if (!mounted) return;
      setState(() => _soundOn = soundOn);
    } catch (error) {
      if (!mounted) return;
      showAppSnack(context, error.toString());
    }
  }

  @override
  void dispose() {
    _title.dispose();
    super.dispose();
  }

  Future<void> _pickTime() async {
    final time = await showTimePicker(context: context, initialTime: _time);
    if (time == null) return;
    setState(() => _time = time);
  }

  Future<void> _save() async {
    if (_saving) return;
    setState(() => _saving = true);
    try {
      await ReminderNotifications.instance.ensurePermissions(requestExact: true);
      final title = _title.text.trim().isEmpty ? 'Wake up' : _title.text.trim();
      final body = {
        'title': title,
        'description': '',
        'reminderAt': _when.toUtc().toIso8601String(),
        'repeatType': _repeat.name,
        'kind': 'alarm',
      };
      final reminder = widget.id == null
          ? await _api.createReminder(body)
          : await _api.updateReminder(widget.id!, body);
      await ReminderNotifications.instance.setSoundEnabled(reminder.id, _soundOn);
      final result = await ReminderNotifications.instance.sync(reminder, requestExact: true);
      try {
        await _api.updateReminder(reminder.id, {'notificationId': '${reminder.id}'});
      } catch (_) {}
      if (!mounted) return;
      if (result.message != null) {
        await showReminderScheduleResult(context, result);
      } else {
        showAppSnack(
          context,
          widget.id == null
              ? 'Alarm set for ${Formatters.time(_when)}'
              : 'Alarm updated',
        );
      }
      if (!mounted) return;
      context.pop();
    } catch (error) {
      if (!mounted) return;
      showAppSnack(context, error.toString());
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return FormPage(
      title: widget.id == null ? 'Add alarm' : 'Edit alarm',
      submitLabel: 'Save',
      submitting: _saving,
      onSubmit: _save,
      children: [
        AppTextField(
          controller: _title,
          label: 'Label',
          hint: 'Wake up',
          prefixIcon: Icons.alarm,
        ),
        const SizedBox(height: 14),
        AppPickerField(
          label: 'Time',
          value: _time.format(context),
          icon: Icons.schedule_outlined,
          onTap: _pickTime,
        ),
        const SizedBox(height: 8),
        Text(
          'Rings ${Formatters.dateTime(_when)}',
          style: TextStyle(color: Colors.grey.shade600),
        ),
        const SizedBox(height: 14),
        AppDropdown<RepeatType>(
          label: 'Repeat',
          value: _repeat,
          items: const [
            RepeatType.none,
            RepeatType.daily,
            RepeatType.weekly,
          ]
              .map((item) => DropdownMenuItem(
                    value: item,
                    child: Text(switch (item) {
                      RepeatType.none => 'Once',
                      RepeatType.daily => 'Every day',
                      RepeatType.weekly => 'Every week',
                      _ => item.label,
                    }),
                  ))
              .toList(),
          onChanged: (value) => setState(() => _repeat = value ?? _repeat),
        ),
        const SizedBox(height: 8),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Sound'),
          subtitle: const Text('Keeps ringing until you snooze or dismiss'),
          value: _soundOn,
          onChanged: (value) => setState(() => _soundOn = value),
        ),
      ],
    );
  }
}
