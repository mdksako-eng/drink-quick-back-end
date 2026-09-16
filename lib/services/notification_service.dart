// services/notification_service.dart
// In-app notification center: persists to SharedPreferences, notifies
// listeners (bell badge updates live), and speaks announcements with a
// platform-correct TTS (browser SpeechSynthesis on web, flutter_tts natively).

import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:drinks_calculator_fixed/config/api_config.dart';
import 'package:drinks_calculator_fixed/services/secure_storage_service.dart';
import 'package:drinks_calculator_fixed/services/supabase_service.dart';
import 'package:drinks_calculator_fixed/utils/currency_helper.dart';
import 'package:drinks_calculator_fixed/services/tts/tts_factory.dart'
    as tts;
import 'package:drinks_calculator_fixed/services/os_notifications/os_notifications_factory.dart'
    as osn;
import 'package:drinks_calculator_fixed/services/voice_service.dart';

class NotificationService extends ChangeNotifier {
  static final NotificationService _instance = NotificationService._internal();
  factory NotificationService() => _instance;
  NotificationService._internal();

  static const String _storageKey = 'app_notifications';
  static const String _soundEnabledKey = 'show_notifications';
  static const int _maxNotifications = 50;

  /// Notifications older than this are deleted automatically (2 months).
  static const int _maxAgeDays = 60;

  final List<AppNotification> _notifications = [];
  bool _initialized = false;
  bool _soundEnabled = true;

  List<AppNotification> get notifications => List.unmodifiable(_notifications);
  int get unreadCount => _notifications.where((n) => !n.isRead).length;
  bool get isInitialized => _initialized;

  Future<void> initialize() async {
    if (_initialized) return;
    _initialized = true;

    await tts.platformInitTts();
    await osn.osNotificationsInit();

    try {
      final prefs = await SharedPreferences.getInstance();
      _soundEnabled = prefs.getBool(_soundEnabledKey) ?? true;
      final raw = prefs.getString(_storageKey);
      if (raw != null && raw.isNotEmpty) {
        final list = jsonDecode(raw) as List<dynamic>;
        _notifications
          ..clear()
          ..addAll(list
              .map((e) => AppNotification.fromJson(Map<String, dynamic>.from(e)))
              .toList());
      }
    } catch (e) {
      debugPrint('⚠️ Notification history load failed: $e');
    }
    _pruneOld(); // 🧹 drop anything older than 2 months
    notifyListeners();
  }

