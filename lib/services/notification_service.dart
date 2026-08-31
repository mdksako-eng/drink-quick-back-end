// services/notification_service.dart
import 'package:flutter/material.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:drinks_calculator_fixed/utils/currency_helper.dart';

class NotificationService {
  static final NotificationService _instance = NotificationService._internal();
  factory NotificationService() => _instance;
  NotificationService._internal();

  final FlutterTts _tts = FlutterTts();
  final List<AppNotification> _notifications = [];

  List<AppNotification> get notifications => _notifications;
  int get unreadCount => _notifications.where((n) => !n.isRead).length;

  Future<void> initialize() async {
    await _tts.setLanguage('en-US');
    await _tts.setSpeechRate(0.5);
  }

  void _addNotification(AppNotification notification) {
    _notifications.insert(0, notification);
    if (_notifications.length > 50) {
      _notifications.removeLast();
    }
  }

  void showOrderCreated({required String orderId, required int itemCount, required double totalAmount}) {
    _addNotification(AppNotification(title: '🛒 New Order', message: '$itemCount items - ${CurrencyHelper.format(totalAmount)}', type: NotificationType.order));
    _speak('New order with $itemCount items');
  }

  void showOrderCompleted({required String orderId, required String customerName, required double totalAmount, required String paymentMethod}) {
    _addNotification(AppNotification(title: '✅ Order Done', message: '$customerName - ${CurrencyHelper.format(totalAmount)} via $paymentMethod', type: NotificationType.order));
    _speak('Order completed for $customerName');
  }

  void showLowStockAlert({required String drinkName, required int currentStock, required int minStockLevel}) {
    _addNotification(AppNotification(title: '⚠️ Low Stock', message: '$drinkName: $currentStock left (Min: $minStockLevel)', type: NotificationType.stock));
    _speak('Low stock alert for $drinkName');
  }

  void showOutOfStockAlert({required String drinkName}) {
    _addNotification(AppNotification(title: '🚫 Out of Stock', message: '$drinkName is out of stock!', type: NotificationType.stock));
    _speak('$drinkName is out of stock');
  }

  void showStockRestocked({required String drinkName, required int quantity, required int newTotal}) {
    _addNotification(AppNotification(title: '📦 Restocked', message: '$drinkName: +$quantity (Total: $newTotal)', type: NotificationType.stock));
  }

  void showPaymentReceived({required String customerName, required double amount, required String paymentMethod}) {
    _addNotification(AppNotification(title: '💵 Payment', message: '$customerName paid ${CurrencyHelper.format(amount)} via $paymentMethod', type: NotificationType.payment));
    _speak('Payment received from $customerName');
  }

  void showPaymentFailed({required String reason, required String paymentMethod}) {
    _addNotification(AppNotification(title: '❌ Failed', message: '$paymentMethod: $reason', type: NotificationType.payment));
    _speak('Payment failed');
  }

  Future<void> _speak(String text) async {
    try { await _tts.speak(text); } catch (e) { print('TTS: $e'); }
  }

  void markAllRead() { for (final n in _notifications) { n.isRead = true; } }
  void clearAll() { _notifications.clear(); }
  void dispose() { _tts.stop(); _notifications.clear(); }
}

class AppNotification {
  final String title;
  final String message;
  final NotificationType type;
  final DateTime time;
  bool isRead;

  AppNotification({required this.title, required this.message, required this.type, DateTime? time, this.isRead = false}) : time = time ?? DateTime.now();
}

enum NotificationType { order, stock, payment, reminder }