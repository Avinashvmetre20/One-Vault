import 'package:flutter/material.dart';

import 'app/app.dart';
import 'core/network/api_config.dart';
import 'features/planner/data/reminder_notifications.dart';

export 'app/app.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  debugPrint('API: ${ApiConfig.baseUrl}');
  await ReminderNotifications.instance.init();
  runApp(const MyApp());
}
