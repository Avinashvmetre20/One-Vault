import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/data/latest.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

import '../../../core/network/device_time_zone.dart';
import 'planner_models.dart';

const _alarmChannelId = 'onevault_alarms';
const _mutedChannelId = 'onevault_alarms_muted';
const _reminderChannelId = 'onevault_reminders';
const _payloadPrefix = 'reminder:';
const _soundPrefPrefix = 'reminder_sound_';
const _batteryHintKey = 'onevault_alarm_battery_hint_shown';
const _insistentFlag = 4;

const snoozeAction5 = 'snooze_5';
const snoozeAction10 = 'snooze_10';
const dismissAction = 'dismiss';

class ReminderScheduleResult {
  const ReminderScheduleResult({
    this.scheduled = false,
    this.notificationsAllowed = true,
    this.exactAlarmsAllowed = true,
    this.message,
  });

  final bool scheduled;
  final bool notificationsAllowed;
  final bool exactAlarmsAllowed;
  final String? message;
}

class ReminderAlarmActions {
  const ReminderAlarmActions({
    required this.loadPending,
    required this.advanceRecurring,
    required this.snooze,
    required this.dismiss,
  });

  final Future<List<PlannerReminder>> Function() loadPending;
  final Future<PlannerReminder> Function(int id) advanceRecurring;
  final Future<PlannerReminder> Function(int id, int minutes) snooze;
  final Future<PlannerReminder> Function(int id) dismiss;
}

@pragma('vm:entry-point')
void reminderNotificationBackground(NotificationResponse _) {}

class ReminderNotifications {
  ReminderNotifications._();

  static final ReminderNotifications instance = ReminderNotifications._();

  final FlutterLocalNotificationsPlugin _plugin = FlutterLocalNotificationsPlugin();
  bool _ready = false;
  Future<void>? _initFuture;
  bool _channelsReady = false;
  bool _restoring = false;
  bool _restoreQueued = false;
  int? _pendingTriggerId;
  String? _pendingActionId;
  int? _ringingId;
  ReminderAlarmActions? _actions;
  void Function(int reminderId)? onTriggered;

  bool get isReady => _ready;
  int? get ringingId => _ringingId;

  void attach({
    required ReminderAlarmActions actions,
    void Function(int reminderId)? onTriggered,
  }) {
    _actions = actions;
    this.onTriggered = onTriggered;
  }

  Future<void> init() {
    return _initFuture ??= _doInit();
  }

  Future<void> _doInit() async {
    try {
      tzdata.initializeTimeZones();
      await _setLocalTimezone();
      const android = AndroidInitializationSettings('@mipmap/ic_launcher');
      final ios = DarwinInitializationSettings(
        requestAlertPermission: false,
        requestBadgePermission: false,
        requestSoundPermission: false,
        notificationCategories: [
          DarwinNotificationCategory(
            'onevault_reminder_alarm',
            actions: [
              DarwinNotificationAction.plain(snoozeAction5, 'Snooze 5 min'),
              DarwinNotificationAction.plain(
                dismissAction,
                'Dismiss',
                options: {DarwinNotificationActionOption.destructive},
              ),
            ],
          ),
        ],
      );
      await _plugin.initialize(
        InitializationSettings(android: android, iOS: ios),
        onDidReceiveNotificationResponse: _onNotificationResponse,
        onDidReceiveBackgroundNotificationResponse: reminderNotificationBackground,
      );
      await _ensureChannels();
      final launch = await _plugin.getNotificationAppLaunchDetails();
      if (launch?.didNotificationLaunchApp == true) {
        _pendingTriggerId = parsePayload(launch!.notificationResponse?.payload);
        _pendingActionId = launch.notificationResponse?.actionId;
      }
      _ready = true;
    } catch (error) {
      debugPrint('ERROR Notifications unavailable: $error');
      _ready = false;
      _initFuture = null;
    }
  }

  Future<void> _setLocalTimezone() async {
    try {
      await DeviceTimeZone.init();
      tz.setLocalLocation(tz.getLocation(DeviceTimeZone.current));
    } catch (error) {
      debugPrint('ERROR Timezone fallback UTC: $error');
      tz.setLocalLocation(tz.UTC);
    }
  }

