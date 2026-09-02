// screens/notifications_screen.dart
// In-app notification center — lists persisted app events (orders, stock,
// payments), with mark-all-read and clear-all. Works on mobile, web, desktop.

import 'package:flutter/material.dart';
import '../services/notification_service.dart';

class NotificationsScreen extends StatelessWidget {
  const NotificationsScreen({Key? key}) : super(key: key);

  Color _typeColor(NotificationType type) {
    switch (type) {
      case NotificationType.order:
        return Colors.green;
      case NotificationType.stock:
        return Colors.orange;
      case NotificationType.payment:
        return Colors.blue;
      case NotificationType.reminder:
        return Colors.purple;
    }
  }

  IconData _typeIcon(NotificationType type) {
    switch (type) {
      case NotificationType.order:
        return Icons.receipt_long;
      case NotificationType.stock:
        return Icons.inventory_2_outlined;
      case NotificationType.payment:
        return Icons.payments_outlined;
      case NotificationType.reminder:
        return Icons.alarm;
    }
  }

  String _timeAgo(DateTime time) {
    final diff = DateTime.now().difference(time);
    if (diff.inMinutes < 1) return 'Just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    if (diff.inDays < 7) return '${diff.inDays}d ago';
    return '${time.day}/${time.month}/${time.year}';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final service = NotificationService();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Notifications'),
        elevation: 4,
        actions: [
          ListenableBuilder(
            listenable: service,
            builder: (context, _) {
              return IconButton(
                tooltip: 'Clear all',
                icon: const Icon(Icons.delete_sweep_outlined),
                onPressed:
                    service.notifications.isNotEmpty ? service.clearAll : null,
              );
            },
          ),
        ],
      ),
      body: ListenableBuilder(
        listenable: service,
        builder: (context, _) {
          final items = service.notifications;
          if (items.isEmpty) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.notifications_off_outlined,
                      size: 64, color: theme.hintColor),
                  const SizedBox(height: 16),
                  Text('No notifications yet',
                      style: theme.textTheme.titleMedium),
                  const SizedBox(height: 8),
                  Text('Orders, stock alerts and payments will appear here',
                      style: TextStyle(color: theme.hintColor, fontSize: 12)),
                ],
              ),
            );
          }

          final unread = service.unreadCount;
          return Column(
            children: [
              if (unread > 0)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                  child: Row(
                    children: [
                      Text('$unread unread',
                          style: TextStyle(
                              color: theme.primaryColor,
                              fontWeight: FontWeight.bold)),
                      const Spacer(),
                      TextButton.icon(
                        onPressed: service.markAllRead,
                        icon: const Icon(Icons.done_all, size: 18),
                        label: const Text('Mark all read'),
                      ),
                    ],
                  ),
                ),
              Expanded(child: _buildList(theme, items)),
            ],
          );
        },
      ),
    );
  }

  Widget _buildList(ThemeData theme, List<AppNotification> items) {
    final service = NotificationService();
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: items.length,
      itemBuilder: (context, index) {
        final n = items[index];
        final color = _typeColor(n.type);
        return Card(
          margin: const EdgeInsets.only(bottom: 10),
          elevation: n.isRead ? 1 : 3,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          child: ListTile(
            leading: CircleAvatar(
              backgroundColor:
                  n.isRead ? color.withValues(alpha: 0.15) : color,
              child: Icon(_typeIcon(n.type),
                  color: n.isRead ? color : Colors.white, size: 20),
            ),
            title: Text(n.title,
                style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                    color: n.isRead
                        ? theme.hintColor
                        : theme.textTheme.bodyLarge?.color)),
            subtitle: Text(n.message,
                style: TextStyle(
                    fontSize: 12,
                    color: n.isRead
                        ? theme.hintColor
                        : theme.textTheme.bodyMedium?.color)),
            trailing: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(_timeAgo(n.time),
                    style: TextStyle(fontSize: 10, color: theme.hintColor)),
                if (!n.isRead)
                  Container(
                    margin: const EdgeInsets.only(top: 4),
                    width: 8,
                    height: 8,
                    decoration:
                        BoxDecoration(color: color, shape: BoxShape.circle),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }
}
