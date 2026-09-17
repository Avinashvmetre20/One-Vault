import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../../app/app_scope.dart';
import '../../../../app/routes.dart';
import '../../../../app/theme/app_colors.dart';
import '../../../../core/widgets/empty_state.dart';
import '../../../../core/widgets/form_page.dart';
import '../../../../core/widgets/app_fields.dart';
import '../../../../core/widgets/list_tile_card.dart';
import '../../../../core/widgets/shell_fab.dart';
import '../../../../shared/helpers/formatters.dart';
import '../../../../shared/helpers/snack.dart';
import '../../data/planner_models.dart';
import '../../data/planner_service.dart';
import 'planner_screens.dart';

class PlannerCalendarScreen extends StatefulWidget {
  const PlannerCalendarScreen({super.key});

  @override
  State<PlannerCalendarScreen> createState() => _PlannerCalendarScreenState();
}

class _PlannerCalendarScreenState extends State<PlannerCalendarScreen>
    with PlannerTickReload {
  DateTime _month = DateTime(DateTime.now().year, DateTime.now().month);
  DateTime _selected = DateTime.now();
  bool _agenda = true;
  bool _loading = true;
  String? _error;
  PlannerAgenda _data = const PlannerAgenda();

  PlannerService get _api => AppScope.of(context).planner;

  @override
  Future<void> reloadPlannerData() => _load();

  String _ymd(DateTime date) =>
      '${date.year.toString().padLeft(4, '0')}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';

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
      final start = DateTime(_month.year, _month.month, 1);
      final end = DateTime(_month.year, _month.month + 1, 0);
      final data = await _api.agenda(from: _ymd(start), to: _ymd(end));
      if (!mounted) return;
      setState(() {
        _data = data;
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

  bool _sameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  List<Widget> _itemsFor(DateTime day) {
    final cards = <Widget>[];
    for (final task in _data.tasks) {
      if (task.dueDate != null && _sameDay(task.dueDate!, day)) {
        cards.add(
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: ListTileCard(
              icon: Icons.check_circle_outline,
              title: task.title,
              subtitle: 'Task · ${task.priority.label}',
              onTap: () => context.push(AppRoutes.taskDetail(task.id)),
            ),
          ),
        );
      }
    }
    for (final reminder in _data.reminders) {
      if (_sameDay(reminder.when, day)) {
        cards.add(
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: ListTileCard(
              icon: Icons.notifications_outlined,
              title: reminder.title,
              subtitle: 'Reminder · ${Formatters.dateTime(reminder.when)}',
              onTap: () => context.push(AppRoutes.reminderDetail(reminder.id)),
            ),
          ),
        );
      }
    }
    for (final event in _data.events) {
      final overlaps = _sameDay(event.startAt, day) ||
          (event.endAt != null &&
              !day.isBefore(DateTime(event.startAt.year, event.startAt.month, event.startAt.day)) &&
              !day.isAfter(DateTime(event.endAt!.year, event.endAt!.month, event.endAt!.day)));
      if (overlaps) {
        cards.add(
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: ListTileCard(
              icon: Icons.event_outlined,
              title: event.title,
              subtitle: event.isAllDay ? 'All day' : Formatters.dateTime(event.startAt),
              onTap: () => context.push(AppRoutes.calendarEdit(event.id)),
            ),
          ),
        );
      }
    }
    return cards;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Calendar'),
        actions: [
          IconButton(
            onPressed: () {
              setState(() => _agenda = !_agenda);
            },
            icon: Icon(_agenda ? Icons.calendar_month_outlined : Icons.view_agenda_outlined),
          ),
        ],
      ),
      floatingActionButton: ShellFab(
        heroTag: 'fab-calendar',
        tooltip: 'Add event',
        onPressed: () async {
          await context.push(AppRoutes.calendarNew);
          if (mounted) _load();
        },
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 88),
          children: [
            Row(
              children: [
                IconButton(
                  onPressed: () {
                    setState(() => _month = DateTime(_month.year, _month.month - 1));
                    _load();
                  },
                  icon: const Icon(Icons.chevron_left),
                ),
                Expanded(
                  child: Text(
                    Formatters.date(_month, pattern: 'MMMM yyyy'),
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                ),
                IconButton(
                  onPressed: () {
                    setState(() => _month = DateTime(_month.year, _month.month + 1));
                    _load();
                  },
                  icon: const Icon(Icons.chevron_right),
                ),
              ],
            ),
            if (!_agenda) _MonthGrid(
              month: _month,
              selected: _selected,
              onSelect: (day) => setState(() {
                _selected = day;
                _agenda = true;
              }),
            ),
            const SizedBox(height: 12),
            if (_loading)
              const Center(child: Padding(
                padding: EdgeInsets.all(24),
                child: CircularProgressIndicator(),
              ))
            else if (_error != null)
              PlannerErrorState(message: _error!, onRetry: _load)
            else if (_agenda) ...[
              Text(
                Formatters.weekdayDate(_selected),
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 12),
              ...() {
                final items = _itemsFor(_selected);
                if (items.isEmpty) {
                  return [
                    const EmptyState(
                      icon: Icons.event_outlined,
                      title: 'Nothing scheduled',
                      subtitle: 'No tasks, reminders, or events on this day.',
                    ),
                  ];
                }
                return items;
              }(),
            ],
          ],
        ),
      ),
    );
  }
}