  Future<void> _ensureChannels() async {
    if (_channelsReady) return;
    final android = _plugin
        .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
    if (android == null) {
      _channelsReady = true;
      return;
    }
    await android.createNotificationChannel(
      AndroidNotificationChannel(
        _alarmChannelId,
        'OneVault Alarms',
        description: 'Alarm-style Planner reminders',
        importance: Importance.max,
        playSound: true,
        enableVibration: true,
        audioAttributesUsage: AudioAttributesUsage.alarm,
        sound: const RawResourceAndroidNotificationSound('onevault_alarm'),
      ),
    );
    await android.createNotificationChannel(
      const AndroidNotificationChannel(
        _mutedChannelId,
        'OneVault Alarms (Silent)',
        description: 'Planner alarms without sound',
        importance: Importance.high,
        playSound: false,
        enableVibration: true,
      ),
    );
    await android.createNotificationChannel(
      const AndroidNotificationChannel(
        _reminderChannelId,
        'OneVault Reminders',
        description: 'Short Planner reminders',
        importance: Importance.high,
        playSound: true,
        enableVibration: true,
      ),
    );
    _channelsReady = true;
  }

  Future<ReminderScheduleResult> ensurePermissions({bool requestExact = false}) async {
    if (!_ready) {
      return const ReminderScheduleResult(
        scheduled: false,
        notificationsAllowed: false,
        message: 'Notifications are not available on this device.',
      );
    }
    var notificationsAllowed = true;
    var exactAlarmsAllowed = true;
    final android = _plugin
        .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
    if (android != null) {
      notificationsAllowed = await android.areNotificationsEnabled() ?? true;
      if (!notificationsAllowed && requestExact) {
        notificationsAllowed = await android.requestNotificationsPermission() ?? false;
      }
      if (requestExact) {
        exactAlarmsAllowed = await android.canScheduleExactNotifications() ?? true;
        if (!exactAlarmsAllowed) {
          await android.requestExactAlarmsPermission();
          exactAlarmsAllowed = await android.canScheduleExactNotifications() ?? false;
        }
        try {
          await android.requestFullScreenIntentPermission();
        } catch (error) {
          debugPrint('ERROR Full-screen intent permission: $error');
        }
      } else {
        exactAlarmsAllowed = await android.canScheduleExactNotifications() ?? true;
      }
    }
    final ios = _plugin
        .resolvePlatformSpecificImplementation<IOSFlutterLocalNotificationsPlugin>();
    await ios?.requestPermissions(alert: true, badge: true, sound: true);
    return ReminderScheduleResult(
      notificationsAllowed: notificationsAllowed,
      exactAlarmsAllowed: exactAlarmsAllowed,
    );
  }

  Future<void> requestExactAlarmSettings() async {
    final android = _plugin
        .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
    await android?.requestExactAlarmsPermission();
  }

