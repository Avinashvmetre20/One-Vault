import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../../app/app_scope.dart';
import '../../../../app/routes.dart';
import '../../../../app/theme/app_colors.dart';
import '../../../../core/widgets/empty_state.dart';
import '../../../../core/widgets/form_page.dart';
import '../../../../core/widgets/app_fields.dart';
import '../../../../core/widgets/list_tile_card.dart';
import '../../../../core/widgets/search_field.dart';
import '../../../../core/widgets/shell_fab.dart';
import '../../../../shared/helpers/formatters.dart';
import '../../../../shared/helpers/snack.dart';
import '../../data/planner_models.dart';
import '../../data/planner_service.dart';
import '../../data/reminder_notifications.dart';
import 'planner_screens.dart';

class TaskListScreen extends StatefulWidget {
  const TaskListScreen({super.key});

  @override
  State<TaskListScreen> createState() => _TaskListScreenState();
}

class _TaskListScreenState extends State<TaskListScreen> with PlannerTickReload {
  String _scope = 'all';
  String _search = '';
  bool _loading = true;
  String? _error;
  List<PlannerTask> _items = [];

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
      final page = await _api.tasks(
        scope: _scope == 'all' ? null : _scope,
        search: _search,
      );
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

  Future<void> _toggle(PlannerTask task) async {
    try {
      await _api.completeTask(task.id, reopen: task.isCompleted);
      await _load();
    } catch (error) {
      if (!mounted) return;
      showAppSnack(context, error.toString());
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Tasks')),
      floatingActionButton: ShellFab(
        heroTag: 'fab-tasks',
        tooltip: 'Add task',
        onPressed: () async {
          await context.push(AppRoutes.taskNew);
          if (mounted) _load();
        },
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 88),
          children: [
            AppSearchField(
              hintText: 'Search tasks',
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
                  ('all', 'All'),
                  ('today', 'Today'),
                  ('upcoming', 'Upcoming'),
                  ('completed', 'Done'),
                  ('archived', 'Archived'),
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
                icon: Icons.check_circle_outline,
                title: 'No tasks yet',
                subtitle: 'Create your first task to stay organized.',
                action: FilledButton(
                  onPressed: () async {
                    await context.push(AppRoutes.taskNew);
                    if (mounted) _load();
                  },
                  child: const Text('Add task'),
                ),
              )
            else
              ..._items.map(
                (item) => Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: ListTileCard(
                    icon: item.isCompleted
                        ? Icons.check_circle
                        : Icons.radio_button_unchecked,
                    title: item.title,
                    subtitle: [
                      item.priority.label,
                      if (item.categoryName != null) item.categoryName!,
                      if (item.dueDate != null) Formatters.date(item.dueDate!),
                    ].join(' · '),
                    trailing: IconButton(
                      onPressed: () => _toggle(item),
                      icon: Icon(
                        item.isCompleted ? Icons.undo : Icons.done,
                        color: item.isCompleted ? Colors.grey : AppColors.success,
                      ),
                    ),
                    onTap: () async {
                      await context.push(AppRoutes.taskDetail(item.id));
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

class TaskDetailScreen extends StatefulWidget {
  const TaskDetailScreen({super.key, required this.id});

  final int id;

  @override
  State<TaskDetailScreen> createState() => _TaskDetailScreenState();
}

class _TaskDetailScreenState extends State<TaskDetailScreen> {
  PlannerTask? _task;
  bool _loading = true;
  String? _error;

  PlannerService get _api => AppScope.of(context).planner;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final task = await _api.task(widget.id);
      if (!mounted) return;
      setState(() {
        _task = task;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error.toString();
        _loading = false;
      });
    }
  }

  Future<void> _run(Future<void> Function() action, String success) async {
    try {
      await action();
      if (!mounted) return;
      showAppSnack(context, success);
      await _load();
    } catch (error) {
      if (!mounted) return;
      showAppSnack(context, error.toString());
    }
  }

  @override
  Widget build(BuildContext context) {
    final task = _task;
    return Scaffold(
      appBar: AppBar(
        title: Text(task?.title ?? 'Task'),
        actions: [
          if (task != null)
            IconButton(
              onPressed: () async {
                await context.push(AppRoutes.taskEdit(task.id));
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
          : task == null
          ? const EmptyState(
              icon: Icons.check_circle_outline,
              title: 'Not found',
              subtitle: 'This task is gone.',
            )
          : ListView(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
              children: [
                if (task.description.isNotEmpty) ...[
                  Text(task.description, style: const TextStyle(fontSize: 16, height: 1.5)),
                  const SizedBox(height: 16),
                ],
                Text('Priority: ${task.priority.label}'),
                const SizedBox(height: 8),
                Text('Category: ${task.categoryName ?? 'None'}'),
                const SizedBox(height: 8),
                Text(
                  'Due: ${task.dueDate == null ? 'None' : '${Formatters.date(task.dueDate!)}${task.dueTime == null ? '' : ' · ${task.dueTime}'}'}',
                ),
                const SizedBox(height: 8),
                Text('Repeat: ${task.repeatType.label}'),
                const SizedBox(height: 8),
                Text('Status: ${task.status.label}'),
                if (task.subtasks.isNotEmpty) ...[
                  const SizedBox(height: 20),
                  const Text('Subtasks', style: TextStyle(fontWeight: FontWeight.w700)),
                  const SizedBox(height: 8),
                  for (final subtask in task.subtasks)
                    CheckboxListTile(
                      contentPadding: EdgeInsets.zero,
                      value: subtask.isCompleted,
                      title: Text(subtask.title),
                      onChanged: (value) => _run(
                        () => _api.updateSubtask(
                          task.id,
                          subtask.id,
                          isCompleted: value ?? false,
                        ),
                        'Subtask updated',
                      ),
                    ),
                ],
                const SizedBox(height: 20),
                FilledButton(
                  onPressed: () => _run(
                    () => _api.completeTask(task.id, reopen: task.isCompleted),
                    'Task updated',
                  ),
                  child: Text(task.isCompleted ? 'Reopen task' : 'Complete task'),
                ),
                const SizedBox(height: 8),
                OutlinedButton(
                  onPressed: () => _run(
                    () => task.isArchived ? _api.restoreTask(task.id) : _api.archiveTask(task.id),
                    task.isArchived ? 'Task restored' : 'Task archived',
                  ),
                  child: Text(task.isArchived ? 'Restore' : 'Archive'),
                ),
                const SizedBox(height: 8),
                TextButton(
                  onPressed: () async {
                    await _run(() => _api.deleteTask(task.id), 'Task deleted');
                    if (mounted) context.pop();
                  },
                  child: const Text('Delete', style: TextStyle(color: AppColors.danger)),
                ),
              ],
            ),
    );
  }
}

class TaskFormScreen extends StatefulWidget {
  const TaskFormScreen({super.key, this.id});

  final int? id;

  @override
  State<TaskFormScreen> createState() => _TaskFormScreenState();
}

class _TaskFormScreenState extends State<TaskFormScreen> {
  final _title = TextEditingController();
  final _description = TextEditingController();
  final _subtask = TextEditingController();
  TaskPriority _priority = TaskPriority.medium;
  RepeatType _repeat = RepeatType.none;
  DateTime? _dueDate = DateTime.now();
  TimeOfDay? _dueTime;
  int? _categoryId;
  List<PlannerCategory> _categories = [];
  List<String> _subtasks = [];
  DateTime? _reminderAt;
  bool _saving = false;

  bool get _isEdit => widget.id != null;
  PlannerService get _api => AppScope.of(context).planner;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _hydrate());
  }

  Future<void> _hydrate() async {
    try {
      final categories = await _api.taskCategories();
      PlannerTask? existing;
      if (widget.id != null) existing = await _api.task(widget.id!);
      if (!mounted) return;
      setState(() {
        _categories = categories;
        if (existing != null) {
          _title.text = existing.title;
          _description.text = existing.description;
          _priority = existing.priority;
          _repeat = existing.repeatType;
          _dueDate = existing.dueDate;
          _categoryId = existing.categoryId;
          _subtasks = existing.subtasks.map((item) => item.title).toList();
          if (existing.dueTime != null) {
            final parts = existing.dueTime!.split(':');
            _dueTime = TimeOfDay(hour: int.parse(parts[0]), minute: int.parse(parts[1]));
          }
        } else {
          _categoryId ??= categories.where((item) => item.name == 'Personal').firstOrNull?.id ??
              categories.firstOrNull?.id;
        }
      });
    } catch (error) {
      if (!mounted) return;
      showAppSnack(context, error.toString());
    }
  }

  @override
  void dispose() {
    _title.dispose();
    _description.dispose();
    _subtask.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_title.text.trim().isEmpty) {
      showAppSnack(context, 'Title is required');
      return;
    }
    if (_saving) return;
    setState(() => _saving = true);
    try {
      final body = {
        'title': _title.text.trim(),
        'description': _description.text.trim(),
        'priority': _priority.name,
        'repeatType': _repeat.name,
        'categoryId': _categoryId,
        'dueDate': _dueDate == null ? null : asDateOnly(_dueDate),
        'dueTime': _dueTime == null
            ? null
            : '${_dueTime!.hour.toString().padLeft(2, '0')}:${_dueTime!.minute.toString().padLeft(2, '0')}',
        if (!_isEdit) 'subtasks': _subtasks,
      };
      late PlannerTask task;
      if (_isEdit) {
        task = await _api.updateTask(widget.id!, body);
      } else {
        task = await _api.createTask(body);
      }
      if (_reminderAt != null) {
        await ReminderNotifications.instance.ensurePermissions(requestExact: true);
        final reminder = await _api.createReminder({
          'title': task.title,
          'reminderAt': _reminderAt!.toUtc().toIso8601String(),
          'taskId': task.id,
          'kind': 'reminder',
        });
        await ReminderNotifications.instance.sync(reminder, requestExact: true);
        try {
          await _api.updateReminder(reminder.id, {'notificationId': '${reminder.id}'});
        } catch (_) {}
      }
      if (!mounted) return;
      showAppSnack(context, _isEdit ? 'Task updated' : 'Task added');
      context.pop();
    } catch (error) {
      if (!mounted) return;
      showAppSnack(context, error.toString());
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _pickDate() async {
    final selected = await showDatePicker(
      context: context,
      initialDate: _dueDate ?? DateTime.now(),
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
    );
    if (selected != null) setState(() => _dueDate = selected);
  }

  Future<void> _pickTime() async {
    final selected = await showTimePicker(
      context: context,
      initialTime: _dueTime ?? TimeOfDay.now(),
    );
    if (selected != null) setState(() => _dueTime = selected);
  }

  Future<void> _pickReminder() async {
    final date = await showDatePicker(
      context: context,
      initialDate: _reminderAt ?? _dueDate ?? DateTime.now(),
      firstDate: DateTime.now().subtract(const Duration(days: 1)),
      lastDate: DateTime(2100),
    );
    if (date == null || !mounted) return;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(_reminderAt ?? DateTime.now()),
    );
    if (time == null) return;
    setState(() {
      _reminderAt = DateTime(date.year, date.month, date.day, time.hour, time.minute);
    });
  }

  @override
  Widget build(BuildContext context) {
    return FormPage(
      title: _isEdit ? 'Edit task' : 'Add task',
      submitLabel: 'Save',
      submitting: _saving,
      onSubmit: _save,
      children: [
        AppTextField(
          controller: _title,
          label: 'Title',
          hint: 'What do you need to do?',
          prefixIcon: Icons.check_circle_outline,
        ),
        const SizedBox(height: 14),
        AppTextField(
          controller: _description,
          label: 'Description',
          hint: 'Add a few details',
          maxLines: 4,
        ),
        const SizedBox(height: 16),
        Text('Priority', style: TextStyle(color: Colors.grey.shade700, fontWeight: FontWeight.w600)),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          children: TaskPriority.values
              .map(
                (priority) => ChoiceChip(
                  label: Text(priority.label),
                  selected: _priority == priority,
                  onSelected: (_) => setState(() => _priority = priority),
                ),
              )
              .toList(),
        ),
        const SizedBox(height: 14),
        AppDropdown<int>(
          label: 'Category',
          hint: 'Choose a category',
          value: _categoryId,
          items: _categories
              .map((item) => DropdownMenuItem(value: item.id, child: Text(item.name)))
              .toList(),
          onChanged: (value) => setState(() => _categoryId = value),
        ),
        const SizedBox(height: 14),
        AppPickerField(
          label: 'Due date',
          value: _dueDate == null ? 'Not set' : Formatters.date(_dueDate!),
          icon: Icons.calendar_today_outlined,
          onTap: _pickDate,
        ),
        const SizedBox(height: 14),
        AppPickerField(
          label: 'Due time',
          value: _dueTime == null ? 'Optional' : _dueTime!.format(context),
          icon: Icons.schedule_outlined,
          onTap: _pickTime,
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
        AppPickerField(
          label: 'Reminder',
          value: _reminderAt == null ? 'Optional' : Formatters.dateTime(_reminderAt!),
          icon: Icons.notifications_outlined,
          onTap: _pickReminder,
        ),
        const SizedBox(height: 18),
        const Text('Subtasks', style: TextStyle(fontWeight: FontWeight.w700)),
        const SizedBox(height: 8),
        for (var i = 0; i < _subtasks.length; i++)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: ListTileCard(
              icon: Icons.subdirectory_arrow_right,
              title: _subtasks[i],
              subtitle: 'Subtask',
              trailing: IconButton(
                onPressed: () => setState(() => _subtasks.removeAt(i)),
                icon: const Icon(Icons.close),
              ),
              onTap: () {},
            ),
          ),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: AppTextField(
                controller: _subtask,
                label: 'Add subtask',
                textInputAction: TextInputAction.done,
                onSubmitted: (_) => _addSubtask(),
              ),
            ),
            const SizedBox(width: 8),
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: IconButton.filled(
                onPressed: _addSubtask,
                icon: const Icon(Icons.add),
              ),
            ),
          ],
        ),
      ],
    );
  }

  void _addSubtask() {
    if (_subtask.text.trim().isEmpty) return;
    setState(() {
      _subtasks.add(_subtask.text.trim());
      _subtask.clear();
    });
  }
}