  /// Honors the "Show Notifications" setting in Storage Settings for voice.
  Future<void> setSoundEnabled(bool enabled) async {
    _soundEnabled = enabled;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_soundEnabledKey, enabled);
    } catch (_) {}
    notifyListeners();
  }

  void _addNotification(AppNotification notification) {
    _notifications.insert(0, notification);
    if (_notifications.length > _maxNotifications) {
      _notifications.removeLast();
    }
    _persist();
    notifyListeners();
    // ☁️ Keep a per-user copy online so the history survives a reinstall.
    _pushToServer(notification);
  }

  Future<void> _persist() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_storageKey,
          jsonEncode(_notifications.map((n) => n.toJson()).toList()));
    } catch (e) {
      debugPrint('⚠️ Notification history save failed: $e');
    }
  }

  void showOrderCreated({required String orderId, required int itemCount, required double totalAmount}) {
    _addNotification(AppNotification(title: '🛒 New Order', message: '$itemCount items - ${CurrencyHelper.format(totalAmount)}', type: NotificationType.order));
    _speak('New order with $itemCount items');
    osn.osShowNotification('order_created', '🛒 New Order', '$itemCount items - ${CurrencyHelper.format(totalAmount)}');
  }

  void showOrderCompleted({required String orderId, required String customerName, required double totalAmount, required String paymentMethod}) {
    _addNotification(AppNotification(title: '✅ Order Done', message: '$customerName - ${CurrencyHelper.format(totalAmount)} via $paymentMethod', type: NotificationType.order));
    _speak('Order completed for $customerName');
    osn.osShowNotification('order_completed', '✅ Order Done', '$customerName - ${CurrencyHelper.format(totalAmount)} via $paymentMethod');
  }

  void showLowStockAlert({required String drinkName, required int currentStock, required int minStockLevel}) {
    _addNotification(AppNotification(title: '⚠️ Low Stock', message: '$drinkName: $currentStock left (Min: $minStockLevel)', type: NotificationType.stock));
    _speak('Low stock alert for $drinkName');
    osn.osShowNotification('low_stock', '⚠️ Low Stock', '$drinkName: $currentStock left (Min: $minStockLevel)');
  }

  void showOutOfStockAlert({required String drinkName}) {
    _addNotification(AppNotification(title: '🚫 Out of Stock', message: '$drinkName is out of stock!', type: NotificationType.stock));
    _speak('$drinkName is out of stock');
    osn.osShowNotification('out_of_stock', '🚫 Out of Stock', '$drinkName is out of stock!');
  }

  void showStockRestocked({required String drinkName, required int quantity, required int newTotal}) {
    _addNotification(AppNotification(title: '📦 Restocked', message: '$drinkName: +$quantity (Total: $newTotal)', type: NotificationType.stock));
    osn.osShowNotification('restocked', '📦 Restocked', '$drinkName: +$quantity (Total: $newTotal)');
  }

  void showPaymentReceived({required String customerName, required double amount, required String paymentMethod}) {
    _addNotification(AppNotification(title: '💵 Payment', message: '$customerName paid ${CurrencyHelper.format(amount)} via $paymentMethod', type: NotificationType.payment));
    _speak('Payment received from $customerName');
    osn.osShowNotification('payment', '💵 Payment', '$customerName paid ${CurrencyHelper.format(amount)} via $paymentMethod');
  }

  void showPaymentFailed({required String reason, required String paymentMethod}) {
    _addNotification(AppNotification(title: '❌ Payment Failed', message: '$paymentMethod: $reason', type: NotificationType.payment));
    _speak('Payment failed');
    osn.osShowNotification('payment_failed', '❌ Payment Failed', '$paymentMethod: $reason');
  }

  /// Surface server-sync failures to the user so they don't assume data saved.
  void showSyncFailed({required String action, required String detail}) {
    _addNotification(AppNotification(
      title: '⚠️ Sync Failed',
      message: '$action failed to reach the server. Data is saved on this device only and will not appear for other staff: $detail',
      type: NotificationType.system,
    ));
    _speak('Warning: sync failed. Data saved locally only');
    osn.osShowNotification('sync_failed', '⚠️ Sync Failed', '$action failed — saved on this device only: $detail');
  }

  Future<void> _speak(String text) async {
    if (!_soundEnabled) return;
    if (!VoiceService.voiceEnabled) return; // 🌐 global app-wide voice switch (AI screen toggle)
    try {
      await tts.platformSpeak(text);
    } catch (e) {
      debugPrint('🔇 TTS unavailable: $e');
    }
  }