  Future<bool> soundEnabled(int reminderId) async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool('$_soundPrefPrefix$reminderId') ?? true;
  }

  Future<void> setSoundEnabled(int reminderId, bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('$_soundPrefPrefix$reminderId', enabled);
  }

  Future<bool> consumeBatteryHint() async {
    final prefs = await SharedPreferences.getInstance();
    if (prefs.getBool(_batteryHintKey) == true) return false;
    await prefs.setBool(_batteryHintKey, true);
    return true;
  }

  Future<ReminderScheduleResult> sync(
    PlannerReminder reminder, {
    bool requestExact = false,
  }) async {
    if (!_ready) await init();
    if (!_ready) {
      return const ReminderScheduleResult(
        scheduled: false,
        message: 'Could not schedule the alarm. The reminder was saved.',
      );
    }
    try {
      await cancel(reminder.id);
      if (reminder.status != ReminderStatus.pending) {
        return const ReminderScheduleResult(scheduled: false);
      }
      var when = reminder.when;
      if (!when.isAfter(DateTime.now())) {
        if (reminder.repeatType == RepeatType.none || _actions == null) {
          return const ReminderScheduleResult(scheduled: false);
        }
        reminder = await _advanceToFuture(reminder);
        when = reminder.when;
        if (reminder.status != ReminderStatus.pending || !when.isAfter(DateTime.now())) {
          return const ReminderScheduleResult(scheduled: false);
        }
      }

      final permissions = await ensurePermissions(requestExact: requestExact);
      if (!permissions.notificationsAllowed) {
        return ReminderScheduleResult(
          scheduled: false,
          notificationsAllowed: false,
          exactAlarmsAllowed: permissions.exactAlarmsAllowed,
          message:
              'Notification permission is disabled. The alarm may not appear or ring correctly.',
        );
      }

      await _ensureChannels();
      final playSound = await soundEnabled(reminder.id);
      final mode = permissions.exactAlarmsAllowed
          ? AndroidScheduleMode.exactAllowWhileIdle
          : AndroidScheduleMode.inexactAllowWhileIdle;
      final isAlarm = reminder.isAlarm;
      final details = NotificationDetails(
        android: _androidDetails(playSound: playSound, isAlarm: isAlarm),
        iOS: DarwinNotificationDetails(
          presentAlert: true,
          presentSound: playSound,
          presentBadge: true,
          interruptionLevel:
              isAlarm ? InterruptionLevel.timeSensitive : InterruptionLevel.active,
          categoryIdentifier: 'onevault_reminder_alarm',
          sound: playSound && isAlarm ? 'onevault_alarm.wav' : null,
        ),
      );

      await _plugin.zonedSchedule(
        reminder.id,
        reminder.title,
        reminder.description.isEmpty
            ? (isAlarm ? 'Alarm' : 'Reminder')
            : reminder.description,
        tz.TZDateTime.from(when, tz.local),
        details,
        androidScheduleMode: mode,
        payload: '$_payloadPrefix${reminder.id}',
      );
      if (!permissions.exactAlarmsAllowed) {
        return const ReminderScheduleResult(
          scheduled: true,
          exactAlarmsAllowed: false,
          message:
              'Exact alarm permission is disabled. This reminder may not ring exactly at the scheduled time.',
        );
      }
      return ReminderScheduleResult(
        scheduled: true,
        exactAlarmsAllowed: permissions.exactAlarmsAllowed,
      );
    } catch (error) {
      debugPrint('ERROR Could not schedule reminder ${reminder.id}: $error');
      return ReminderScheduleResult(
        scheduled: false,
        message: 'Could not schedule the alarm. The reminder was saved.',
      );
    }
  }

  AndroidNotificationDetails _androidDetails({
    required bool playSound,
    required bool isAlarm,
  }) {
    if (!isAlarm) {
      return AndroidNotificationDetails(
        _reminderChannelId,
        'OneVault Reminders',
        channelDescription: 'Short Planner reminders',
        importance: Importance.high,
        priority: Priority.high,
        category: AndroidNotificationCategory.reminder,
        playSound: playSound,
        enableVibration: true,
        autoCancel: true,
        actions: const [
          AndroidNotificationAction(
            snoozeAction5,
            'Snooze 5 min',
            showsUserInterface: false,
            cancelNotification: true,
          ),
          AndroidNotificationAction(
            dismissAction,
            'Done',
            cancelNotification: true,
            showsUserInterface: false,
          ),
        ],
      );
    }
    return AndroidNotificationDetails(
      playSound ? _alarmChannelId : _mutedChannelId,
      playSound ? 'OneVault Alarms' : 'OneVault Alarms (Silent)',
      channelDescription: 'Wake-up alarms',
      importance: Importance.max,
      priority: Priority.max,
      category: AndroidNotificationCategory.alarm,
      audioAttributesUsage: AudioAttributesUsage.alarm,
      fullScreenIntent: true,
      playSound: playSound,
      enableVibration: true,
      vibrationPattern: Int64List.fromList(const [0, 600, 400, 600, 400, 600]),
      sound: playSound ? const RawResourceAndroidNotificationSound('onevault_alarm') : null,
      additionalFlags: playSound ? Int32List.fromList(const [_insistentFlag]) : null,
      visibility: NotificationVisibility.public,
      ongoing: true,
      autoCancel: false,
      actions: const [
        AndroidNotificationAction(
          snoozeAction5,
          'Snooze 5 min',
          showsUserInterface: false,
          cancelNotification: true,
        ),
        AndroidNotificationAction(
          dismissAction,
          'Dismiss',
          cancelNotification: true,
          showsUserInterface: false,
        ),
      ],
    );
  }

  Future<void> cancelAllManaged() async {
    if (!_ready) return;
    try {
      final scheduled = await _plugin.pendingNotificationRequests();
      for (final item in scheduled) {
        if (item.payload?.startsWith(_payloadPrefix) == true) {
          await cancel(item.id);
        }
      }
    } catch (error) {
      debugPrint('ERROR cancelAllManaged failed: $error');
    }
  }

  Future<void> cancel(int reminderId) async {
    if (!_ready) return;
    await _plugin.cancel(reminderId);
    if (_ringingId == reminderId) _ringingId = null;
  }

  Future<void> stopRinging(int reminderId) async {
    await cancel(reminderId);
  }

  bool markRinging(int reminderId) {
    if (_ringingId == reminderId) return false;
    _ringingId = reminderId;
    return true;
  }

  void clearRinging(int reminderId) {
    if (_ringingId == reminderId) _ringingId = null;
  }

  Future<void> restorePending() async {
    await init();
    final actions = _actions;
    if (!_ready || actions == null) return;
    if (_restoring) {
      _restoreQueued = true;
      return;
    }
    _restoring = true;
    try {
      do {
        _restoreQueued = false;
        final pending = await actions.loadPending();
        final keep = <int>{};
        for (final reminder in pending) {
          final result = await sync(reminder);
          if (result.scheduled) keep.add(reminder.id);
        }
        final scheduled = await _plugin.pendingNotificationRequests();
        for (final item in scheduled) {
          final id = parsePayload(item.payload) ?? item.id;
          if (item.payload?.startsWith(_payloadPrefix) == true && !keep.contains(id)) {
            await cancel(id);
          }
        }
      } while (_restoreQueued);
    } catch (error) {
      debugPrint('ERROR Restore failed: $error');
    } finally {
      _restoring = false;
    }
  }

  Future<void> handlePendingLaunch() async {
    final id = _pendingTriggerId;
    final action = _pendingActionId;
    _pendingTriggerId = null;
    _pendingActionId = null;
    if (id == null) return;
    await _handleResponse(id, action);
  }

  static int? parsePayload(String? payload) {
    if (payload == null || payload.isEmpty) return null;
    final value = payload.startsWith(_payloadPrefix)
        ? payload.substring(_payloadPrefix.length)
        : payload;
    return int.tryParse(value);
  }

  Future<void> _onNotificationResponse(NotificationResponse response) async {
    final id = parsePayload(response.payload);
    if (id == null) return;
    await _handleResponse(id, response.actionId);
  }

  Future<void> _handleResponse(int reminderId, String? actionId) async {
    if (actionId == dismissAction) {
      await _dismissFromNotification(reminderId);
      return;
    }
    if (actionId == snoozeAction5 || actionId == snoozeAction10) {
      final minutes = actionId == snoozeAction10 ? 10 : 5;
      await _snoozeFromNotification(reminderId, minutes);
      return;
    }
    onTriggered?.call(reminderId);
  }

  Future<void> _snoozeFromNotification(int reminderId, int minutes) async {
    final actions = _actions;
    await stopRinging(reminderId);
    if (actions == null) {
      onTriggered?.call(reminderId);
      return;
    }
    try {
      final updated = await actions.snooze(reminderId, minutes);
      await sync(updated);
    } catch (error) {
      debugPrint('ERROR Snooze failed $reminderId: $error');
      onTriggered?.call(reminderId);
    }
  }

  Future<void> _dismissFromNotification(int reminderId) async {
    final actions = _actions;
    await stopRinging(reminderId);
    if (actions == null) {
      onTriggered?.call(reminderId);
      return;
    }
    try {
      final updated = await actions.dismiss(reminderId);
      await sync(updated);
    } catch (error) {
      debugPrint('ERROR Dismiss failed $reminderId: $error');
      onTriggered?.call(reminderId);
    }
  }

  Future<PlannerReminder> _advanceToFuture(PlannerReminder reminder) async {
    final actions = _actions;
    if (actions == null) return reminder;
    var current = reminder;
    var guard = 0;
    while (current.status == ReminderStatus.pending &&
        current.repeatType != RepeatType.none &&
        !current.when.isAfter(DateTime.now()) &&
        guard < 400) {
      current = await actions.advanceRecurring(current.id);
      guard++;
    }
    return current;
  }
}
