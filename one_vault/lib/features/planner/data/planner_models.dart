class PlannerException implements Exception {
  const PlannerException(this.message, {this.statusCode});

  final String message;
  final int? statusCode;

  @override
  String toString() => message;
}

int asInt(dynamic value) {
  if (value is int) return value;
  return int.parse(value.toString());
}

int? asIntOrNull(dynamic value) {
  if (value == null) return null;
  return asInt(value);
}

DateTime? asDateTime(dynamic value) {
  if (value == null) return null;
  if (value is DateTime) return value.toUtc();
  return DateTime.tryParse(value.toString())?.toUtc();
}

DateTime? asCivilDate(dynamic value) {
  if (value == null) return null;
  if (value is DateTime) {
    final local = value.toLocal();
    return DateTime(local.year, local.month, local.day);
  }
  final match = RegExp(r'^(\d{4})-(\d{2})-(\d{2})').firstMatch(value.toString());
  if (match == null) return null;
  return DateTime(
    int.parse(match.group(1)!),
    int.parse(match.group(2)!),
    int.parse(match.group(3)!),
  );
}

String? asDateOnly(dynamic value) {
  final civil = asCivilDate(value);
  if (civil == null) return null;
  return '${civil.year.toString().padLeft(4, '0')}-${civil.month.toString().padLeft(2, '0')}-${civil.day.toString().padLeft(2, '0')}';
}

String? asTimeOnly(dynamic value) {
  if (value == null) return null;
  final text = value.toString();
  if (text.length >= 5) return text.substring(0, 5);
  return text;
}

enum TaskStatus { pending, completed, archived }

enum TaskPriority { low, medium, high }

enum RepeatType { none, daily, weekly, monthly, yearly, custom }

enum ReminderStatus { pending, completed, cancelled }

enum ReminderKind { reminder, alarm }

extension TaskStatusLabel on TaskStatus {
  String get label => switch (this) {
    TaskStatus.pending => 'Pending',
    TaskStatus.completed => 'Completed',
    TaskStatus.archived => 'Archived',
  };

  String get api => name;
}

extension TaskPriorityLabel on TaskPriority {
  String get label => switch (this) {
    TaskPriority.high => 'High',
    TaskPriority.medium => 'Medium',
    TaskPriority.low => 'Low',
  };
}

extension RepeatTypeLabel on RepeatType {
  String get label => switch (this) {
    RepeatType.none => "Doesn't repeat",
    RepeatType.daily => 'Daily',
    RepeatType.weekly => 'Weekly',
    RepeatType.monthly => 'Monthly',
    RepeatType.yearly => 'Yearly',
    RepeatType.custom => 'Custom',
  };

  String get api => name;
}

extension ReminderStatusLabel on ReminderStatus {
  String get label => switch (this) {
    ReminderStatus.pending => 'Scheduled',
    ReminderStatus.completed => 'Completed',
    ReminderStatus.cancelled => 'Cancelled',
  };
}

ReminderKind reminderKindFrom(dynamic value) {
  return ReminderKind.values.firstWhere(
    (item) => item.name == value?.toString(),
    orElse: () => ReminderKind.reminder,
  );
}

TaskStatus taskStatusFrom(dynamic value) {
  return TaskStatus.values.firstWhere(
    (item) => item.name == value?.toString(),
    orElse: () => TaskStatus.pending,
  );
}

TaskPriority taskPriorityFrom(dynamic value) {
  return TaskPriority.values.firstWhere(
    (item) => item.name == value?.toString(),
    orElse: () => TaskPriority.medium,
  );
}

RepeatType repeatTypeFrom(dynamic value) {
  return RepeatType.values.firstWhere(
    (item) => item.name == value?.toString(),
    orElse: () => RepeatType.none,
  );
}

ReminderStatus reminderStatusFrom(dynamic value) {
  return ReminderStatus.values.firstWhere(
    (item) => item.name == value?.toString(),
    orElse: () => ReminderStatus.pending,
  );
}

class PlannerPage<T> {
  const PlannerPage({required this.items, required this.total, required this.limit, required this.offset});

  final List<T> items;
  final int total;
  final int limit;
  final int offset;

  bool get hasMore => offset + items.length < total;
}

class PlannerSummary {
  const PlannerSummary({
    this.tasksOpen = 0,
    this.tasksToday = 0,
    this.notesTotal = 0,
    this.notesPinned = 0,
    this.remindersUpcoming = 0,
    this.remindersToday = 0,
    this.alarmsUpcoming = 0,
    this.alarmsToday = 0,
    this.eventsToday = 0,
  });

  final int tasksOpen;
  final int tasksToday;
  final int notesTotal;
  final int notesPinned;
  final int remindersUpcoming;
  final int remindersToday;
  final int alarmsUpcoming;
  final int alarmsToday;
  final int eventsToday;

