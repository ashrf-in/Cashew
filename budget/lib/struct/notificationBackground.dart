import 'dart:async';
import 'dart:ui';

import 'package:budget/database/tables.dart';
import 'package:budget/firebase_options.dart';
import 'package:budget/pages/autoTransactionsPageEmail.dart';
import 'package:budget/struct/currencyFunctions.dart';
import 'package:budget/struct/databaseGlobal.dart';
import 'package:budget/struct/initializeNotifications.dart';
import 'package:budget/struct/notificationsGlobal.dart';
import 'package:budget/struct/settings.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';

const MethodChannel _backgroundNotificationChannel =
    MethodChannel('com.budget.tracker_app/notification_background');

bool _backgroundNotificationRuntimeInitialized = false;

Future<void> runNotificationBackgroundMain() async {
  WidgetsFlutterBinding.ensureInitialized();
  DartPluginRegistrant.ensureInitialized();
  await _ensureBackgroundNotificationRuntimeInitialized();
  print('Notification background entrypoint initialized');

  _backgroundNotificationChannel.setMethodCallHandler(
    _handleBackgroundNotificationMethodCall,
  );
  await _backgroundNotificationChannel.invokeMethod('backgroundReady');
  await Completer<void>().future;
}

Future<void> _ensureBackgroundNotificationRuntimeInitialized() async {
  if (_backgroundNotificationRuntimeInitialized) {
    return;
  }

  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );
  sharedPreferences = await SharedPreferences.getInstance();
  database = await constructDb('db');
  notificationPayload = await initializeNotifications();
  await loadCurrencyJSON();
  await initializeSettings();

  _backgroundNotificationRuntimeInitialized = true;
}

Future<void> _handleBackgroundNotificationMethodCall(MethodCall call) async {
  if (call.method != 'handleNotification') {
    throw MissingPluginException(
      'Unknown notification background method: ${call.method}',
    );
  }

  final Map<dynamic, dynamic> event =
      (call.arguments as Map<dynamic, dynamic>? ?? <dynamic, dynamic>{});
  print(
    'Processing background notification from '
    '${event['packageName']} with title ${event['title']}',
  );
  await processIncomingNotificationEvent(
    packageName: event['packageName']?.toString(),
    title: event['title']?.toString(),
    content: event['content']?.toString(),
    hasRemoved: event['hasRemoved'] == true,
    receivedAt: DateTime.now(),
  );
}