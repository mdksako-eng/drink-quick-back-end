// widgets/professional_sync_indicator.dart
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:drinks_calculator_fixed/providers/sync_provider.dart';

class ProfessionalSyncIndicator extends StatefulWidget {
  final Widget child;
  final bool showStatusText;

  const ProfessionalSyncIndicator({
    Key? key,
    required this.child,
    this.showStatusText = true,
  }) : super(key: key);

  @override
  State<ProfessionalSyncIndicator> createState() => _ProfessionalSyncIndicatorState();
}

class _ProfessionalSyncIndicatorState extends State<ProfessionalSyncIndicator>
    with SingleTickerProviderStateMixin {
  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      duration: const Duration(milliseconds: 1500),
      vsync: this,
    )..repeat(reverse: true);
    _pulseAnimation = Tween<double>(begin: 1.0, end: 1.3).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        widget.child,
        Positioned(
          bottom: 20,
          right: 20,
          child: Consumer<SyncProvider>(
            builder: (context, syncProvider, _) {
              return AnimatedOpacity(
                duration: const Duration(milliseconds: 300),
                opacity: syncProvider.status == SyncStatus.idle ? 0.7 : 1.0,
                child: GestureDetector(
                  onTap: () {
                    if (syncProvider.status != SyncStatus.syncing) {
                      syncProvider.manualSync();
                      _showSyncToast(context, syncProvider);
                    }
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                    decoration: BoxDecoration(
                      gradient: _getGradient(syncProvider.status),
                      borderRadius: BorderRadius.circular(30),
                      boxShadow: [
                        BoxShadow(
                          color: _getShadowColor(syncProvider.status).withValues(alpha: 0.5),
                          blurRadius: 12,
                          offset: const Offset(0, 4),
                        ),
                      ],
                      border: Border.all(
                        color: Colors.white.withValues(alpha: 0.2),
                        width: 1,
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        _buildIcon(syncProvider.status),
                        const SizedBox(width: 10),
                        if (widget.showStatusText)
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                _getStatusText(syncProvider.status),
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              if (syncProvider.lastSyncTime != null)
                                Text(
                                  _formatTimeAgo(syncProvider.lastSyncTime!),
                                  style: const TextStyle(
                                    color: Colors.white70,
                                    fontSize: 10,
                                  ),
                                ),
                            ],
                          ),
                        const SizedBox(width: 8),
                        if (_hasAction(syncProvider.status))
                          Container(
                            padding: const EdgeInsets.all(4),
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.2),
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: const Icon(
                              Icons.refresh,
                              size: 14,
                              color: Colors.white,
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildIcon(SyncStatus status) {
    switch (status) {
      case SyncStatus.syncing:
        return ScaleTransition(
          scale: _pulseAnimation,
          child: const SizedBox(
            width: 20,
            height: 20,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: Colors.white,
            ),
          ),
        );
      case SyncStatus.success:
        return const Icon(Icons.cloud_done, color: Colors.white, size: 20);
      case SyncStatus.error:
        return const Icon(Icons.cloud_off, color: Colors.white, size: 20);
      case SyncStatus.offline:
        return const Icon(Icons.wifi_off, color: Colors.white, size: 20);
      case SyncStatus.idle:
        return const Icon(Icons.cloud_queue, color: Colors.white70, size: 20);
    }
  }

  String _getStatusText(SyncStatus status) {
    switch (status) {
      case SyncStatus.syncing:
        return 'Syncing...';
      case SyncStatus.success:
        return 'Synced';
      case SyncStatus.error:
        return 'Sync failed';
      case SyncStatus.offline:
        return 'Offline';
      case SyncStatus.idle:
        return 'Cloud ready';
    }
  }

  String _formatTimeAgo(DateTime time) {
    final now = DateTime.now();
    final diff = now.difference(time);
    if (diff.inSeconds < 60) return 'Just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    return '${diff.inDays}d ago';
  }

  Gradient _getGradient(SyncStatus status) {
    switch (status) {
      case SyncStatus.syncing:
        return const LinearGradient(
          colors: [Color(0xFF667EEA), Color(0xFF764BA2)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        );
      case SyncStatus.success:
        return const LinearGradient(
          colors: [Color(0xFF11998E), Color(0xFF38EF7D)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        );
      case SyncStatus.error:
        return const LinearGradient(
          colors: [Color(0xFFEB3349), Color(0xFFF45C43)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        );
      case SyncStatus.offline:
        return const LinearGradient(
          colors: [Color(0xFF4B6CB7), Color(0xFF182848)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        );
      case SyncStatus.idle:
        return const LinearGradient(
          colors: [Color(0xFF2C3E50), Color(0xFF3498DB)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        );
    }
  }

  Color _getShadowColor(SyncStatus status) {
    switch (status) {
      case SyncStatus.syncing:
        return const Color(0xFF667EEA);
      case SyncStatus.success:
        return const Color(0xFF11998E);
      case SyncStatus.error:
        return const Color(0xFFEB3349);
      case SyncStatus.offline:
        return const Color(0xFF4B6CB7);
      case SyncStatus.idle:
        return const Color(0xFF2C3E50);
    }
  }

  bool _hasAction(SyncStatus status) {
    return status == SyncStatus.error || status == SyncStatus.offline;
  }

  void _showSyncToast(BuildContext context, SyncProvider syncProvider) {
    if (syncProvider.status == SyncStatus.syncing) return;
    
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.sync, color: Colors.white, size: 18),
            const SizedBox(width: 12),
            const Expanded(child: Text('Manual sync started...')),
          ],
        ),
        duration: const Duration(seconds: 2),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        backgroundColor: const Color(0xFF2C3E50),
      ),
    );
  }
}