void markAllRead() {
    for (final n in _notifications) {
      n.isRead = true;
    }
    _persist();
    notifyListeners();
    _markAllReadOnServer();
  }

  /// Marks one notification as read (called when the user taps it) — locally
  /// and on the server so the state follows the user across devices.
  void markAsRead(String id) {
    final index = _notifications.indexWhere((n) => n.id == id);
    if (index == -1) return;
    if (_notifications[index].isRead) return;
    _notifications[index].isRead = true;
    _persist();
    notifyListeners();
    _patchReadOnServer(id, true);
  }

  void toggleRead(String id) {
    final index = _notifications.indexWhere((n) => n.id == id);
    if (index == -1) return;
    final newValue = !_notifications[index].isRead;
    _notifications[index].isRead = newValue;
    _persist();
    notifyListeners();
    _patchReadOnServer(id, newValue);
  }

  Future<void> deleteNotification(String id) async {
    _notifications.removeWhere((n) => n.id == id);
    _persist();
    notifyListeners();
    if (!SupabaseService.canUseSupabase) return;
    try {
      await http.delete(
        Uri.parse('${ApiConfig.dataNotifications}/${Uri.encodeComponent(id)}'),
        headers: await _authedHeaders(),
      );
    } catch (e) {
      debugPrint('⚠️ Notification delete sync failed: $e');
    }
  }

  // ============================================================
  // ☁️ ONLINE SYNC (per user) + 🧹 2-month retention
  // ============================================================

  /// Drops notifications older than [_maxAgeDays] (2 months).
  void _pruneOld() {
    final cutoff = DateTime.now().subtract(const Duration(days: _maxAgeDays));
    final before = _notifications.length;
    _notifications.removeWhere((n) => n.time.isBefore(cutoff));
    if (_notifications.length != before) {
      debugPrint('🧹 Pruned ${before - _notifications.length} old notifications');
    }
  }

  /// Loads this user's notifications from the server and merges them with the
  /// local cache (deduplicating by id, newest first).
  Future<void> syncWithServer() async {
    if (!SupabaseService.canUseSupabase) return;
    try {
      final response = await http.get(
        Uri.parse(ApiConfig.dataNotifications),
        headers: await _authedHeaders(),
      );
      if (response.statusCode != 200) return;

      final rows = List<Map<String, dynamic>>.from(jsonDecode(response.body));
      final byId = <String, AppNotification>{
        for (final n in _notifications) n.id: n,
      };

      for (final row in rows) {
        final id = row['id']?.toString();
        if (id == null || id.isEmpty) continue;
        final remote = AppNotification(
          id: id,
          title: row['title']?.toString() ?? '',
          message: row['message']?.toString() ?? '',
          type: NotificationType.values.firstWhere(
            (t) => t.name == row['type']?.toString(),
            orElse: () => NotificationType.system,
          ),
          time: DateTime.tryParse('${row['created_at']}') ?? DateTime.now(),
          isRead: row['is_read'] == true,
        );
        final local = byId[id];
        byId[id] = remote;
        // Keep local-only rows that were never pushed (state is local truth).
        if (local != null && local.isRead && !remote.isRead) {
          remote.isRead = true;
          _patchReadOnServer(id, true);
        }
      }

      _notifications
        ..clear()
        ..addAll(byId.values);
      _notifications.sort((a, b) => b.time.compareTo(a.time));
      _pruneOld();
      _persist();
      notifyListeners();
    } catch (e) {
      debugPrint('⚠️ Notification sync failed: $e');
    }
  }

  Future<Map<String, String>> _authedHeaders() async {
    final token = await SecureStorageService.getSessionToken();
    return {
      'Content-Type': 'application/json',
      if (token != null && token.isNotEmpty) 'Authorization': 'Bearer $token',
    };
  }

  Future<void> _pushToServer(AppNotification n) async {
    if (!SupabaseService.canUseSupabase) return;
    try {
      await http.post(
        Uri.parse(ApiConfig.dataNotifications),
        headers: await _authedHeaders(),
        body: jsonEncode({
          'id': n.id,
          'title': n.title,
          'message': n.message,
          'type': n.type.name,
          'created_at': n.time.toIso8601String(),
        }),
      );
    } catch (e) {
      debugPrint('⚠️ Notification push failed: $e');
    }
  }

  Future<void> _patchReadOnServer(String id, bool isRead) async {
    if (!SupabaseService.canUseSupabase) return;
    try {
      await http.patch(
        Uri.parse('${ApiConfig.dataNotifications}/${Uri.encodeComponent(id)}'),
        headers: await _authedHeaders(),
        body: jsonEncode({'is_read': isRead}),
      );
    } catch (e) {
      debugPrint('⚠️ Notification read sync failed: $e');
    }
  }

  Future<void> _markAllReadOnServer() async {
    if (!SupabaseService.canUseSupabase) return;
    try {
      await http.patch(
        Uri.parse('${ApiConfig.dataNotifications}/read-all'),
        headers: await _authedHeaders(),
      );
    } catch (e) {
      debugPrint('⚠️ Notification read-all sync failed: $e');
    }
  }

  void clearAll() {
    _notifications.clear();
    _persist();
    notifyListeners();
  }

  @override
  void dispose() {
    tts.platformStopTts();
    super.dispose();
  }
}

class AppNotification {
  /// Stable id (also used as the primary key online) so the same notification
  /// can be deduplicated between the device and the server.
  final String id;
  final String title;
  final String message;
  final NotificationType type;
  final DateTime time;
  bool isRead;

  AppNotification({
    String? id,
    required this.title,
    required this.message,
    required this.type,
    DateTime? time,
    this.isRead = false,
  })  : id = id ?? 'n_${DateTime.now().microsecondsSinceEpoch}',
        time = time ?? DateTime.now();

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'message': message,
        'type': type.name,
        'time': time.toIso8601String(),
        'isRead': isRead,
      };

  factory AppNotification.fromJson(Map<String, dynamic> json) => AppNotification(
        id: json['id']?.toString() ??
            'n_${DateTime.tryParse('${json['time']}')?.microsecondsSinceEpoch ?? DateTime.now().microsecondsSinceEpoch}',
        title: json['title']?.toString() ?? '',
        message: json['message']?.toString() ?? '',
        type: NotificationType.values.firstWhere(
          (t) => t.name == json['type'],
          orElse: () => NotificationType.order,
        ),
        time: DateTime.tryParse('${json['time']}') ?? DateTime.now(),
        isRead: json['isRead'] == true,
      );
}

enum NotificationType { order, stock, payment, reminder, system }
