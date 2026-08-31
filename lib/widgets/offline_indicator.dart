// widgets/offline_indicator.dart
// COMPLETE FIXED VERSION WITH RESPONSIVE DESIGN & INTERNET QUALITY DETECTION

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:drinks_calculator_fixed/providers/auth_provider.dart';
import 'package:drinks_calculator_fixed/providers/drink_provider.dart';
import 'package:drinks_calculator_fixed/providers/order_provider.dart';
import 'package:drinks_calculator_fixed/providers/inventory_provider.dart';

class OfflineIndicator extends StatefulWidget {
  final Widget child;
  final bool showForAllUsers; // ✅ Option to show for all users

  const OfflineIndicator({
    super.key,
    required this.child,
    this.showForAllUsers = false,
  });

  @override
  State<OfflineIndicator> createState() => _OfflineIndicatorState();
}

class _OfflineIndicatorState extends State<OfflineIndicator>
    with SingleTickerProviderStateMixin {
  // ========== CONNECTIVITY STATE ==========
  bool _isOffline = false;
  bool _isChecking = true;
  bool _isSlowConnection = false;
  double _connectionQuality = 1.0; // 1.0 = good, 0.0 = bad

  // ========== ANIMATION ==========
  late AnimationController _slideController;
  late Animation<Offset> _slideAnimation;

  // ========== TIMERS ==========
  Timer? _qualityCheckTimer;
  Timer? _hideTimer;

  @override
  void initState() {
    super.initState();

    // ✅ Initialize animation
    _slideController = AnimationController(
      duration: const Duration(milliseconds: 400),
      vsync: this,
    );
    _slideAnimation = Tween<Offset>(
      begin: const Offset(0, -1),
      end: Offset.zero,
    ).animate(CurvedAnimation(
      parent: _slideController,
      curve: Curves.easeOut,
    ));

    _checkConnectivity();

    // ✅ Listen to connectivity changes
    Connectivity().onConnectivityChanged.listen((result) {
      final isOffline = result == ConnectivityResult.none;
      final isSlow = _isSlowConnection;

      if (_isOffline != isOffline || _isSlowConnection != isSlow) {
        setState(() {
          _isOffline = isOffline;
          _isChecking = false;
        });

        if (isOffline) {
          _showOfflineToast();
          _slideController.forward();
        } else if (_isSlowConnection) {
          _showSlowConnectionToast();
          _slideController.forward();
        } else {
          _showOnlineToast();
          _hideBannerAfterDelay();
        }
      }
    });

    // ✅ Check connection quality periodically
    _qualityCheckTimer = Timer.periodic(const Duration(seconds: 10), (timer) {
      _checkConnectionQuality();
    });
  }

  @override
  void dispose() {
    _slideController.dispose();
    _qualityCheckTimer?.cancel();
    _hideTimer?.cancel();
    super.dispose();
  }

  // ============================================================
  // 🔍 CONNECTIVITY CHECKS
  // ============================================================

  Future<void> _checkConnectivity() async {
    final result = await Connectivity().checkConnectivity();
    setState(() {
      _isOffline = result == ConnectivityResult.none;
      _isChecking = false;
    });

    if (!_isOffline) {
      await _checkConnectionQuality();
    }

    if (_isOffline) {
      _slideController.forward();
    }
  }

  Future<void> _checkConnectionQuality() async {
    try {
      // ✅ Check connection quality by measuring response time
      final stopwatch = Stopwatch()..start();
      final result = await Connectivity().checkConnectivity();
      stopwatch.stop();

      final isOffline = result == ConnectivityResult.none;

      if (!isOffline) {
        // ✅ Calculate quality based on response time
        final responseTime = stopwatch.elapsedMilliseconds;
        final quality = _calculateQuality(responseTime);

        setState(() {
          _connectionQuality = quality;
          _isSlowConnection = quality < 0.5;
          _isOffline = false;
          _isChecking = false;
        });

        if (_isSlowConnection) {
          _slideController.forward();
        } else {
          _hideBannerAfterDelay();
        }
      }
    } catch (e) {
      // Ignore
    }
  }

  double _calculateQuality(int responseTime) {
    if (responseTime < 200) return 1.0; // Excellent
    if (responseTime < 500) return 0.8; // Good
    if (responseTime < 1000) return 0.5; // Fair
    if (responseTime < 2000) return 0.3; // Poor
    return 0.1; // Very poor
  }

  void _hideBannerAfterDelay() {
    _hideTimer?.cancel();
    _hideTimer = Timer(const Duration(seconds: 3), () {
      if (mounted && !_isOffline && !_isSlowConnection) {
        _slideController.reverse();
      }
    });
  }

  // ============================================================
  // 🎨 TOAST NOTIFICATIONS
  // ============================================================

  void _showOfflineToast() {
    final user = Provider.of<AuthProvider>(context, listen: false).currentUser;
    final isCompanyUser = _isCompanyUser(user);

    if (!isCompanyUser && !widget.showForAllUsers) return;

    if (mounted && context.mounted) {
      ScaffoldMessenger.of(context).clearSnackBars();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              const Icon(Icons.wifi_off, color: Colors.white, size: 20),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  'You are offline. ${isCompanyUser ? "Company data may not be up to date." : "Some features may not work."}',
                ),
              ),
            ],
          ),
          backgroundColor: Colors.red,
          duration: const Duration(seconds: 5),
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
        ),
      );
    }
  }

  void _showSlowConnectionToast() {
    final user = Provider.of<AuthProvider>(context, listen: false).currentUser;
    final isCompanyUser = _isCompanyUser(user);

    if (!isCompanyUser && !widget.showForAllUsers) return;

    if (mounted && context.mounted) {
      ScaffoldMessenger.of(context).clearSnackBars();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              const Icon(Icons.signal_wifi_4_bar, color: Colors.white, size: 20),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  'Slow internet connection. Data may load slowly.',
                ),
              ),
            ],
          ),
          backgroundColor: Colors.orange,
          duration: const Duration(seconds: 4),
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
        ),
      );
    }
  }

  void _showOnlineToast() {
    final user = Provider.of<AuthProvider>(context, listen: false).currentUser;
    final isCompanyUser = _isCompanyUser(user);

    if (!isCompanyUser && !widget.showForAllUsers) return;

    if (mounted && context.mounted) {
      ScaffoldMessenger.of(context).clearSnackBars();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              const Icon(Icons.wifi, color: Colors.white, size: 20),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  'Back online! ${isCompanyUser ? "Data will sync automatically." : ""}',
                ),
              ),
            ],
          ),
          backgroundColor: Colors.green,
          duration: const Duration(seconds: 3),
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
        ),
      );
    }
  }

  // ============================================================
  // 🔍 HELPER METHODS
  // ============================================================

  bool _isCompanyUser(User? user) {
    if (user == null) return false;
    return user.role == 'Manager' ||
        user.role == 'Staff' ||
        user.role == 'Administrator';
  }

  bool _shouldShowBanner(User? user) {
    if (widget.showForAllUsers) return true;
    return _isCompanyUser(user);
  }

  // ============================================================
  // 🔄 REFRESH DATA
  // ============================================================

  Future<void> _refreshData() async {
    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    final user = authProvider.currentUser;

    if (!_shouldShowBanner(user)) return;

    // ✅ Check if back online
    if (_isOffline) {
      if (mounted && context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Please connect to the internet first.'),
            backgroundColor: Colors.orange,
            duration: Duration(seconds: 2),
          ),
        );
      }
      return;
    }

    final drinkProvider = Provider.of<DrinkProvider>(context, listen: false);
    final orderProvider = Provider.of<OrderProvider>(context, listen: false);
    final inventoryProvider =
        Provider.of<InventoryProvider>(context, listen: false);

    try {
      if (mounted && context.mounted) {
        ScaffoldMessenger.of(context).clearSnackBars();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(width: 12),
                const Text('Refreshing data...'),
              ],
            ),
            backgroundColor: Colors.blue,
            duration: const Duration(seconds: 2),
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
            ),
          ),
        );
      }

      await drinkProvider.loadDrinksFromSupabase();
      await orderProvider.loadOrdersFromSupabase();
      await inventoryProvider.loadInventoryFromSupabase();

      if (mounted && context.mounted) {
        ScaffoldMessenger.of(context).clearSnackBars();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Icon(Icons.check_circle, color: Colors.white, size: 20),
                const SizedBox(width: 12),
                const Text('✅ Data refreshed successfully!'),
              ],
            ),
            backgroundColor: Colors.green,
            duration: const Duration(seconds: 2),
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
            ),
          ),
        );
      }

      _slideController.reverse();
    } catch (e) {
      if (mounted && context.mounted) {
        ScaffoldMessenger.of(context).clearSnackBars();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Icon(Icons.error, color: Colors.white, size: 20),
                const SizedBox(width: 12),
                Expanded(
                  child: Text('❌ Failed to refresh: $e'),
                ),
              ],
            ),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 3),
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
            ),
          ),
        );
      }
    }
  }

  // ============================================================
  // 🏗️ BUILD - RESPONSIVE
  // ============================================================

  @override
  Widget build(BuildContext context) {
    final authProvider = Provider.of<AuthProvider>(context);
    final user = authProvider.currentUser;
    final shouldShow = _shouldShowBanner(user);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final screenWidth = MediaQuery.of(context).size.width;
    final isMobile = screenWidth < 600;

    // ✅ Only show offline indicator for company users (or if enabled for all)
    if (!shouldShow) {
      return widget.child;
    }

    // ✅ Show loading while checking
    if (_isChecking) {
      return widget.child;
    }

    // ✅ Only show the banner when OFFLINE or SLOW CONNECTION
    final bool showBanner = _isOffline || _isSlowConnection;

    return Stack(
      children: [
        widget.child,
        if (showBanner && shouldShow)
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: SlideTransition(
              position: _slideAnimation,
              child: Material(
                elevation: 4,
                child: Container(
                  padding: EdgeInsets.symmetric(
                    vertical: isMobile ? 10 : 12,
                    horizontal: isMobile ? 12 : 20,
                  ),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: _isOffline
                          ? [Colors.red.shade700, Colors.red.shade900]
                          : [Colors.orange.shade600, Colors.orange.shade800],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.2),
                        blurRadius: 8,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: SafeArea(
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        // ✅ Icon
                        Container(
                          padding: const EdgeInsets.all(4),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.2),
                            shape: BoxShape.circle,
                          ),
                          child: Icon(
                            _isOffline ? Icons.wifi_off : Icons.signal_wifi_4_bar,
                            color: Colors.white,
                            size: isMobile ? 18 : 20,
                          ),
                        ),
                        const SizedBox(width: 10),

                        // ✅ Message
                        Expanded(
                          child: Text(
                            _isOffline
                                ? 'You are offline. Company data may not be up to date.'
                                : 'Slow internet connection. Data may load slowly.',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: isMobile ? 12 : 14,
                              fontWeight: FontWeight.w500,
                            ),
                            overflow: TextOverflow.ellipsis,
                            maxLines: 2,
                          ),
                        ),

                        // ✅ Retry Button
                        GestureDetector(
                          onTap: _refreshData,
                          child: Container(
                            padding: EdgeInsets.symmetric(
                              horizontal: isMobile ? 10 : 14,
                              vertical: isMobile ? 6 : 8,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.2),
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(
                                color: Colors.white.withValues(alpha: 0.3),
                                width: 1,
                              ),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  Icons.refresh,
                                  color: Colors.white,
                                  size: isMobile ? 14 : 16,
                                ),
                                if (!isMobile) ...[
                                  const SizedBox(width: 4),
                                  Text(
                                    'Retry',
                                    style: TextStyle(
                                      color: Colors.white,
                                      fontSize: 12,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ),
                        ),

                        // ✅ Close Button (only for slow connection)
                        if (_isSlowConnection && !_isOffline)
                          IconButton(
                            icon: Icon(
                              Icons.close,
                              color: Colors.white,
                              size: isMobile ? 18 : 20,
                            ),
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(),
                            onPressed: () {
                              _slideController.reverse();
                              _hideTimer?.cancel();
                            },
                            tooltip: 'Dismiss',
                          ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}