  factory PlannerSummary.fromJson(Map<String, dynamic> json) {
    final tasks = json['tasks'] as Map<String, dynamic>? ?? const {};
    final notes = json['notes'] as Map<String, dynamic>? ?? const {};
    final reminders = json['reminders'] as Map<String, dynamic>? ?? const {};
    final alarms = json['alarms'] as Map<String, dynamic>? ?? const {};
    final events = json['events'] as Map<String, dynamic>? ?? const {};
    return PlannerSummary(
      tasksOpen: asInt(tasks['open'] ?? 0),
      tasksToday: asInt(tasks['today'] ?? 0),
      notesTotal: asInt(notes['total'] ?? 0),
      notesPinned: asInt(notes['pinned'] ?? 0),
      remindersUpcoming: asInt(reminders['upcoming'] ?? 0),
      remindersToday: asInt(reminders['today'] ?? 0),
      alarmsUpcoming: asInt(alarms['upcoming'] ?? 0),
      alarmsToday: asInt(alarms['today'] ?? 0),
      eventsToday: asInt(events['today'] ?? 0),
    );
  }
}

class PlannerCategory {
  const PlannerCategory({required this.id, required this.name});

  final int id;
  final String name;

  factory PlannerCategory.fromJson(Map<String, dynamic> json) {
    return PlannerCategory(
      id: asInt(json['taskCategoryId'] ?? json['noteCategoryId'] ?? json['id']),
      name: json['name'] as String,
    );
  }
}

class TaskSubtask {
  const TaskSubtask({
    required this.id,
    required this.taskId,
    required this.title,
    required this.isCompleted,
    required this.position,
  });

  final int id;
  final int taskId;
  final String title;
  final bool isCompleted;
  final int position;

  factory TaskSubtask.fromJson(Map<String, dynamic> json) {
    return TaskSubtask(
      id: asInt(json['taskSubtaskId'] ?? json['id']),
      taskId: asInt(json['taskId']),
      title: json['title'] as String,
      isCompleted: json['isCompleted'] == true,
      position: asInt(json['position'] ?? 0),
    );
  }
}

class PlannerTask {
  const PlannerTask({
    required this.id,
    required this.title,
    required this.description,
    required this.status,
    required this.priority,
    this.categoryId,
    this.categoryName,
    this.dueDate,
    this.dueTime,
    this.repeatType = RepeatType.none,
    this.repeatInterval = 1,
    this.isFavorite = false,
    this.isArchived = false,
    this.completedAt,
    this.subtasks = const [],
  });

  final int id;
  final String title;
  final String description;
  final TaskStatus status;
  final TaskPriority priority;
  final int? categoryId;
  final String? categoryName;
  final DateTime? dueDate;
  final String? dueTime;
  final RepeatType repeatType;
  final int repeatInterval;
  final bool isFavorite;
  final bool isArchived;
  final DateTime? completedAt;
  final List<TaskSubtask> subtasks;

  bool get isCompleted => status == TaskStatus.completed;

  factory PlannerTask.fromJson(Map<String, dynamic> json) {
    final rawSubtasks = json['subtasks'];
    return PlannerTask(
      id: asInt(json['taskId'] ?? json['id']),
      title: json['title'] as String? ?? '',
      description: json['description'] as String? ?? '',
      status: taskStatusFrom(json['status']),
      priority: taskPriorityFrom(json['priority']),
      categoryId: asIntOrNull(json['categoryId'] ?? json['taskCategoryId']),
      categoryName: json['categoryName'] as String?,
      dueDate: asCivilDate(json['dueDate']),
      dueTime: asTimeOnly(json['dueTime']),
      repeatType: repeatTypeFrom(json['repeatType']),
      repeatInterval: asInt(json['repeatInterval'] ?? 1),
      isFavorite: json['isFavorite'] == true,
      isArchived: json['isArchived'] == true,
      completedAt: asDateTime(json['completedAt']),
      subtasks: rawSubtasks is List
          ? rawSubtasks
                .whereType<Map>()
                .map((item) => TaskSubtask.fromJson(Map<String, dynamic>.from(item)))
                .toList()
          : const [],
    );
  }
}

class PlannerNote {
  const PlannerNote({
    required this.id,
    required this.title,
    required this.content,
    this.categoryId,
    this.categoryName,
    this.tags = const [],
    this.isPinned = false,
    this.isFavorite = false,
    this.isArchived = false,
    this.updatedAt,
  });

  final int id;
  final String title;
  final String content;
  final int? categoryId;
  final String? categoryName;
  final List<String> tags;
  final bool isPinned;
  final bool isFavorite;
  final bool isArchived;
  final DateTime? updatedAt;

