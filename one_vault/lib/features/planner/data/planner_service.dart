import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../../core/network/api_client.dart';
import '../../../core/network/api_config.dart';
import 'planner_models.dart';
import 'reminder_notifications.dart';

class PlannerService {
  PlannerService({
    required String? Function() token,
    void Function()? onChanged,
    ApiClient? apiClient,
    http.Client? client,
  }) : _token = token,
       _onChanged = onChanged,
       _api = apiClient ?? ApiClient(client: client);

  final String? Function() _token;
  final void Function()? _onChanged;
  final ApiClient _api;

  static const _base = '/api/v1/planner';

  bool get _offline {
    final token = _token();
    return token == null || token.isEmpty || token == 'test-access-token';
  }

  Future<PlannerSummary> summary() async {
    if (_offline) return const PlannerSummary();
    final json = await _send(() => _api.get('$_base/summary', headers: _headers()));
    return PlannerSummary.fromJson(json['data'] as Map<String, dynamic>);
  }

  Future<List<PlannerSearchHit>> search(String query) async {
    if (_offline || query.trim().isEmpty) return const [];
    final json = await _send(
      () => _api.get(
        '$_base/search',
        headers: _headers(),
        query: {'q': query.trim()},
      ),
    );
    final results = (json['data'] as Map<String, dynamic>)['results'];
    if (results is! List) return const [];
    return results
        .whereType<Map>()
        .map((item) => PlannerSearchHit.fromJson(Map<String, dynamic>.from(item)))
        .toList();
  }

  Future<PlannerAgenda> agenda({String? from, String? to}) async {
    if (_offline) return const PlannerAgenda();
    final json = await _send(
      () => _api.get(
        '$_base/agenda',
        headers: _headers(),
        query: {
          if (from != null) 'from': from,
          if (to != null) 'to': to,
        },
      ),
    );
    return PlannerAgenda.fromJson(json['data'] as Map<String, dynamic>);
  }

  Future<List<PlannerCategory>> taskCategories() async {
    if (_offline) return const [];
    final json = await _send(() => _api.get('$_base/task-categories', headers: _headers()));
    return _categories(json);
  }

  Future<PlannerCategory> createTaskCategory(String name) async {
    final json = await _mutate(
      () => _api.post(
        '$_base/task-categories',
        headers: _headers(json: true),
        body: jsonEncode({'name': name}),
      ),
    );
    return PlannerCategory.fromJson(
      (json['data'] as Map<String, dynamic>)['category'] as Map<String, dynamic>,
    );
  }

  Future<PlannerPage<PlannerTask>> tasks({
    String? scope,
    String? search,
    String? priority,
    int? categoryId,
    int limit = 30,
    int offset = 0,
  }) async {
    if (_offline) {
      return const PlannerPage(items: [], total: 0, limit: 30, offset: 0);
    }
    final json = await _send(
      () => _api.get(
        '$_base/tasks',
        headers: _headers(),
        query: {
          'limit': '$limit',
          'offset': '$offset',
          if (scope != null && scope.isNotEmpty) 'scope': scope,
          if (search != null && search.isNotEmpty) 'search': search,
          if (priority != null && priority.isNotEmpty) 'priority': priority,
          if (categoryId != null) 'categoryId': '$categoryId',
        },
      ),
    );
    return _page(json, 'tasks', PlannerTask.fromJson);
  }

  Future<PlannerTask> task(int id) async {
    final json = await _send(() => _api.get('$_base/tasks/$id', headers: _headers()));
    return PlannerTask.fromJson(
      (json['data'] as Map<String, dynamic>)['task'] as Map<String, dynamic>,
    );
  }

  Future<PlannerTask> createTask(Map<String, dynamic> body) async {
    final json = await _mutate(
      () => _api.post('$_base/tasks', headers: _headers(json: true), body: jsonEncode(body)),
    );
    return PlannerTask.fromJson(
      (json['data'] as Map<String, dynamic>)['task'] as Map<String, dynamic>,
    );
  }

  Future<PlannerTask> updateTask(int id, Map<String, dynamic> body) async {
    final json = await _mutate(
      () => _api.patch('$_base/tasks/$id', headers: _headers(json: true), body: jsonEncode(body)),
    );
    return PlannerTask.fromJson(
      (json['data'] as Map<String, dynamic>)['task'] as Map<String, dynamic>,
    );
  }

  Future<void> deleteTask(int id) {
    return _mutate(() => _api.delete('$_base/tasks/$id', headers: _headers()));
  }

