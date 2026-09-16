import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../../app/app_scope.dart';
import '../../../../app/routes.dart';
import '../../../../core/widgets/empty_state.dart';
import '../../../../core/widgets/form_page.dart';
import '../../../../core/widgets/hub_card.dart';
import '../../../../core/widgets/list_tile_card.dart';
import '../../../../shared/enums/enums.dart';
import '../../../../shared/helpers/formatters.dart';
import '../../../../shared/helpers/snack.dart';
import '../../../../shared/models/models.dart';

class PlannerHubScreen extends StatelessWidget {
  const PlannerHubScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Planner')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
        children: [
          HubCard(
            icon: Icons.check_circle_outline,
            title: 'Tasks',
            subtitle: '${state.todos.where((item) => !item.completed).length} open',
            onTap: () => context.push(AppRoutes.todos),
          ),
          HubCard(
            icon: Icons.sticky_note_2_outlined,
            title: 'Notes',
            subtitle: '${state.notes.length} notes',
            onTap: () => context.push(AppRoutes.notes),
          ),
          HubCard(
            icon: Icons.notifications_outlined,
            title: 'Reminders',
            subtitle: '${state.reminders.where((item) => !item.completed).length} upcoming',
            onTap: () => context.push(AppRoutes.reminders),
          ),
        ],
      ),
    );
  }
}

class ReminderListScreen extends StatelessWidget {
  const ReminderListScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Reminders')),
      floatingActionButton: FloatingActionButton(
        heroTag: 'fab-reminders',
        onPressed: () => context.push(AppRoutes.reminderNew),
        child: const Icon(Icons.add),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 88),
        children: [
          if (state.reminders.isEmpty)
            const EmptyState(
              icon: Icons.notifications_outlined,
              title: 'No reminders',
              subtitle: 'Create a reminder for bills, expiry, or tasks.',
            )
          else
            ...state.reminders.map(
              (item) => Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: ListTileCard(
                  icon: item.completed
                      ? Icons.notifications_off_outlined
                      : Icons.notifications_outlined,
                  title: item.title,
                  subtitle:
                      '${Formatters.dateTime(item.dateTime)} · ${item.recurrence.label}',
                  trailing: IconButton(
                    onPressed: () => state.toggleReminder(item.id),
                    icon: Icon(item.completed ? Icons.undo : Icons.done),
                  ),
                  onTap: () => context.push(AppRoutes.reminderDetail(item.id)),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class ReminderDetailScreen extends StatelessWidget {
  const ReminderDetailScreen({super.key, required this.id});

  final String id;

  @override
  Widget build(BuildContext context) {
    final item = AppScope.of(context).reminders.where((entry) => entry.id == id).firstOrNull;
    if (item == null) {
      return const Scaffold(
        body: EmptyState(
          icon: Icons.notifications_outlined,
          title: 'Not found',
          subtitle: 'This reminder is gone.',
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(title: Text(item.title)),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
        children: [
          Text(Formatters.dateTime(item.dateTime)),
          const SizedBox(height: 8),
          Text('Repeat: ${item.recurrence.label}'),
          const SizedBox(height: 8),
          Text('Linked to: ${item.linkedTo ?? 'None'}'),
          const SizedBox(height: 8),
          Text(item.completed ? 'Completed' : 'Scheduled'),
        ],
      ),
    );
  }
}

class ReminderFormScreen extends StatefulWidget {
  const ReminderFormScreen({super.key});

  @override
  State<ReminderFormScreen> createState() => _ReminderFormScreenState();
}

class _ReminderFormScreenState extends State<ReminderFormScreen> {
  final _title = TextEditingController();
  ReminderRecurrence _recurrence = ReminderRecurrence.none;

  @override
  void dispose() {
    _title.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FormPage(
      title: 'Add reminder',
      onSubmit: () {
        if (_title.text.trim().isEmpty) {
          showAppSnack(context, 'Title is required');
          return;
        }
        final state = AppScope.of(context);
        state.addReminder(
          ReminderItem(
            id: state.nextId('rem'),
            title: _title.text.trim(),
            dateTime: DateTime.now().add(const Duration(days: 1)),
            recurrence: _recurrence,
          ),
        );
        showAppSnack(context, 'Reminder added');
        context.pop();
      },
      children: [
        TextField(
          controller: _title,
          decoration: const InputDecoration(labelText: 'Title'),
        ),
        const SizedBox(height: 12),
        DropdownButtonFormField<ReminderRecurrence>(
          initialValue: _recurrence,
          decoration: const InputDecoration(labelText: 'Repeat'),
          items: ReminderRecurrence.values
              .map((item) => DropdownMenuItem(value: item, child: Text(item.label)))
              .toList(),
          onChanged: (value) => setState(() => _recurrence = value ?? _recurrence),
        ),
      ],
    );
  }
}
