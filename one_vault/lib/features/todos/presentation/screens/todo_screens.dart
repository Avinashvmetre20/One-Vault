import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../../app/app_scope.dart';
import '../../../../app/routes.dart';
import '../../../../app/theme/app_colors.dart';
import '../../../../core/widgets/empty_state.dart';
import '../../../../core/widgets/form_page.dart';
import '../../../../core/widgets/list_tile_card.dart';
import '../../../../shared/enums/enums.dart';
import '../../../../shared/helpers/formatters.dart';
import '../../../../shared/helpers/snack.dart';
import '../../../../shared/models/models.dart';

class TodoListScreen extends StatelessWidget {
  const TodoListScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Tasks')),
      floatingActionButton: FloatingActionButton(
        heroTag: 'fab-todos',
        onPressed: () => context.push(AppRoutes.todoNew),
        child: const Icon(Icons.add),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 88),
        children: [
          if (state.todos.isEmpty)
            const EmptyState(
              icon: Icons.check_circle_outline,
              title: 'No tasks',
              subtitle: 'Add a task to get started.',
            )
          else
            ...state.todos.map(
              (item) => Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: ListTileCard(
                  icon: item.completed
                      ? Icons.check_circle
                      : Icons.radio_button_unchecked,
                  title: item.title,
                  subtitle:
                      '${item.priority.label}${item.dueDate == null ? '' : ' · ${Formatters.date(item.dueDate!)}'}',
                  trailing: IconButton(
                    onPressed: () => state.toggleTodo(item.id),
                    icon: Icon(
                      item.completed ? Icons.undo : Icons.done,
                      color: item.completed ? Colors.grey : AppColors.success,
                    ),
                  ),
                  onTap: () => context.push(AppRoutes.todoDetail(item.id)),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class TodoDetailScreen extends StatelessWidget {
  const TodoDetailScreen({super.key, required this.id});

  final String id;

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final item = state.todos.where((entry) => entry.id == id).firstOrNull;
    if (item == null) {
      return const Scaffold(
        body: EmptyState(
          icon: Icons.check_circle_outline,
          title: 'Not found',
          subtitle: 'This task is gone.',
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(title: Text(item.title)),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
        children: [
          Text(item.description),
          const SizedBox(height: 12),
          Text('Priority: ${item.priority.label}'),
          const SizedBox(height: 8),
          Text('Category: ${item.category}'),
          const SizedBox(height: 8),
          Text(
            'Due: ${item.dueDate == null ? 'None' : Formatters.dateTime(item.dueDate!)}',
          ),
          const SizedBox(height: 8),
          Text(item.completed ? 'Completed' : 'Open'),
          const SizedBox(height: 20),
          FilledButton(
            onPressed: () {
              state.toggleTodo(item.id);
              showAppSnack(context, 'Task updated');
            },
            child: Text(item.completed ? 'Mark open' : 'Mark complete'),
          ),
        ],
      ),
    );
  }
}

class TodoFormScreen extends StatefulWidget {
  const TodoFormScreen({super.key});

  @override
  State<TodoFormScreen> createState() => _TodoFormScreenState();
}

class _TodoFormScreenState extends State<TodoFormScreen> {
  final _title = TextEditingController();
  final _description = TextEditingController();
  TodoPriority _priority = TodoPriority.medium;

  @override
  void dispose() {
    _title.dispose();
    _description.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FormPage(
      title: 'Add task',
      onSubmit: () {
        if (_title.text.trim().isEmpty) {
          showAppSnack(context, 'Title is required');
          return;
        }
        final state = AppScope.of(context);
        state.addTodo(
          TodoItem(
            id: state.nextId('todo'),
            title: _title.text.trim(),
            description: _description.text.trim(),
            priority: _priority,
            category: 'Personal',
            dueDate: DateTime.now(),
          ),
        );
        showAppSnack(context, 'Task added');
        context.pop();
      },
      children: [
        TextField(
          controller: _title,
          decoration: const InputDecoration(labelText: 'Title'),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _description,
          maxLines: 3,
          decoration: const InputDecoration(labelText: 'Description'),
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          children: TodoPriority.values
              .map(
                (priority) => ChoiceChip(
                  label: Text(priority.label),
                  selected: _priority == priority,
                  onSelected: (_) => setState(() => _priority = priority),
                ),
              )
              .toList(),
        ),
      ],
    );
  }
}