  Future<PlannerTask> completeTask(int id, {bool reopen = false}) async {
    List<PlannerReminder> linked = const [];
    if (!reopen) {
      try {
        linked = (await reminders(scope: 'upcoming', taskId: id, limit: 100)).items;
      } catch (_) {}
    }
    final json = await _mutate(
      () => _api.post(
        '$_base/tasks/$id/complete',
        headers: _headers(json: true),
        body: jsonEncode({'reopen': reopen}),
      ),
    );
    final task = PlannerTask.fromJson(
      (json['data'] as Map<String, dynamic>)['task'] as Map<String, dynamic>,
    );
    if (task.status == TaskStatus.completed) {
      for (final reminder in linked) {
        await ReminderNotifications.instance.cancel(reminder.id);
      }
    }
    return task;
  }

  Future<PlannerTask> archiveTask(int id) async {
    final json = await _mutate(
      () => _api.post('$_base/tasks/$id/archive', headers: _headers(json: true), body: jsonEncode({})),
    );
    return PlannerTask.fromJson(
      (json['data'] as Map<String, dynamic>)['task'] as Map<String, dynamic>,
    );
  }

  Future<PlannerTask> restoreTask(int id) async {
    final json = await _mutate(
      () => _api.post('$_base/tasks/$id/restore', headers: _headers(json: true), body: jsonEncode({})),
    );
    return PlannerTask.fromJson(
      (json['data'] as Map<String, dynamic>)['task'] as Map<String, dynamic>,
    );
  }

  Future<TaskSubtask> createSubtask(int taskId, String title) async {
    final json = await _mutate(
      () => _api.post(
        '$_base/tasks/$taskId/subtasks',
        headers: _headers(json: true),
        body: jsonEncode({'title': title}),
      ),
    );
    return TaskSubtask.fromJson(
      (json['data'] as Map<String, dynamic>)['subtask'] as Map<String, dynamic>,
    );
  }

  Future<TaskSubtask> updateSubtask(
    int taskId,
    int subtaskId, {
    String? title,
    bool? isCompleted,
    int? position,
  }) async {
    final json = await _mutate(
      () => _api.patch(
        '$_base/tasks/$taskId/subtasks/$subtaskId',
        headers: _headers(json: true),
        body: jsonEncode({
          if (title != null) 'title': title,
          if (isCompleted != null) 'isCompleted': isCompleted,
          if (position != null) 'position': position,
        }),
      ),
    );
    return TaskSubtask.fromJson(
      (json['data'] as Map<String, dynamic>)['subtask'] as Map<String, dynamic>,
    );
  }

  Future<void> deleteSubtask(int taskId, int subtaskId) {
    return _mutate(() => _api.delete('$_base/tasks/$taskId/subtasks/$subtaskId', headers: _headers()));
  }

  Future<List<PlannerCategory>> noteCategories() async {
    if (_offline) return const [];
    final json = await _send(() => _api.get('$_base/note-categories', headers: _headers()));
    return _categories(json);
  }

  Future<PlannerPage<PlannerNote>> notes({
    String? scope,
    String? search,
    bool? pinned,
    bool? favorite,
    int limit = 30,
    int offset = 0,
  }) async {
    if (_offline) {
      return const PlannerPage(items: [], total: 0, limit: 30, offset: 0);
    }
    final json = await _send(
      () => _api.get(
        '$_base/notes',
        headers: _headers(),
        query: {
          'limit': '$limit',
          'offset': '$offset',
          if (scope != null) 'scope': scope,
          if (search != null && search.isNotEmpty) 'search': search,
          if (pinned == true) 'pinned': 'true',
          if (favorite == true) 'favorite': 'true',
        },
      ),
    );
    return _page(json, 'notes', PlannerNote.fromJson);
  }

  Future<PlannerNote> note(int id) async {
    final json = await _send(() => _api.get('$_base/notes/$id', headers: _headers()));
    return PlannerNote.fromJson(
      (json['data'] as Map<String, dynamic>)['note'] as Map<String, dynamic>,
    );
  }

  Future<PlannerNote> createNote(Map<String, dynamic> body) async {
    final json = await _mutate(
      () => _api.post('$_base/notes', headers: _headers(json: true), body: jsonEncode(body)),
    );
    return PlannerNote.fromJson(
      (json['data'] as Map<String, dynamic>)['note'] as Map<String, dynamic>,
    );
  }

