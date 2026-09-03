// services/os_notifications/os_notifications_stub.dart
// Default (unimplemented) OS notification bindings — web has no local
// notification plugin support, so this no-ops there.

Future<void> osNotificationsInit() async {}

Future<void> osShowNotification(String id, String title, String body) async {}