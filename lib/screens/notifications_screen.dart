// screens/notifications_screen.dart
// In-app notification center — lists persisted app events (orders, stock,
// payments), with mark-all-read and clear-all. Works on mobile, web, desktop.

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:drinks_calculator_fixed/providers/plan_provider.dart';
import '../widgets/upgrade_required.dart';
import '../services/notification_service.dart';
import '../utils/i18n.dart';

class NotificationsScreen extends StatefulWidget {
  const NotificationsScreen({Key? key}) : super(key: key);

  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  /// Notifications the user opened (reveals the brief view + marks them read).
  final Set<String> _expandedIds = {};

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
      case NotificationType.system:
        return Colors.redAccent;
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
      case NotificationType.system:
        return Icons.error_outline;
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
    if (!context.read<PlanProvider>().canAccess('inbox')) {
      return const UpgradeRequiredView();
    }
    final theme = Theme.of(context);
    final service = NotificationService();

    return Scaffold(
      appBar: AppBar(
        title: Text(t('notifications')),
        elevation: 4,
        actions: [
          ListenableBuilder(
            listenable: service,
            builder: (context, _) {
              return IconButton(
                tooltip: t('clearAll'),
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
                  Text(t('noNotificationsYet'),
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
                      Text('$unread ${t('unreadCount')}',
                          style: TextStyle(
                              color: theme.primaryColor,
                              fontWeight: FontWeight.bold)),
                      const Spacer(),
                      TextButton.icon(
                        onPressed: service.markAllRead,
                        icon: const Icon(Icons.done_all, size: 18),
                        label: Text(t('markAllRead')),
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
        final expanded = _expandedIds.contains(n.id);
        return Card(
          margin: const EdgeInsets.only(bottom: 10),
          elevation: n.isRead ? 1 : 3,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          child: Column(children: [
            ListTile(
            onTap: () {
              // 👆 Opening a notification marks it read and reveals the detail.
              service.markAsRead(n.id);
              setState(() {
                if (expanded) {
                  _expandedIds.remove(n.id);
                } else {
                  _expandedIds.add(n.id);
                }
              });
            },
            onLongPress: () => _confirmDelete(n),
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
                maxLines: expanded ? null : 2,
                overflow:
                    expanded ? TextOverflow.visible : TextOverflow.ellipsis,
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
                Icon(expanded ? Icons.expand_less : Icons.expand_more,
                    size: 18, color: theme.hintColor),
              ],
            ),
            ),
            // 📄 Brief view of the opened notification (exact time + actions).
            if (expanded) _buildExpandedDetail(theme, service, n),
          ]),
        );
      },
    );
  }

  Widget _buildExpandedDetail(
      ThemeData theme, NotificationService service, AppNotification n) {
    return Padding(
      padding: const EdgeInsets.only(left: 16, right: 16, bottom: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Divider(height: 12),
          Row(children: [
            Icon(Icons.schedule, size: 13, color: theme.hintColor),
            const SizedBox(width: 6),
            Text(_fullTime(n.time),
                style: TextStyle(fontSize: 11, color: theme.hintColor)),
            const Spacer(),
            TextButton.icon(
              icon: const Icon(Icons.done_all, size: 15),
              label: Text(n.isRead ? t('notifMarkUnread') : t('notifMarkRead'),
                  style: const TextStyle(fontSize: 12)),
              onPressed: () => service.toggleRead(n.id),
            ),
            IconButton(
              tooltip: t('delete'),
              icon: const Icon(Icons.delete_outline, size: 18),
              onPressed: () => _confirmDelete(n),
            ),
          ]),
        ],
      ),
    );
  }

  String _fullTime(DateTime time) {
    String two(int v) => v.toString().padLeft(2, '0');
    return '${two(time.day)}/${two(time.month)}/${time.year} '
        '${two(time.hour)}:${two(time.minute)}';
  }

  Future<void> _confirmDelete(AppNotification n) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(t('delete')),
        content: Text(n.title),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(t('cancel'))),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(t('delete')),
          ),
        ],
      ),
    );
    if (ok == true) {
      await NotificationService().deleteNotification(n.id);
      if (mounted) setState(() => _expandedIds.remove(n.id));
    }
  }
}
