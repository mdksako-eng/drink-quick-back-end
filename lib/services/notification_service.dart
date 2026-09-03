// services/notification_service.dart
// In-app notification center: persists to SharedPreferences, notifies
// listeners (bell badge updates live), and speaks announcements with a
// platform-correct TTS (browser SpeechSynthesis on web, flutter_tts natively).

import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:drinks_calculator_fixed/utils/currency_helper.dart';
import 'package:drinks_calculator_fixed/services/tts/tts_factory.dart'
    as tts;
import 'package:drinks_calculator_fixed/services/os_notifications/os_notifications_factory.dart'
    as osn;

class NotificationService extends ChangeNotifier {
  static final NotificationService _instance = NotificationService._internal();
  factory NotificationService() => _instance;
  NotificationService._internal();

  static const String _storageKey = 'app_notifications';
  static const String _soundEnabledKey = 'show_notifications';
  static const int _maxNotifications = 50;

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

  Future<void> _speak(String text) async {
    if (!_soundEnabled) return;
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
  final String title;
  final String message;
  final NotificationType type;
  final DateTime time;
  bool isRead;

  AppNotification({required this.title, required this.message, required this.type, DateTime? time, this.isRead = false}) : time = time ?? DateTime.now();

  Map<String, dynamic> toJson() => {
        'title': title,
        'message': message,
        'type': type.name,
        'time': time.toIso8601String(),
        'isRead': isRead,
      };

  factory AppNotification.fromJson(Map<String, dynamic> json) => AppNotification(
        title: json['title']?.toString() ?? '',
        message: json['message']?.toString() ?? '',
        type: NotificationType.values.firstWhere(
          (t) => t.name == json['type'],
          orElse: () => NotificationType.order,
        ),
        time: DateTime.tryParse('${json['time']}'),
        isRead: json['isRead'] == true,
      );
}

enum NotificationType { order, stock, payment, reminder }