  Future<PlannerNote> updateNote(int id, Map<String, dynamic> body) async {
    final json = await _mutate(
      () => _api.patch('$_base/notes/$id', headers: _headers(json: true), body: jsonEncode(body)),
    );
    return PlannerNote.fromJson(
      (json['data'] as Map<String, dynamic>)['note'] as Map<String, dynamic>,
    );
  }

  Future<void> deleteNote(int id) {
    return _mutate(() => _api.delete('$_base/notes/$id', headers: _headers()));
  }

  Future<PlannerNote> pinNote(int id) async {
    final json = await _mutate(
      () => _api.post('$_base/notes/$id/pin', headers: _headers(json: true), body: jsonEncode({})),
    );
    return PlannerNote.fromJson(
      (json['data'] as Map<String, dynamic>)['note'] as Map<String, dynamic>,
    );
  }

  Future<PlannerNote> favoriteNote(int id) async {
    final json = await _mutate(
      () => _api.post('$_base/notes/$id/favorite', headers: _headers(json: true), body: jsonEncode({})),
    );
    return PlannerNote.fromJson(
      (json['data'] as Map<String, dynamic>)['note'] as Map<String, dynamic>,
    );
  }

  Future<PlannerNote> archiveNote(int id) async {
    final json = await _mutate(
      () => _api.post('$_base/notes/$id/archive', headers: _headers(json: true), body: jsonEncode({})),
    );
    return PlannerNote.fromJson(
      (json['data'] as Map<String, dynamic>)['note'] as Map<String, dynamic>,
    );
  }

  Future<PlannerNote> restoreNote(int id) async {
    final json = await _mutate(
      () => _api.post('$_base/notes/$id/restore', headers: _headers(json: true), body: jsonEncode({})),
    );
    return PlannerNote.fromJson(
      (json['data'] as Map<String, dynamic>)['note'] as Map<String, dynamic>,
    );
  }

  Future<PlannerPage<PlannerReminder>> reminders({
    String? scope,
    String? search,
    String? kind,
    int? taskId,
    int limit = 30,
    int offset = 0,
  }) async {
    if (_offline) {
      return const PlannerPage(items: [], total: 0, limit: 30, offset: 0);
    }
    final json = await _send(
      () => _api.get(
        '$_base/reminders',
        headers: _headers(),
        query: {
          'limit': '$limit',
          'offset': '$offset',
          if (scope != null) 'scope': scope,
          if (search != null && search.isNotEmpty) 'search': search,
          if (kind != null) 'kind': kind,
          if (taskId != null) 'taskId': '$taskId',
        },
      ),
    );
    return _page(json, 'reminders', PlannerReminder.fromJson);
  }

  Future<PlannerReminder> reminder(int id) async {
    final json = await _send(() => _api.get('$_base/reminders/$id', headers: _headers()));
    return PlannerReminder.fromJson(
      (json['data'] as Map<String, dynamic>)['reminder'] as Map<String, dynamic>,
    );
  }

  Future<PlannerReminder> createReminder(Map<String, dynamic> body) async {
    final json = await _mutate(
      () => _api.post('$_base/reminders', headers: _headers(json: true), body: jsonEncode(body)),
    );
    return PlannerReminder.fromJson(
      (json['data'] as Map<String, dynamic>)['reminder'] as Map<String, dynamic>,
    );
  }

  Future<PlannerReminder> updateReminder(int id, Map<String, dynamic> body) async {
    final json = await _mutate(
      () => _api.patch('$_base/reminders/$id', headers: _headers(json: true), body: jsonEncode(body)),
    );
    return PlannerReminder.fromJson(
      (json['data'] as Map<String, dynamic>)['reminder'] as Map<String, dynamic>,
    );
  }

  Future<void> deleteReminder(int id) {
    return _mutate(() => _api.delete('$_base/reminders/$id', headers: _headers()));
  }

  Future<PlannerReminder> completeReminder(int id, {bool reopen = false}) async {
    final json = await _mutate(
      () => _api.post(
        '$_base/reminders/$id/complete',
        headers: _headers(json: true),
        body: jsonEncode({'reopen': reopen}),
      ),
    );
    return PlannerReminder.fromJson(
      (json['data'] as Map<String, dynamic>)['reminder'] as Map<String, dynamic>,
    );
  }

