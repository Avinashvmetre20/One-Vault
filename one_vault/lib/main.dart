import 'package:flutter/material.dart';

import 'app/app.dart';
import 'features/planner/data/reminder_notifications.dart';

export 'app/app.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await ReminderNotifications.instance.init();
  runApp(const MyApp());
}
