// services/notification_service.dart
// In-app notification center. DEVICE-ONLY BY DESIGN: the history lives in
// SharedPreferences on this device and is never written to Supabase or sent
// to the backend. It notifies listeners (bell badge updates live) and speaks
// announcements with a platform-correct TTS (browser SpeechSynthesis on web,
// flutter_tts natively).

import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:drinks_calculator_fixed/utils/currency_helper.dart';
import 'package:drinks_calculator_fixed/utils/i18n.dart';
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
    final title = '🛒 ${t('notifNewOrderTitle')}';
    final message =
        '$itemCount ${t('invItems')} - ${CurrencyHelper.format(totalAmount)}';
    _addNotification(AppNotification(title: title, message: message, type: NotificationType.order));
    _speak('${t('notifNewOrderSpoken')} $itemCount ${t('invItems')}');
    osn.osShowNotification('order_created', title, message);
  }

  void showOrderCompleted({required String orderId, required String customerName, required double totalAmount, required String paymentMethod}) {
    final title = '✅ ${t('notifOrderDoneTitle')}';
    final message =
        '$customerName - ${CurrencyHelper.format(totalAmount)} ${t('notifVia')} $paymentMethod';
    _addNotification(AppNotification(title: title, message: message, type: NotificationType.order));
    _speak('${t('notifOrderCompletedSpoken')} $customerName');
    osn.osShowNotification('order_completed', title, message);
  }

  void showLowStockAlert({required String drinkName, required int currentStock, required int minStockLevel}) {
    final title = '⚠️ ${t('notifLowStockTitle')}';
    final message =
        '$drinkName: $currentStock ${t('notifLeft')} (${t('notifMin')} $minStockLevel)';
    _addNotification(AppNotification(title: title, message: message, type: NotificationType.stock));
    _speak('${t('notifLowStockSpoken')} $drinkName');
    osn.osShowNotification('low_stock', title, message);
  }

  void showOutOfStockAlert({required String drinkName}) {
    final title = '🚫 ${t('notifOutOfStockTitle')}';
    final message = '$drinkName ${t('notifOutOfStock')}';
    _addNotification(AppNotification(title: title, message: message, type: NotificationType.stock));
    _speak(message);
    osn.osShowNotification('out_of_stock', title, message);
  }

  void showStockRestocked({required String drinkName, required int quantity, required int newTotal}) {
    final title = '📦 ${t('invRestocked')}';
    final message = '$drinkName: +$quantity (${t('total')}: $newTotal)';
    _addNotification(AppNotification(title: title, message: message, type: NotificationType.stock));
    osn.osShowNotification('restocked', title, message);
  }

  void showPaymentReceived({required String customerName, required double amount, required String paymentMethod}) {
    final title = '💵 ${t('notifPaymentTitle')}';
    final message =
        '$customerName ${t('notifPaid')} ${CurrencyHelper.format(amount)} ${t('notifVia')} $paymentMethod';
    _addNotification(AppNotification(title: title, message: message, type: NotificationType.payment));
    _speak('${t('notifPaymentReceivedSpoken')} $customerName');
    osn.osShowNotification('payment', title, message);
  }

  void showPaymentFailed({required String reason, required String paymentMethod}) {
    final title = '❌ ${t('notifPaymentFailedTitle')}';
    final message = '$paymentMethod: $reason';
    _addNotification(AppNotification(title: title, message: message, type: NotificationType.payment));
    _speak(t('notifPaymentFailedSpoken'));
    osn.osShowNotification('payment_failed', title, message);
  }

  /// Warns that a batch is about to expire (or already has), including the
  /// expected demand for the coming days so the stock can be pushed first.
  void showExpirySoon({
    required String drinkName,
    required int daysLeft,
    required bool expired,
    double forecastDemand = 0,
    int recommendedOrder = 0,
  }) {
    final when = expired
        ? t('notifExpired')
        : daysLeft == 0
            ? t('notifExpiresToday')
            : '${t('notifExpiresInDays')} $daysLeft '
                '${daysLeft == 1 ? t('notifDaySingle') : t('forecastDays')}';
    final demand = forecastDemand > 0
        ? ' - ${t('notifExpectedDemand')} ${forecastDemand.toStringAsFixed(1)}'
        : '';
    final order =
        recommendedOrder > 0 ? ' - ${t('notifOrderWord')} $recommendedOrder' : '';
    final message = '$drinkName $when$demand$order';
    final title =
        expired ? t('notifExpiredStockTitle') : t('notifExpiringSoonTitle');

    _addNotification(AppNotification(
      title: title,
      message: message,
      type: NotificationType.reminder,
    ));
    // Spoken wording follows the notification body so both read the same.
    _speak('$drinkName $when');
    osn.osShowNotification(
        expired ? 'stock_expired' : 'stock_expiring', title, message);
  }

  /// Surface server-sync failures to the user so they don't assume data saved.
  void showSyncFailed({required String action, required String detail}) {
    final title = '⚠️ ${t('notifSyncFailedTitle')}';
    _addNotification(AppNotification(
      title: title,
      message: '$action ${t('notifSyncBody')} $detail',
      type: NotificationType.system,
    ));
    _speak(t('notifSyncFailedSpoken'));
    osn.osShowNotification(
        'sync_failed', title, '$action ${t('notifSyncShortBody')} $detail');
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

  /// Marks every notification as read (device only).
  void markAllRead() {
    for (final n in _notifications) {
      n.isRead = true;
    }
    _persist();
    notifyListeners();
  }

  /// Marks one notification as read (called when the user taps it).
  /// The read state is kept on this device only.
  void markAsRead(String id) {
    final index = _notifications.indexWhere((n) => n.id == id);
    if (index == -1) return;
    if (_notifications[index].isRead) return;
    _notifications[index].isRead = true;
    _persist();
    notifyListeners();
  }

  /// Flips the read state of one notification (device only).
  void toggleRead(String id) {
    final index = _notifications.indexWhere((n) => n.id == id);
    if (index == -1) return;
    _notifications[index].isRead = !_notifications[index].isRead;
    _persist();
    notifyListeners();
  }

  /// Removes a notification from this device history (device only).
  Future<void> deleteNotification(String id) async {
    _notifications.removeWhere((n) => n.id == id);
    _persist();
    notifyListeners();
  }

  /// Drops notifications older than [_maxAgeDays] (2 months).
  void _pruneOld() {
    final cutoff = DateTime.now().subtract(const Duration(days: _maxAgeDays));
    final before = _notifications.length;
    _notifications.removeWhere((n) => n.time.isBefore(cutoff));
    if (_notifications.length != before) {
      debugPrint('🧹 Pruned ${before - _notifications.length} old notifications');
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