class _MonthGrid extends StatelessWidget {
  const _MonthGrid({
    required this.month,
    required this.selected,
    required this.onSelect,
  });

  final DateTime month;
  final DateTime selected;
  final ValueChanged<DateTime> onSelect;

  @override
  Widget build(BuildContext context) {
    final first = DateTime(month.year, month.month, 1);
    final daysInMonth = DateTime(month.year, month.month + 1, 0).day;
    final startWeekday = first.weekday % 7;
    final tiles = <Widget>[
      for (final label in const ['S', 'M', 'T', 'W', 'T', 'F', 'S'])
        Center(child: Text(label, style: TextStyle(color: Colors.grey.shade600, fontSize: 12))),
      for (var i = 0; i < startWeekday; i++) const SizedBox.shrink(),
      for (var day = 1; day <= daysInMonth; day++)
        _DayCell(
          day: day,
          selected: selected.year == month.year && selected.month == month.month && selected.day == day,
          onTap: () => onSelect(DateTime(month.year, month.month, day)),
        ),
    ];

    return GridView.count(
      crossAxisCount: 7,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      children: tiles,
    );
  }
}

class _DayCell extends StatelessWidget {
  const _DayCell({required this.day, required this.selected, required this.onTap});

  final int day;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Center(
        child: Container(
          width: 36,
          height: 36,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: selected ? AppColors.primary : Colors.transparent,
            shape: BoxShape.circle,
          ),
          child: Text(
            '$day',
            style: TextStyle(
              color: selected ? Colors.white : null,
              fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
            ),
          ),
        ),
      ),
    );
  }
}

class CalendarEventFormScreen extends StatefulWidget {
  const CalendarEventFormScreen({super.key, this.id});

  final int? id;

  @override
  State<CalendarEventFormScreen> createState() => _CalendarEventFormScreenState();
}

class _CalendarEventFormScreenState extends State<CalendarEventFormScreen> {
  final _title = TextEditingController();
  final _description = TextEditingController();
  DateTime _start = DateTime.now().add(const Duration(hours: 1));
  DateTime? _end;
  bool _allDay = false;
  RepeatType _repeat = RepeatType.none;
  bool _saving = false;

  PlannerService get _api => AppScope.of(context).planner;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _hydrate());
  }

  Future<void> _hydrate() async {
    if (widget.id == null) return;
    try {
      final event = await _api.calendarEvent(widget.id!);
      if (!mounted) return;
      setState(() {
        _title.text = event.title;
        _description.text = event.description;
        _start = event.startAt;
        _end = event.endAt;
        _allDay = event.isAllDay;
        _repeat = event.repeatType;
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
    super.dispose();
  }

  Future<DateTime?> _pickDateTime(DateTime initial) async {
    final date = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
    );
    if (date == null || !mounted) return null;
    if (_allDay) return DateTime(date.year, date.month, date.day);
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(initial),
    );
    if (time == null) return null;
    return DateTime(date.year, date.month, date.day, time.hour, time.minute);
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
        'startAt': _start.toUtc().toIso8601String(),
        'endAt': _end?.toUtc().toIso8601String(),
        'isAllDay': _allDay,
        'repeatType': _repeat.name,
      };
      if (widget.id == null) {
        await _api.createCalendarEvent(body);
      } else {
        await _api.updateCalendarEvent(widget.id!, body);
      }
      if (!mounted) return;
      showAppSnack(context, widget.id == null ? 'Event added' : 'Event updated');
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
      title: widget.id == null ? 'Add event' : 'Edit event',
      submitLabel: 'Save',
      submitting: _saving,
      onSubmit: _save,
      children: [
        AppTextField(
          controller: _title,
          label: 'Title',
          hint: 'Event name',
          prefixIcon: Icons.event_outlined,
        ),
        const SizedBox(height: 14),
        AppTextField(
          controller: _description,
          label: 'Description',
          hint: 'Optional details',
          maxLines: 3,
        ),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('All day'),
          value: _allDay,
          onChanged: (value) => setState(() => _allDay = value),
        ),
        AppPickerField(
          label: 'Start',
          value: Formatters.dateTime(_start),
          icon: Icons.schedule_outlined,
          onTap: () async {
            final value = await _pickDateTime(_start);
            if (value != null) setState(() => _start = value);
          },
        ),
        const SizedBox(height: 14),
        AppPickerField(
          label: 'End',
          value: _end == null ? 'Optional' : Formatters.dateTime(_end!),
          icon: Icons.schedule_outlined,
          onTap: () async {
            final value = await _pickDateTime(_end ?? _start.add(const Duration(hours: 1)));
            if (value != null) setState(() => _end = value);
          },
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
        if (widget.id != null)
          TextButton(
            onPressed: () async {
              await _api.deleteCalendarEvent(widget.id!);
              if (!mounted) return;
              showAppSnack(context, 'Event deleted');
              context.pop();
            },
            child: const Text('Delete', style: TextStyle(color: AppColors.danger)),
          ),
      ],
    );
  }
}
