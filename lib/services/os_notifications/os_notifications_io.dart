// services/os_notifications/os_notifications_io.dart
// OS notification support via flutter_local_notifications.
// Not supported on web — that platform uses the fallback stub.
// ignore: avoid_web_libraries_in_flutter, unused_import
import 'dart:io' show Platform;
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

final FlutterLocalNotificationsPlugin _plugin =
    FlutterLocalNotificationsPlugin();
bool _initialized = false;

Future<void> osNotificationsInit() async {
  if (_initialized) return;
  _initialized = true;

  const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');
  // macOS requires a small data set on first request.
  const darwinInit = DarwinInitializationSettings(
    requestAlertPermission: false,
    requestBadgePermission: false,
    requestSoundPermission: false,
  );
  const settings =
      InitializationSettings(android: androidInit, iOS: darwinInit, macOS: darwinInit);

  await _plugin.initialize(settings);

  // Android 13+ requires runtime permission for notifications
  if (Platform.isAndroid) {
    try {
      await _plugin.resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>()?.requestNotificationsPermission();
    } catch (_) {}
  }
}

Future<void> osShowNotification(String id, String title, String body) async {
  if (!_initialized) return;
  try {
    const androidDetails = AndroidNotificationDetails(
      'drink_quick_cal',
      'Drink Quick Cal',
      channelDescription: 'Orders, stock and payment notifications',
      importance: Importance.high,
      priority: Priority.high,
      autoCancel: true,
    );
    const iosDetails = DarwinNotificationDetails(
      presentAlert: true,
      presentBadge: true,
      presentSound: true,
    );
    const details = NotificationDetails(
        android: androidDetails, iOS: iosDetails, macOS: iosDetails);

    final notificationId = int.tryParse(id) ?? (id.hashCode & 0x7fffffff);
    await _plugin.show(notificationId, title, body, details);
  } catch (e) {
    // Non-fatal — in-app center still shows it
  }
}