  Future<PlannerReminder> snoozeReminder(int id, {int minutes = 10, DateTime? until}) async {
    final json = await _mutate(
      () => _api.post(
        '$_base/reminders/$id/snooze',
        headers: _headers(json: true),
        body: jsonEncode({
          'minutes': minutes,
          if (until != null) 'snoozedUntil': until.toUtc().toIso8601String(),
        }),
      ),
    );
    return PlannerReminder.fromJson(
      (json['data'] as Map<String, dynamic>)['reminder'] as Map<String, dynamic>,
    );
  }

  Future<PlannerReminder> cancelReminder(int id) async {
    final json = await _mutate(
      () => _api.post('$_base/reminders/$id/cancel', headers: _headers(json: true), body: jsonEncode({})),
    );
    return PlannerReminder.fromJson(
      (json['data'] as Map<String, dynamic>)['reminder'] as Map<String, dynamic>,
    );
  }

  Future<PlannerPage<CalendarEvent>> calendarEvents({
    String? from,
    String? to,
    int limit = 100,
    int offset = 0,
  }) async {
    if (_offline) {
      return const PlannerPage(items: [], total: 0, limit: 100, offset: 0);
    }
    final json = await _send(
      () => _api.get(
        '$_base/calendar',
        headers: _headers(),
        query: {
          'limit': '$limit',
          'offset': '$offset',
          if (from != null) 'from': from,
          if (to != null) 'to': to,
        },
      ),
    );
    return _page(json, 'events', CalendarEvent.fromJson);
  }

  Future<CalendarEvent> calendarEvent(int id) async {
    final json = await _send(() => _api.get('$_base/calendar/$id', headers: _headers()));
    return CalendarEvent.fromJson(
      (json['data'] as Map<String, dynamic>)['event'] as Map<String, dynamic>,
    );
  }

  Future<CalendarEvent> createCalendarEvent(Map<String, dynamic> body) async {
    final json = await _mutate(
      () => _api.post('$_base/calendar', headers: _headers(json: true), body: jsonEncode(body)),
    );
    return CalendarEvent.fromJson(
      (json['data'] as Map<String, dynamic>)['event'] as Map<String, dynamic>,
    );
  }

  Future<CalendarEvent> updateCalendarEvent(int id, Map<String, dynamic> body) async {
    final json = await _mutate(
      () => _api.patch('$_base/calendar/$id', headers: _headers(json: true), body: jsonEncode(body)),
    );
    return CalendarEvent.fromJson(
      (json['data'] as Map<String, dynamic>)['event'] as Map<String, dynamic>,
    );
  }

  Future<void> deleteCalendarEvent(int id) {
    return _mutate(() => _api.delete('$_base/calendar/$id', headers: _headers()));
  }

  List<PlannerCategory> _categories(Map<String, dynamic> json) {
    final raw = (json['data'] as Map<String, dynamic>)['categories'];
    if (raw is! List) return const [];
    return raw
        .whereType<Map>()
        .map((item) => PlannerCategory.fromJson(Map<String, dynamic>.from(item)))
        .toList();
  }

  PlannerPage<T> _page<T>(
    Map<String, dynamic> json,
    String key,
    T Function(Map<String, dynamic>) parse,
  ) {
    final data = json['data'] as Map<String, dynamic>;
    final raw = data[key];
    final pagination = data['pagination'] as Map<String, dynamic>? ?? const {};
    final items = raw is List
        ? raw.whereType<Map>().map((item) => parse(Map<String, dynamic>.from(item))).toList()
        : <T>[];
    return PlannerPage(
      items: items,
      total: asInt(pagination['total'] ?? items.length),
      limit: asInt(pagination['limit'] ?? items.length),
      offset: asInt(pagination['offset'] ?? 0),
    );
  }

  Map<String, String> _headers({bool json = false}) =>
      ApiClient.authHeaders(_token(), json: json);

  Future<Map<String, dynamic>> _mutate(
    Future<http.Response> Function() request,
  ) async {
    final json = await _send(request);
    _onChanged?.call();
    return json;
  }

  Future<Map<String, dynamic>> _send(
    Future<http.Response> Function() request,
  ) async {
    try {
      return await ApiClient.readJson(
        request,
        onError: (message, status) => PlannerException(message, statusCode: status),
      );
    } on PlannerException {
      rethrow;
    } on TimeoutException {
      throw PlannerException('Request timed out for ${ApiConfig.baseUrl}.');
    } catch (_) {
      throw PlannerException(
        'Cannot reach ${ApiConfig.baseUrl}. Check Wi-Fi and that the API is running.',
      );
    }
  }
}
