import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../../app/app_scope.dart';
import '../../../../app/routes.dart';
import '../../../../app/theme/app_colors.dart';
import '../../../../app/theme/app_dimensions.dart';
import '../../../../core/widgets/empty_state.dart';
import '../../../../core/widgets/form_page.dart';
import '../../../../core/widgets/app_fields.dart';
import '../../../../core/widgets/list_tile_card.dart';
import '../../../../core/widgets/search_field.dart';
import '../../../../core/widgets/shell_fab.dart';
import '../../../../shared/helpers/formatters.dart';
import '../../../../shared/helpers/confirm.dart';
import '../../../../shared/helpers/snack.dart';
import '../../data/planner_models.dart';
import '../../data/planner_service.dart';
import '../../data/reminder_notifications.dart';
import 'planner_screens.dart';

Future<void> showReminderScheduleResult(
  BuildContext context,
  ReminderScheduleResult result,
) async {
  if (!context.mounted) return;
  final message = result.message;
  if (message != null && !result.exactAlarmsAllowed) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(message),
          action: SnackBarAction(
            label: 'Settings',
            onPressed: () => ReminderNotifications.instance.requestExactAlarmSettings(),
          ),
        ),
      );
    return;
  }
  if (message != null) {
    showAppSnack(context, message);
  }
}

class ReminderListScreen extends StatefulWidget {
  const ReminderListScreen({super.key});

  @override
  State<ReminderListScreen> createState() => _ReminderListScreenState();
}

class _ReminderListScreenState extends State<ReminderListScreen> with PlannerTickReload {
  String _scope = 'upcoming';
  String _search = '';
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
      final page = await _api.reminders(scope: _scope, search: _search, kind: 'reminder');
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

  Future<void> _toggle(PlannerReminder item) async {
    try {
      final updated = await _api.completeReminder(item.id, reopen: item.isCompleted);
      await ReminderNotifications.instance.sync(updated);
      await _load();
    } catch (error) {
      if (!mounted) return;
      showAppSnack(context, error.toString());
    }
  }