  factory PlannerNote.fromJson(Map<String, dynamic> json) {
    final rawTags = json['tags'];
    return PlannerNote(
      id: asInt(json['noteId'] ?? json['id']),
      title: json['title'] as String? ?? '',
      content: json['content'] as String? ?? '',
      categoryId: asIntOrNull(json['categoryId'] ?? json['noteCategoryId']),
      categoryName: json['categoryName'] as String?,
      tags: rawTags is List ? rawTags.map((item) => item.toString()).toList() : const [],
      isPinned: json['isPinned'] == true,
      isFavorite: json['isFavorite'] == true,
      isArchived: json['isArchived'] == true,
      updatedAt: asDateTime(json['updatedAt']),
    );
  }
}

class PlannerReminder {
  const PlannerReminder({
    required this.id,
    required this.title,
    required this.description,
    required this.reminderAt,
    this.taskId,
    this.taskTitle,
    this.repeatType = RepeatType.none,
    this.repeatInterval = 1,
    this.status = ReminderStatus.pending,
    this.kind = ReminderKind.reminder,
    this.snoozedUntil,
    this.notificationId,
    this.timeZone,
  });

  final int id;
  final String title;
  final String description;
  final DateTime reminderAt;
  final int? taskId;
  final String? taskTitle;
  final RepeatType repeatType;
  final int repeatInterval;
  final ReminderStatus status;
  final ReminderKind kind;
  final DateTime? snoozedUntil;
  final String? notificationId;
  final String? timeZone;

  DateTime get when => snoozedUntil ?? reminderAt;
  bool get isCompleted => status == ReminderStatus.completed;
  bool get isAlarm => kind == ReminderKind.alarm;

  factory PlannerReminder.fromJson(Map<String, dynamic> json) {
    return PlannerReminder(
      id: asInt(json['reminderId'] ?? json['id']),
      title: json['title'] as String? ?? '',
      description: json['description'] as String? ?? '',
      reminderAt: asDateTime(json['reminderAt']) ?? DateTime.now().toUtc(),
      taskId: asIntOrNull(json['taskId']),
      taskTitle: json['taskTitle'] as String?,
      repeatType: repeatTypeFrom(json['repeatType']),
      repeatInterval: asInt(json['repeatInterval'] ?? 1),
      status: reminderStatusFrom(json['status']),
      kind: reminderKindFrom(json['kind']),
      snoozedUntil: asDateTime(json['snoozedUntil']),
      notificationId: json['notificationId']?.toString(),
      timeZone: json['timeZone'] as String?,
    );
  }
}

class CalendarEvent {
  const CalendarEvent({
    required this.id,
    required this.title,
    required this.description,
    required this.startAt,
    this.endAt,
    this.isAllDay = false,
    this.repeatType = RepeatType.none,
    this.repeatInterval = 1,
    this.timeZone,
  });

  final int id;
  final String title;
  final String description;
  final DateTime startAt;
  final DateTime? endAt;
  final bool isAllDay;
  final RepeatType repeatType;
  final int repeatInterval;
  final String? timeZone;

  factory CalendarEvent.fromJson(Map<String, dynamic> json) {
    return CalendarEvent(
      id: asInt(json['calendarEventId'] ?? json['id']),
      title: json['title'] as String? ?? '',
      description: json['description'] as String? ?? '',
      startAt: asDateTime(json['startAt']) ?? DateTime.now().toUtc(),
      endAt: asDateTime(json['endAt']),
      isAllDay: json['isAllDay'] == true,
      repeatType: repeatTypeFrom(json['repeatType']),
      repeatInterval: asInt(json['repeatInterval'] ?? 1),
      timeZone: json['timeZone'] as String?,
    );
  }
}

class PlannerSearchHit {
  const PlannerSearchHit({
    required this.type,
    required this.id,
    required this.title,
    this.subtitle,
  });

  final String type;
  final int id;
  final String title;
  final String? subtitle;

  factory PlannerSearchHit.fromJson(Map<String, dynamic> json) {
    final type = json['type'] as String? ?? 'task';
    final id = asInt(
      json['taskId'] ?? json['noteId'] ?? json['reminderId'] ?? json['calendarEventId'] ?? json['id'],
    );
    return PlannerSearchHit(
      type: type,
      id: id,
      title: json['title'] as String? ?? '',
      subtitle: json['description'] as String? ?? json['content'] as String?,
    );
  }
}

class PlannerAgenda {
  const PlannerAgenda({
    this.tasks = const [],
    this.reminders = const [],
    this.events = const [],
  });

  final List<PlannerTask> tasks;
  final List<PlannerReminder> reminders;
  final List<CalendarEvent> events;

  factory PlannerAgenda.fromJson(Map<String, dynamic> json) {
    List<T> mapList<T>(String key, T Function(Map<String, dynamic>) parse) {
      final raw = json[key];
      if (raw is! List) return <T>[];
      return raw
          .whereType<Map>()
          .map((item) => parse(Map<String, dynamic>.from(item)))
          .toList();
    }

    return PlannerAgenda(
      tasks: mapList('tasks', PlannerTask.fromJson),
      reminders: mapList('reminders', PlannerReminder.fromJson),
      events: mapList('events', CalendarEvent.fromJson),
    );
  }
}
