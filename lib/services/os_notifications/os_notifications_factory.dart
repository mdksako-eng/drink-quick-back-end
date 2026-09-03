// services/os_notifications/os_notifications_factory.dart
// Platform-correct OS notifications: flutter_local_notifications on native
// (Android/iOS/macOS/Windows/Linux), a no-op on web (the in-app center handles
// web). Conditional export is resolved at compile time.

export 'os_notifications_stub.dart'
    if (dart.library.io) 'os_notifications_io.dart';