  Future<void> _addReminder() async {
    await context.push(AppRoutes.reminderNew);
    if (mounted) _load();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Reminders'),
        actions: [
          IconButton(
            tooltip: 'Add reminder',
            onPressed: _addReminder,
            icon: const Icon(Icons.add_rounded),
          ),
        ],
      ),
      floatingActionButton: ShellFab(
        heroTag: 'fab-reminders',
        tooltip: 'Add reminder',
        onPressed: _addReminder,
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: AppDimensions.pagePaddingTallFab,
          children: [
            AppSearchField(
              hintText: 'Search reminders',
              onChanged: (value) {
                _search = value;
                _load(silent: true);
              },
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              children: [
                for (final item in const [
                  ('upcoming', 'Upcoming'),
                  ('today', 'Today'),
                  ('completed', 'Done'),
                  ('cancelled', 'Cancelled'),
                ])
                  ChoiceChip(
                    label: Text(item.$2),
                    selected: _scope == item.$1,
                    onSelected: (_) {
                      setState(() => _scope = item.$1);
                      _load();
                    },
                  ),
              ],
            ),
            const SizedBox(height: 16),
            if (_loading)
              const Center(child: Padding(
                padding: EdgeInsets.all(24),
                child: CircularProgressIndicator(),
              ))
            else if (_error != null)
              PlannerErrorState(message: _error!, onRetry: _load)
            else if (_items.isEmpty)
              EmptyState(
                icon: Icons.notifications_outlined,
                title: 'No reminders',
                subtitle: 'Set a 7-minute check, bill reminder, or follow-up.',
                action: FilledButton(
                  onPressed: _addReminder,
                  child: const Text('Add reminder'),
                ),
              )
            else
              ..._items.map(
                (item) => Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: ListTileCard(
                    icon: item.status == ReminderStatus.pending
                        ? Icons.notifications_outlined
                        : Icons.notifications_off_outlined,
                    title: item.title,
                    subtitle: '${Formatters.dateTime(item.when)} · ${item.repeatType.label}',
                    trailing: IconButton(
                      onPressed: () => _toggle(item),
                      icon: Icon(item.isCompleted ? Icons.undo : Icons.done),
                    ),
                    onTap: () async {
                      await context.push(AppRoutes.reminderDetail(item.id));
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

class ReminderDetailScreen extends StatefulWidget {
  const ReminderDetailScreen({super.key, required this.id});

  final int id;

  @override
  State<ReminderDetailScreen> createState() => _ReminderDetailScreenState();
}

class _ReminderDetailScreenState extends State<ReminderDetailScreen> {
  PlannerReminder? _item;
  bool _loading = true;
  String? _error;

  PlannerService get _api => AppScope.of(context).planner;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
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

  Future<void> _run(Future<PlannerReminder> Function() action, String message) async {
    try {
      final updated = await action();
      await ReminderNotifications.instance.sync(updated);
      if (!mounted) return;
      showAppSnack(context, message);
      await _load();
    } catch (error) {
      if (!mounted) return;
      showAppSnack(context, error.toString());
    }
  }

  Future<void> _snooze() async {
    final choice = await showModalBottomSheet<int>(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(title: const Text('5 minutes'), onTap: () => Navigator.pop(context, 5)),
            ListTile(title: const Text('10 minutes'), onTap: () => Navigator.pop(context, 10)),
            ListTile(title: const Text('30 minutes'), onTap: () => Navigator.pop(context, 30)),
            ListTile(title: const Text('1 hour'), onTap: () => Navigator.pop(context, 60)),
            ListTile(title: const Text('Tomorrow'), onTap: () => Navigator.pop(context, 24 * 60)),
          ],
        ),
      ),
    );
    if (choice == null) return;
    await _run(() => _api.snoozeReminder(widget.id, minutes: choice), 'Reminder snoozed');
  }

  @override
  Widget build(BuildContext context) {
    final item = _item;
    return Scaffold(
      appBar: AppBar(
        title: Text(item?.isAlarm == true ? 'Alarm' : (item?.title ?? 'Reminder')),
        actions: [
          if (item != null)
            IconButton(
              onPressed: () async {
                await context.push(
                  item.isAlarm ? AppRoutes.alarmEdit(item.id) : AppRoutes.reminderEdit(item.id),
                );
                if (mounted) _load();
              },
              icon: const Icon(Icons.edit_outlined),
            ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
          ? PlannerErrorState(message: _error!, onRetry: _load)
          : item == null
          ? const EmptyState(
              icon: Icons.notifications_outlined,
              title: 'Not found',
              subtitle: 'This reminder is gone.',
            )
          : ListView(
              padding: AppDimensions.pagePadding,
              children: [
                Text(Formatters.dateTime(item.when)),
                const SizedBox(height: 8),
                Text('Repeat: ${item.repeatType.label}'),
                const SizedBox(height: 8),
                Text('Linked task: ${item.taskTitle ?? 'None'}'),
                const SizedBox(height: 8),
                Text(item.status.label),
                if (item.description.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  Text(item.description),
                ],
                const SizedBox(height: 20),
                FilledButton(
                  onPressed: () => _run(
                    () => _api.completeReminder(item.id, reopen: item.isCompleted),
                    'Reminder updated',
                  ),
                  child: Text(item.isCompleted ? 'Reopen' : 'Complete'),
                ),
                const SizedBox(height: 8),
                OutlinedButton(onPressed: _snooze, child: const Text('Snooze')),
                const SizedBox(height: 8),
                OutlinedButton(
                  onPressed: () => _run(() => _api.cancelReminder(item.id), 'Reminder cancelled'),
                  child: const Text('Cancel reminder'),
                ),
                TextButton(
                  onPressed: () async {
                    final kind = item.isAlarm ? 'alarm' : 'reminder';
                    final confirmed = await showAppConfirm(
                      context,
                      title: 'Delete this $kind?',
                      message: '${item.title} will be removed. This cannot be undone.',
                    );
                    if (!confirmed || !mounted) return;
                    await ReminderNotifications.instance.cancel(item.id);
                    await _api.deleteReminder(item.id);
                    if (!mounted) return;
                    showAppSnack(context, item.isAlarm ? 'Alarm deleted' : 'Reminder deleted');
                    context.pop();
                  },
                  child: const Text('Delete', style: TextStyle(color: AppColors.danger)),
                ),
              ],
            ),
    );
  }
}

class ReminderFormScreen extends StatefulWidget {
  const ReminderFormScreen({super.key, this.id});

  final int? id;

  @override
  State<ReminderFormScreen> createState() => _ReminderFormScreenState();
}

class _ReminderFormScreenState extends State<ReminderFormScreen> {
  final _title = TextEditingController();
  final _description = TextEditingController();
  RepeatType _repeat = RepeatType.none;
  DateTime _when = DateTime.now().add(const Duration(minutes: 7));
  int? _quickMinutes = 7;
  int? _taskId;
  List<PlannerTask> _tasks = [];
  bool _soundOn = true;
  bool _saving = false;

  PlannerService get _api => AppScope.of(context).planner;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _hydrate());
  }

  Future<void> _hydrate() async {
    try {
      final tasks = await _api.tasks(scope: 'all');
      PlannerReminder? existing;
      if (widget.id != null) existing = await _api.reminder(widget.id!);
      if (!mounted) return;
      setState(() {
        _tasks = tasks.items;
        if (existing != null) {
          _title.text = existing.title;
          _description.text = existing.description;
          _repeat = existing.repeatType;
          _when = existing.reminderAt.toLocal();
          _taskId = existing.taskId;
          _quickMinutes = null;
        }
      });
      if (existing != null) {
        final soundOn = await ReminderNotifications.instance.soundEnabled(existing.id);
        if (!mounted) return;
        setState(() => _soundOn = soundOn);
      }
    } catch (error) {
      if (!mounted) return;
      showAppSnack(context, error.toString());
    }
  }

  @override
  void dispose() {
    _title.dispose();
    _description.dispose();
    super.dispose();
  }

  Future<void> _pickWhen() async {
    final date = await showDatePicker(
      context: context,
      initialDate: _when,
      firstDate: DateTime.now().subtract(const Duration(days: 1)),
      lastDate: DateTime(2100),
    );
    if (date == null || !mounted) return;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(_when),
    );
    if (time == null) return;
    setState(() {
      _when = DateTime(date.year, date.month, date.day, time.hour, time.minute);
      _quickMinutes = null;
    });
  }

  Future<void> _save() async {
    if (_title.text.trim().isEmpty) {
      showAppSnack(context, 'Title is required');
      return;
    }
    if (_saving) return;
    setState(() => _saving = true);
    try {
      await ReminderNotifications.instance.ensurePermissions(requestExact: true);
      final body = {
        'title': _title.text.trim(),
        'description': _description.text.trim(),
        'reminderAt': _when.toUtc().toIso8601String(),
        'repeatType': _repeat.name,
        'taskId': _taskId,
        'kind': 'reminder',
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
        var message = widget.id == null ? 'Reminder added' : 'Reminder updated';
        if (result.scheduled && await ReminderNotifications.instance.consumeBatteryHint()) {
          message =
              '$message Your device may delay alarms because of battery restrictions.';
        }
        if (!mounted) return;
        showAppSnack(context, message);
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
      title: widget.id == null ? 'Add reminder' : 'Edit reminder',
      submitLabel: 'Save',
      submitting: _saving,
      onSubmit: _save,
      children: [
        AppTextField(
          controller: _title,
          label: 'Title',
          hint: 'What should we remind you about?',
          prefixIcon: Icons.notifications_outlined,
        ),
        const SizedBox(height: 14),
        AppTextField(
          controller: _description,
          label: 'Description',
          hint: 'Optional details',
          maxLines: 3,
        ),
        const SizedBox(height: 14),
        AppPickerField(
          label: 'Date and time',
          value: Formatters.dateTime(_when),
          icon: Icons.schedule_outlined,
          onTap: _pickWhen,
        ),
        const SizedBox(height: 12),
        Text('Remind me in', style: TextStyle(color: AppColors.muted(context), fontWeight: FontWeight.w600)),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final item in const [
              (5, '5 min'),
              (7, '7 min'),
              (10, '10 min'),
              (15, '15 min'),
              (30, '30 min'),
              (60, '1 hour'),
            ])
              ChoiceChip(
                label: Text(item.$2),
                selected: _quickMinutes == item.$1,
                onSelected: (_) => setState(() {
                  _quickMinutes = item.$1;
                  _when = DateTime.now().add(Duration(minutes: item.$1));
                }),
              ),
          ],
        ),
        const SizedBox(height: 14),
        AppDropdown<RepeatType>(
          label: 'Repeat',
          value: _repeat,
          items: RepeatType.values
              .map((item) => DropdownMenuItem(value: item, child: Text(item.label)))
              .toList(),
          onChanged: (value) => setState(() => _repeat = value ?? _repeat),
        ),
        const SizedBox(height: 14),
        AppDropdown<int?>(
          label: 'Linked task',
          hint: 'Optional',
          value: _taskId,
          items: [
            const DropdownMenuItem<int?>(value: null, child: Text('None')),
            ..._tasks.map(
              (item) => DropdownMenuItem<int?>(value: item.id, child: Text(item.title)),
            ),
          ],
          onChanged: (value) => setState(() => _taskId = value),
        ),
        const SizedBox(height: 8),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Sound'),
          value: _soundOn,
          onChanged: (value) => setState(() => _soundOn = value),
        ),
      ],
    );
  }
}
